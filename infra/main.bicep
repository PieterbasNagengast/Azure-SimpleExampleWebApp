extension microsoftGraphV1

@description('The name of the web application')
@maxLength(14)
param appName string

@description('The location for all resources')
param location string = resourceGroup().location

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
  'Standard_ZRS'
])
param storageSku string = 'Standard_LRS'

// Variables
var uniqueSuffix = take(uniqueString(resourceGroup().id), 5)
var issuer = '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'

// Resource names
var storageAccountName = 'st${appName}${uniqueSuffix}'
var appServicePlanName = 'asp-${appName}-${uniqueSuffix}'
var webAppName = 'app-${appName}-${uniqueSuffix}'
var uamiName = 'uami-${appName}-${uniqueSuffix}'
var storageContainerName = 'uploads'

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: toLower(storageAccountName)
  location: location
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

// User Assigned Managed Identity for Web App
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
  name: uamiName
  location: location
}

module appReg 'modules/appregistration.bicep' = {
  name: 'reg'
  params: {
    clientAppName: webAppName
    clientAppDisplayName: 'MagicFiles Web App'
    issuer: issuer
    webAppEndpoint: 'https://${webApp.properties.defaultHostName}'
    webAppIdentityId: uami.properties.clientId
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
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
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
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
          name: 'OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID'
          value: uami.properties.clientId
        }
      ]
    }
  }
}

resource webAppAuth 'Microsoft.Web/sites/config@2024-11-01' = {
  name: 'authsettingsV2'
  parent: webApp
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'AzureActiveDirectory'
      requireAuthentication: true
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true

        registration: {
          clientId: appReg.outputs.clientAppId
          clientSecretSettingName: 'OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID'
          openIdIssuer: issuer
        }
        validation: {
          defaultAuthorizationPolicy: {
            allowedApplications: []
          }
        }
      }
    }
    login: {
      tokenStore: {
        enabled: false
      }
    }
  }
}

// resource webAppSCM 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-11-01' = {
//   name: 'scm'
//   parent: webApp
//   properties: {
//     allow: true
//   }
// }

// resource webAppSourceControl 'Microsoft.Web/sites/sourcecontrols@2024-11-01' = {
//   name: 'web'
//   parent: webApp
//   properties: {
//     branch: 'main'
//     repoUrl: repoUrl
//     isGitHubAction: false
//     isManualIntegration: true
//     isMercurial: false
//   }
// }

// Role Assignment: Storage Blob Data Contributor for Web App (Managed Identity)
resource roleAssignment1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment: Storage Blob Data Contributor for Use (Deployer)
resource roleAssignment2 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, deployer().objectId)
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
