@description('The address prefix for the Virtual Network')
param vnetAddressPrefix string

@description('the name of the Virtual Network')
param vnetName string

@description('the name of the Network Security Group for the Web App subnet')
param nsgWebAppName string

@description('the name of the Network Security Group for the Private Endpoint subnet')
param nsgPrivateEndpointName string

@description('Enable AVM telemetry')
param avmTelemetry bool = false

module vnet 'br/public:avm/res/network/virtual-network:0.7.1' = {
  params: {
    name: vnetName
    addressPrefixes: [
      vnetAddressPrefix
    ]
    enableTelemetry: avmTelemetry
  }
}

module subnetWebApp 'br/public:avm/res/network/virtual-network/subnet:0.1.3' = {
  params: {
    name: 'webapp-subnet'
    virtualNetworkName: vnet.outputs.name
    addressPrefix: cidrSubnet(vnetAddressPrefix, 27, 0)
    networkSecurityGroupResourceId: nsgWebApp.outputs.resourceId
    delegation: 'Microsoft.Web/serverFarms'
    privateEndpointNetworkPolicies: 'Disabled'
    defaultOutboundAccess: false
    enableTelemetry: avmTelemetry
  }
}

module subnetPrivateEndpoint 'br/public:avm/res/network/virtual-network/subnet:0.1.3' = {
  params: {
    name: 'pe-subnet'
    virtualNetworkName: vnet.outputs.name
    addressPrefix: cidrSubnet(vnetAddressPrefix, 27, 1)
    networkSecurityGroupResourceId: nsgPrivateEndpoint.outputs.resourceId
    privateEndpointNetworkPolicies: 'Disabled'
    defaultOutboundAccess: false
    enableTelemetry: avmTelemetry
  }
  dependsOn: [
    subnetWebApp
  ]
}

module nsgWebApp 'br/public:avm/res/network/network-security-group:0.5.0' = {
  params: {
    name: nsgWebAppName
    enableTelemetry: avmTelemetry
  }
}

module nsgPrivateEndpoint 'br/public:avm/res/network/network-security-group:0.5.0' = {
  params: {
    name: nsgPrivateEndpointName
    enableTelemetry: avmTelemetry
  }
}

module blob_privDNSzone 'br/public:avm/res/network/private-dns-zone:0.3.0' = {
  params: {
    name: 'privatelink.blob.${environment().suffixes.storage}'
    virtualNetworkLinks: [
      {
        registrationEnabled: false
        virtualNetworkResourceId: vnet.outputs.resourceId
      }
    ]
    enableTelemetry: avmTelemetry
  }
}

module vision_privDNSzone 'br/public:avm/res/network/private-dns-zone:0.3.0' = {
  params: {
    name: 'privatelink.cognitiveservices.azure.com'
    virtualNetworkLinks: [
      {
        registrationEnabled: false
        virtualNetworkResourceId: vnet.outputs.resourceId
      }
    ]
    enableTelemetry: avmTelemetry
  }
}

output vnetId string = vnet.outputs.resourceId
output subnetWebAppId string = subnetWebApp.outputs.resourceId
output subnetPrivateEndpointId string = subnetPrivateEndpoint.outputs.resourceId
output nsgWebAppId string = nsgWebApp.outputs.resourceId
output nsgPrivateEndpointId string = nsgPrivateEndpoint.outputs.resourceId
output blob_privDNSzoneId string = blob_privDNSzone.outputs.resourceId
output vision_privDNSzoneId string = vision_privDNSzone.outputs.resourceId
