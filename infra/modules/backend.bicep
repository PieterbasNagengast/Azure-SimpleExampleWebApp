param storageAccountName string
param storageSku string
param storageContainerName string
param subnetResourceId string
param privateDnsZoneResourceId string
param principalIds array
param lawName string
param visionAccountName string
param avmTelemetry bool

// Storage Account with Blob Container
module storageAccount 'br/public:avm/res/storage/storage-account:0.29.0' = {
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
    customDomainUseSubDomainName: false
    privateEndpoints: [
      {
        service: 'blob'
        subnetResourceId: subnetResourceId
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: privateDnsZoneResourceId
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
      diagnosticSettings: [
        {
          name: 'storageDiagnostics'
          workspaceResourceId: law.outputs.resourceId
          logCategoriesAndGroups: [
            {
              categoryGroup: 'AllLogs'
              enabled: true
            }
          ]
        }
      ]
    }
    roleAssignments: [
      for principalId in principalIds: {
        principalId: principalId
        roleDefinitionIdOrName: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
      }
    ]
    enableTelemetry: avmTelemetry
  }
}

// Log Analytics Workspace
module law 'br/public:avm/res/operational-insights/workspace:0.13.0' = {
  params: {
    name: lawName
    enableTelemetry: avmTelemetry
  }
}

// Azure AI Vision (Computer Vision) Account
module visionAccount 'br/public:avm/res/cognitive-services/account:0.14.0' = {
  params: {
    name: visionAccountName
    kind: 'ComputerVision'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    sku: 'S1'
    roleAssignments: [
      for principalId in principalIds: {
        principalId: principalId
        roleDefinitionIdOrName: 'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User
      }
    ]
    enableTelemetry: avmTelemetry
  }
}
