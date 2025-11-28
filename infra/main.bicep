@description('The name of the web application')
@maxLength(14)
param appName string

@description('The SKU for the App Service Plan')
@allowed([
  'B1'
  'P1v3'
])
param appServicePlanSku string = 'P1v3'

@description('The capacity (number of instances) for the App Service Plan')
param skuCapacity int = 1

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

@description('Application title displayed in the header')
param appTitle string = 'MagicFiles'

@description('Application subtitle displayed in the header')
param appSubtitle string = 'Your secure cloud file manager'

@description('The address prefix for the Virtual Network')
param vnetAddressPrefix string = '192.168.0.0/25'

@description('Enable AVM telemetry for the Virtual Network')
param avmTelemetry bool = false

// Variable to create unique suffix for resource names
var uniqueSuffix = take(uniqueString(resourceGroup().id), 5)

// Variables to generate resource names
var storageAccountName = 'st${appName}${uniqueSuffix}'
var appServicePlanName = 'asp-${appName}-${uniqueSuffix}'
var webAppName = 'app-${appName}-${uniqueSuffix}'
var uamiName = 'uami-${appName}-${uniqueSuffix}'
var vnetName = 'vnet-${appName}-${uniqueSuffix}'
var nsgWebAppName = 'nsg-webapp-subnet-${appName}-${uniqueSuffix}'
var nsgPrivateEndpointName = 'nsg-pe-subnet-${appName}-${uniqueSuffix}'
var lawName = 'law-${appName}-${uniqueSuffix}'
var storageContainerName = 'uploads'

// Networking Module
module network 'modules/network.bicep' = {
  name: 'networking'
  params: {
    vnetName: vnetName
    vnetAddressPrefix: vnetAddressPrefix
    nsgWebAppName: nsgWebAppName
    nsgPrivateEndpointName: nsgPrivateEndpointName
    avmTelemetry: avmTelemetry
  }
}

// Backend Module (Deploys Storage Account with Private Endpoint, LAW, etc.)
module backEnd 'modules/backend.bicep' = {
  name: 'backend'
  params: {
    storageAccountName: storageAccountName
    storageSku: storageSku
    storageContainerName: storageContainerName
    subnetResourceId: network.outputs.subnetPrivateEndpointId
    privateDnsZoneResourceId: network.outputs.privDNSzoneId
    lawName: lawName
    principalId: frontEnd.outputs.uamiPrincipalId
    avmTelemetry: avmTelemetry
  }
}

// Frontend Module (deploys Web App, App Service Plan, UAMI, etc.)
module frontEnd 'modules/frontend.bicep' = {
  name: 'frontend'
  params: {
    appServicePlanName: appServicePlanName
    appServicePlanSku: appServicePlanSku
    skuCapacity: skuCapacity
    webAppName: webAppName
    storageAccountName: storageAccountName
    storageContainerName: storageContainerName
    virtualNetworkSubnetResourceId: network.outputs.subnetWebAppId
    maxFileSizeMB: maxFileSizeMB
    allowedFileTypes: allowedFileTypes
    defaultThemeMode: defaultThemeMode
    appTitle: appTitle
    appSubtitle: appSubtitle
    uamiName: uamiName
    avmTelemetry: avmTelemetry
  }
}

// Outputs
@description('The URL of the deployed Web App')
output webAppUrl string = frontEnd.outputs.url

@description('The name of the deployed Web App')
output webAppName string = frontEnd.outputs.webAppName
