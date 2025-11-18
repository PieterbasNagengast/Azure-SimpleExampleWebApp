extension microsoftGraphV1

param issuer string
param clientAppName string
param clientAppDisplayName string
param clientAppScopes array = ['User.Read', 'offline_access', 'openid', 'profile']
param webAppEndpoint string
param webAppIdentityId string
param serviceManagementReference string = ''

param cloudEnvironment string = environment().name
param audiences object = {
  AzureCloud: {
    uri: 'api://AzureADTokenExchange'
  }
  AzureUSGovernment: {
    uri: 'api://AzureADTokenExchangeUSGov'
  }
  AzureChinaCloud: {
    uri: 'api://AzureADTokenExchangeChina'
  }
}

// Get the MS Graph Service Principal based on its application ID:
var msGraphAppId = '00000003-0000-0000-c000-000000000000'
resource msGraphSP 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: msGraphAppId
}

var graphScopes = msGraphSP.oauth2PermissionScopes
resource clientApp 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: clientAppName
  displayName: clientAppDisplayName
  signInAudience: 'AzureADMyOrg'
  serviceManagementReference: empty(serviceManagementReference) ? null : serviceManagementReference
  web: {
    implicitGrantSettings: {
      enableIdTokenIssuance: true
      enableAccessTokenIssuance: true
    }
  }
  spa: {
    redirectUris: [
      '${webAppEndpoint}/.auth/login/aad/callback'
    ]
  }
  requiredResourceAccess: [
    {
      resourceAppId: msGraphAppId
      resourceAccess: [
        for (scope, i) in clientAppScopes: {
          id: filter(graphScopes, graphScopes => graphScopes.value == scope)[0].id
          type: 'Scope'
        }
      ]
    }
  ]

  resource clientAppFic 'federatedIdentityCredentials@v1.0' = {
    name: '${clientApp.uniqueName}/miAsFic'
    audiences: [
      audiences[cloudEnvironment].uri
    ]
    issuer: issuer
    subject: webAppIdentityId
  }
}

resource clientSp 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: clientApp.appId
}

output clientAppId string = clientApp.appId
output clientSpId string = clientSp.id
