targetScope = 'subscription'
 
@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string
 
@minLength(1)
@description('Primary location for all resources')
param location string
 
var _abbrs = loadJsonContent('./abbreviations.json')
param deploymentTimestamp string = utcNow()
 
// Names parameters
 
param aiHubName string = ''
param aiProjectName string = ''
param resourceGroupName string = ''
param aiResourceGroupName string = ''
param appInsightsName string = ''
param appServiceName string = ''
var _appServiceName = !empty(appServiceName) ? appServiceName : '${_abbrs.webSitesAppService}${_resourceToken}'
param appServicePlanName string = ''
var _appServicePlanName = !empty(appServicePlanName) ? appServicePlanName : '${_abbrs.webSitesAppService}${_resourceToken}'
param containerRegistryName string = ''
param containerRepositoryName string = ''
var _containerRepositoryName = !empty(containerRepositoryName) ? containerRepositoryName : 'rag-project'
param keyVaultName string = ''
param logAnalyticsName string = ''
param openAiName string = ''
param searchServiceName string = ''
param storageAccountName string = ''
 
// Azure OpenAI parameters
 
param oaiApiVersion string = '2023-05-15'
param oaiChatDeployment string = 'gpt-35-turbo'
param oaiEmbeddingDeployment string = 'text-embedding-ada-002'
param oaiEmbeddingModel string = 'text-embedding-ada-002'
 
// Use sample data for Azure Search Index?
param azureSearchIndexSampleData string = ''
var _azureSearchIndexSampleData = !empty(azureSearchIndexSampleData) ? azureSearchIndexSampleData : 'true'
 
@description('User or service principal identity to assign application roles')
param principalId string = ''
param principalType string = 'ServicePrincipal'
 
// Flow parameters
 
param promptFlowWorkerNum string = ''
var _promptFlowWorkerNum = !empty(promptFlowWorkerNum) ? promptFlowWorkerNum : '1'
 
param promptFlowServingEngine string = ''
var _promptFlowServingEngine = !empty(promptFlowServingEngine) ? promptFlowServingEngine : 'fastapi'
 
var _resourceToken = toLower(uniqueString(subscription().id, environmentName, location, deploymentTimestamp))
var _keyVaultName = !empty(keyVaultName) ? keyVaultName : '${_abbrs.keyVaultVaults}${_resourceToken}'
 
 
// tags that should be applied to all resources.
var _tags = {
  // Tag all resources with the environment name.
  'azd-env-name': environmentName
}
 
// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${_abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: _tags
}
 
var _openAiConfig = loadYamlContent('./ai.yaml')
var _openAiModelDeployments = array(contains(_openAiConfig, 'deployments') ? _openAiConfig.deployments : [])
 
module ai 'core/host/ai-environment.bicep' = {
  name: 'ai'
  scope: resourceGroup(!empty(aiResourceGroupName) ? aiResourceGroupName : rg.name)
  params: {
    location: location
    tags: _tags
    hubName: !empty(aiHubName) ? aiHubName : 'ai-hub-${_resourceToken}'
    projectName: !empty(aiProjectName) ? aiProjectName : 'ai-project-${_resourceToken}'
    logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName  : '${_abbrs.operationalInsightsWorkspaces}${_resourceToken}'
    appInsightsName: !empty(appInsightsName) ? appInsightsName : '${_abbrs.insightsComponents}${_resourceToken}'
    containerRegistryName: !empty(containerRegistryName) ? containerRegistryName : '${_abbrs.containerRegistryRegistries}${_resourceToken}'
    keyVaultName: _keyVaultName
    storageAccountName: !empty(storageAccountName)? storageAccountName : '${_abbrs.storageStorageAccounts}${_resourceToken}'
    openAiName: !empty(openAiName) ? openAiName : 'aoai-${_resourceToken}'
    openAiModelDeployments: _openAiModelDeployments
    searchName: !empty(searchServiceName) ? searchServiceName : 'srch-${_resourceToken}'
  }
}
 
