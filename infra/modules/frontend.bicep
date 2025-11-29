param appServicePlanName string
param appServicePlanSku string
param skuCapacity int
param avmTelemetry bool
param webAppName string
param storageAccountName string
param storageContainerName string

param virtualNetworkSubnetResourceId string

param maxFileSizeMB int
param allowedFileTypes string
param defaultThemeMode string
param appTitle string
param appSubtitle string

param uamiName string

var issuer = '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'

// User Assigned Managed Identity for Web App Entra ID authentication
module uami 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.2' = {
  params: {
    name: uamiName
    enableTelemetry: avmTelemetry
  }
}

// App Service Plan
module webServerFarm 'br/public:avm/res/web/serverfarm:0.5.0' = {
  params: {
    name: appServicePlanName
    skuName: appServicePlanSku
    kind: 'linux'
    reserved: true
    skuCapacity: skuCapacity
    zoneRedundant: false
    enableTelemetry: avmTelemetry
  }
}

// Web App
module webSsite 'br/public:avm/res/web/site:0.19.4' = {
  params: {
    name: webAppName
    kind: 'app'
    slots: [
      {
        name: 'dev'
      }
    ]
    serverFarmResourceId: webServerFarm.outputs.resourceId
    managedIdentities: {
      userAssignedResourceIds: [
        uami.outputs.resourceId
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
          name: 'APP_TITLE'
          value: appTitle
        }
        {
          name: 'APP_SUBTITLE'
          value: appSubtitle
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
      ]
    }
    publicNetworkAccess: 'Enabled'
    virtualNetworkSubnetResourceId: virtualNetworkSubnetResourceId
    enableTelemetry: avmTelemetry
  }
}

// Web App Authentication Settings
module webAuth 'br/public:avm/res/web/site/config:0.1.1' = {
  params: {
    name: 'authsettingsV2'
    appName: webSsite.outputs.name
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

// App Registration for Web App Entra ID authentication Module
module appReg 'appregistration.bicep' = {
  name: 'AppRegistration'
  params: {
    clientAppName: webAppName
    clientAppDisplayName: 'MagicFiles Web App'
    issuer: issuer
    webAppEndpoint: 'https://${webSsite.outputs.defaultHostname}'
    webAppIdentityId: uami.outputs.principalId
  }
}

output url string = 'https://${webSsite.outputs.defaultHostname}'
output uamiPrincipalId string = uami.outputs.principalId
output webAppName string = webSsite.outputs.name
