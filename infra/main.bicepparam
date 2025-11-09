using './main.bicep'

// Parameters
param appName = 'MagicFiles'
param location = 'westeurope'
param environment = 'dev'
param appServicePlanSku = 'B1'
param storageSku = 'Standard_LRS'
param repoUrl = 'https://github.com/PieterbasNagengast/Azure-SimpleExampleWebApp.git'
