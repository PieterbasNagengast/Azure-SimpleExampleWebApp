param storageAccountName string
param storageSku string
param storageContainerName string
param subnetResourceId string
param privateDnsZoneResourceId string
param workspaceResourceId string
param principalId string
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
          workspaceResourceId: workspaceResourceId
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
      {
        principalId: principalId
        roleDefinitionIdOrName: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
      }
    ]
    enableTelemetry: avmTelemetry
  }
}
