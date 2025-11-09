@description('The name of the web application')
@maxLength(14)
param appName string

@description('The location for all resources')
param location string = resourceGroup().location

@description('The environment name (dev, test, prod)')
@allowed([
  'dev'
  'tst'
  'prd'
])
param environment string = 'dev'

@description('The SKU for the App Service Plan')
@allowed([
  'F1'
  'B1'
  'B2'
  'S1'
  'P1V2'
])
param appServicePlanSku string = 'B1'

@description('The SKU for the Storage Account')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageSku string = 'Standard_LRS'

@description('The URL of the Git repository for the Web App source code')
param repoUrl string

// Variables
var uniqueSuffix = take(uniqueString(resourceGroup().id), 5)
var storageAccountName = 'st${replace(appName, '-', '')}${environment}${uniqueSuffix}'
var appServicePlanName = 'asp-${appName}-${environment}'
var webAppName = 'app-${appName}-${environment}-${uniqueSuffix}'
var storageContainerName = 'uploads'

// Tags
var commonTags = {
  Environment: environment
  Application: appName
  ManagedBy: 'Bicep'
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: toLower(storageAccountName)
  location: location
  tags: commonTags
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Blob Service
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Blob Container for uploads
resource uploadContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: storageContainerName
  properties: {
    publicAccess: 'None'
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: commonTags
  sku: {
    name: appServicePlanSku
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// Web App
resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|24-lts'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      alwaysOn: appServicePlanSku != 'F1'
      appSettings: [
        {
          name: 'AZURE_STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        {
          name: 'AZURE_STORAGE_CONTAINER_NAME'
          value: storageContainerName
        }
        {
          name: 'NODE_ENV'
          value: environment
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~20'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'ENABLE_ORYX_BUILD'
          value: 'true'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '0'
        }
        {
          name: 'PROJECT'
          value: 'src/app'
        }
      ]
    }
  }
}

resource webAppxx 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-11-01' = {
  name: 'scm'
  parent: webApp
  properties: {
    allow: true
  }
}

resource webAppSourceControl 'Microsoft.Web/sites/sourcecontrols@2024-11-01' = {
  name: 'web'
  parent: webApp
  properties: {
    branch: 'main'
    repoUrl: repoUrl
    isGitHubAction: false
    isManualIntegration: true
    isMercurial: false
  }
}

// Role Assignment: Storage Blob Data Contributor for Web App (Managed Identity)
resource roleAssignment1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, webApp.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment: Storage Blob Data Contributor for Use (Deployer)
resource roleAssignment2 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, webApp.id, deployer().objectId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
    principalId: deployer().objectId
    principalType: 'User'
  }
}

// Outputs
@description('The name of the deployed Web App')
output webAppName string = webApp.name

@description('The URL of the deployed Web App')
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'

@description('The name of the Storage Account')
output storageAccountName string = storageAccount.name

@description('The name of the upload container')
output containerName string = storageContainerName

@description('The resource group name')
output resourceGroupName string = resourceGroup().name
