using './main.bicep'

// Parameters
param appName = 'MagicFiles'
param appServicePlanSku = 'P1v3'
param storageSku = 'Standard_LRS'
param appTitle = 'My Super Magic Files App'
param appSubtitle = 'Store and manage your files securely in the cloud'
param defaultThemeMode = 'auto'
param allowedFileTypes = '.docx,.pdf,.xlsx,.png,.jpg,.jpeg,.txt'
param skuCapacity = 1