module appServicePlan './core/host/appserviceplan.bicep' = {
  name: 'appServicePlan'
  scope: rg
  params: {
    name: _appServicePlanName
    location: location
    tags: _tags
    sku: {
      name: 'P0v3'
      capacity: 1
    }
    kind: 'linux'
  }
}
 
module appService  'core/host/appservice.bicep'  = {
  name: 'appService'
  scope: rg
  params: {
    name: _appServiceName
    applicationInsightsName: ai.outputs.appInsightsName
    runtimeName: 'DOCKER'
    runtimeVersion: '${_containerRepositoryName}:dummy'
    keyVaultName: _keyVaultName
    location: location
    tags: union(_tags, { 'azd-service-name': 'rag-flow' })
    appServicePlanId: appServicePlan.outputs.id
    scmDoBuildDuringDeployment: false
    appSettings: {
      WEBSITES_ENABLE_APP_SERVICE_STORAGE: false
      DOCKER_REGISTRY_SERVER_URL: 'https://${ai.outputs.containerRegistryName}.azurecr.io'
      WEBSITES_PORT: '80'
      AZURE_SUBSCRIPTION_ID: subscription().subscriptionId
      AZURE_RESOURCE_GROUP: rg.name
      AZUREAI_PROJECT_NAME: ai.outputs.projectName
      PROMPTFLOW_WORKER_NUM: _promptFlowWorkerNum
      PROMPTFLOW_SERVING_ENGINE: _promptFlowServingEngine
      AZURE_OPENAI_ENDPOINT: ai.outputs.openAiEndpoint
      AZURE_OPENAI_CHAT_DEPLOYMENT: oaiChatDeployment
      AZURE_OPENAI_EMBEDDING_DEPLOYMENT: oaiEmbeddingDeployment
      AZURE_OPENAI_EMBEDDING_MODEL: oaiEmbeddingModel
      AZURE_OPENAI_API_VERSION: oaiApiVersion
      AZURE_SEARCH_ENDPOINT: ai.outputs.searchEndpoint
      acrUseManagedIdentityCreds: true
    }
  }
}
 
// output for post processing
 
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_PRINCIPAL_ID string = principalId
output AZURE_PRINCIPAL_TYPE string = principalType
 
output AZURE_OPENAI_ENDPOINT string = ai.outputs.openAiEndpoint
output AZURE_OPENAI_API_VERSION string = oaiApiVersion
output AZURE_OPENAI_CHAT_DEPLOYMENT string =  oaiChatDeployment
output AZURE_OPENAI_EMBEDDING_DEPLOYMENT string =  oaiEmbeddingDeployment
output AZURE_OPENAI_EMBEDDING_MODEL string =  oaiEmbeddingModel
 
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = ai.outputs.containerRegistryEndpoint
output AZURE_KEY_VAULT_ENDPOINT string = ai.outputs.keyVaultEndpoint
output AZURE_SEARCH_ENDPOINT string = ai.outputs.searchEndpoint
 
output AZUREAI_HUB_NAME string = ai.outputs.hubName
output AZUREAI_PROJECT_NAME string = ai.outputs.projectName
output AZURE_APP_INSIGHTS_NAME string = ai.outputs.appInsightsName
output AZURE_APP_SERVICE_NAME string = _appServiceName
output AZURE_APP_SERVICE_PLAN_NAME string = _appServicePlanName
output AZURE_CONTAINER_REGISTRY_NAME string = ai.outputs.containerRegistryName
output AZURE_CONTAINER_REPOSITORY_NAME string = _containerRepositoryName
 
output AZURE_KEY_VAULT_NAME string = ai.outputs.keyVaultName
output AZURE_LOG_ANALYTICS_NAME string = ai.outputs.logAnalyticsWorkspaceName
output AZURE_OPENAI_NAME string = ai.outputs.openAiName
output AZURE_SEARCH_NAME string = ai.outputs.searchName
output AZURE_STORAGE_ACCOUNT_NAME string = ai.outputs.storageAccountName
 
output PROMPTFLOW_WORKER_NUM string = _promptFlowWorkerNum
output PROMPTFLOW_SERVING_ENGINE string = _promptFlowServingEngine
output LOAD_AZURE_SEARCH_SAMPLE_DATA string = _azureSearchIndexSampleData
