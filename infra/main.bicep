@description('The name of the web application')
@maxLength(14)
param appName string

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

// Storage Account with Blob Container
module storageAccount_AVM 'br/public:avm/res/storage/storage-account:0.29.0' = {
  params: {
    name: toLower(storageAccountName)
    skuName: storageSku
    kind: 'StorageV2'
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    blobServices: {
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: 7
      containers: [
        {
          name: storageContainerName
          publicAccess: 'None'
        }
      ]
    }
    roleAssignments: [
      {
        principalId: uami_AVM.outputs.principalId
        roleDefinitionIdOrName: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
      }
      {
        principalId: deployer().objectId
        roleDefinitionIdOrName: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
      }
    ]
  }
}

// User Assigned Managed Identity for Web App
module uami_AVM 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.2' = {
  params: {
    name: uamiName
  }
}

module appReg 'modules/appregistration.bicep' = {
  name: 'reg'
  params: {
    clientAppName: webAppName
    clientAppDisplayName: 'MagicFiles Web App'
    issuer: issuer
    webAppEndpoint: 'https://${webSsite_AVM.outputs.defaultHostname}'
    webAppIdentityId: uami_AVM.outputs.principalId
  }
}

module webServerFarm_AVM 'br/public:avm/res/web/serverfarm:0.5.0' = {
  params: {
    name: appServicePlanName
    skuName: appServicePlanSku
    kind: 'linux'
    reserved: true
  }
}

module webSsite_AVM 'br/public:avm/res/web/site:0.19.4' = {
  params: {
    name: webAppName
    kind: 'app'
    serverFarmResourceId: webServerFarm_AVM.outputs.resourceId
    managedIdentities: {
      userAssignedResourceIds: [
        uami_AVM.outputs.resourceId
      ]
    }
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|24-lts'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      alwaysOn: appServicePlanSku != 'F1'
      appSettings: [
        {
          name: 'AZURE_STORAGE_ACCOUNT_NAME'
          value: storageAccount_AVM.outputs.name
        }
        {
          name: 'AZURE_STORAGE_CONTAINER_NAME'
          value: storageContainerName
        }
        {
          name: 'OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID'
          value: uami_AVM.outputs.clientId
        }
      ]
    }
  }
}

module webauth 'br/public:avm/res/web/site/config:0.1.1' = {
  params: {
    name: 'authsettingsV2'
    appName: webSsite_AVM.outputs.name
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

// Outputs
@description('The URL of the deployed Web App')
output webAppUrl string = 'https://${webSsite_AVM.outputs.defaultHostname}'
