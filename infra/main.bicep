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

@description('Maximum file size in MB for uploads')
@minValue(1)
@maxValue(500)
param maxFileSizeMB int = 100

@description('Comma-separated list of allowed file extensions (e.g., .pdf,.jpg,.png) or * for all types')
param allowedFileTypes string = '*'

@description('Default theme mode for the application')
@allowed([
  'auto'
  'light'
  'dark'
])
param defaultThemeMode string = 'auto'

@description('The address prefix for the Virtual Network')
param vnetAddressPrefix string = '192.168.0.0/25'

@description('Enable AVM telemetry for the Virtual Network')
param avmTelemetry bool = false

// Variables
var uniqueSuffix = take(uniqueString(resourceGroup().id), 5)
var issuer = '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'

// Resource names
var storageAccountName = 'st${appName}${uniqueSuffix}'
var appServicePlanName = 'asp-${appName}-${uniqueSuffix}'
var webAppName = 'app-${appName}-${uniqueSuffix}'
var uamiName = 'uami-${appName}-${uniqueSuffix}'
var vnetName = 'vnet-${appName}-${uniqueSuffix}'
var nsgWebAppName = 'nsg-webapp-subnet-${appName}-${uniqueSuffix}'
var nsgPrivateEndpointName = 'nsg-pe-subnet-${appName}-${uniqueSuffix}'
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
    publicNetworkAccess: 'Disabled'
    privateEndpoints: [
      {
        service: 'blob'
        subnetResourceId: networking.outputs.subnetPrivateEndpointId
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: networking.outputs.privDNSzoneId
            }
          ]
        }
      }
    ]
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
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
        principalId: webSsite_AVM.?outputs.?systemAssignedMIPrincipalId ?? ''
        roleDefinitionIdOrName: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
      }
      {
        principalId: deployer().objectId
        roleDefinitionIdOrName: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
      }
    ]
    enableTelemetry: avmTelemetry
  }
}

// User Assigned Managed Identity for Web App Entra ID authentication
module uami_AVM 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.2' = {
  params: {
    name: uamiName
    enableTelemetry: avmTelemetry
  }
}

// App Registration for Web App Entra ID authentication
module appReg 'modules/appregistration.bicep' = {
  name: 'AppRegistration'
  params: {
    clientAppName: webAppName
    clientAppDisplayName: 'MagicFiles Web App'
    issuer: issuer
    webAppEndpoint: 'https://${webSsite_AVM.outputs.defaultHostname}'
    webAppIdentityId: uami_AVM.outputs.principalId
  }
}

// App Service Plan
module webServerFarm_AVM 'br/public:avm/res/web/serverfarm:0.5.0' = {
  params: {
    name: appServicePlanName
    skuName: appServicePlanSku
    kind: 'linux'
    reserved: true
    enableTelemetry: avmTelemetry
  }
}

// Web App
module webSsite_AVM 'br/public:avm/res/web/site:0.19.4' = {
  params: {
    name: webAppName
    kind: 'app'
    serverFarmResourceId: webServerFarm_AVM.outputs.resourceId
    managedIdentities: {
      userAssignedResourceIds: [
        uami_AVM.outputs.resourceId
      ]
      systemAssigned: true
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
          value: storageAccountName
        }
        {
          name: 'AZURE_STORAGE_CONTAINER_NAME'
          value: storageContainerName
        }
        {
          name: 'MAX_FILE_SIZE_MB'
          value: string(maxFileSizeMB)
        }
        {
          name: 'ALLOWED_FILE_TYPES'
          value: allowedFileTypes
        }
        {
          name: 'DEFAULT_THEME_MODE'
          value: defaultThemeMode
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
      ]
    }
    publicNetworkAccess: 'Enabled'
    virtualNetworkSubnetResourceId: networking.outputs.subnetWebAppId
    enableTelemetry: avmTelemetry
  }
}

// Web App Authentication Settings
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
    enableTelemetry: avmTelemetry
  }
}

module networking 'modules/network.bicep' = {
  name: 'networking'
  params: {
    vnetName: vnetName
    vnetAddressPrefix: vnetAddressPrefix
    nsgWebAppName: nsgWebAppName
    nsgPrivateEndpointName: nsgPrivateEndpointName
    avmTelemetry: avmTelemetry
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
//   name: '${webSsite_AVM.outputs.name}/web'
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
