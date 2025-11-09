# Azure File Upload Solution

A complete Azure solution that enables users to upload files to Azure Storage through a web application. The infrastructure is deployed using Bicep and includes an Azure Web App and Storage Account with managed identity authentication.

## Architecture Overview

```
┌─────────────┐         ┌──────────────────┐         ┌──────────────────┐
│   User      │────────>│  Azure Web App   │────────>│  Azure Storage   │
│  (Browser)  │         │  (Node.js/Express│         │  (Blob Container)│
└─────────────┘         └──────────────────┘         └──────────────────┘
                                │
                                │ System-Assigned
                                │ Managed Identity
                                │ (RBAC: Storage Blob Data Contributor)
                                └─────────────────────────────────────────┘
```

### Components

1. **Azure App Service Plan** (Linux, Node.js 20 LTS)
   - Hosts the web application
   - Configurable SKU (default: B1)

2. **Azure Web App**
   - Node.js/Express application
   - System-assigned managed identity for secure authentication
   - HTTPS enforcement with TLS 1.2 minimum
   - Environment-based naming with unique suffixes

3. **Azure Storage Account**
   - Blob storage with private access
   - Dedicated container for uploads
   - 7-day soft delete retention policy
   - RBAC-based access control

4. **Web Application**
   - Drag-and-drop file upload interface
   - File type filtering (images, PDFs, documents)
   - Real-time file list display
   - Maximum 10MB file size limit

## Prerequisites

Before deploying this solution, ensure you have:

- **Azure Subscription**: An active Azure subscription with appropriate permissions
- **Azure CLI**: Version 2.50.0 or later ([Install](https://aka.ms/installazurecli))
- **Bicep**: Installed via Azure CLI (`az bicep install`)
- **Node.js**: Version 20 or later (for local development)
- **PowerShell**: Version 5.1 or later (Windows) or PowerShell Core 7+ (cross-platform)
- **Git**: For cloning the repository (optional)

### Verify Prerequisites

```powershell
# Check Azure CLI
az version

# Check Node.js
node --version

# Check PowerShell
$PSVersionTable.PSVersion

# Login to Azure
az login

# Set default subscription (if needed)
az account set --subscription "Your-Subscription-Name"
```

## Quick Start

### 1. Clone or Download the Repository

```powershell
cd c:\temp
git clone <repository-url> MinBZK-Example
cd MinBZK-Example
```

### 2. Deploy to Azure

Run the deployment script with your desired configuration:

```powershell
.\deploy.ps1 -ResourceGroupName "rg-fileupload-dev" -Location "westeurope"
```

The script will:
- ✓ Check prerequisites
- ✓ Create the resource group
- ✓ Deploy Azure infrastructure (Web App + Storage Account)
- ✓ Deploy the web application
- ✓ Display the application URL

### 3. Access the Application

Open the displayed URL in your browser and start uploading files!

## Deployment Options

### Basic Deployment

```powershell
.\deploy.ps1 -ResourceGroupName "rg-fileupload-dev"
```

### Production Deployment

```powershell
.\deploy.ps1 `
    -ResourceGroupName "rg-fileupload-prod" `
    -Location "westeurope" `
    -AppName "fileupload" `
    -Environment "prod"
```

### Application-Only Update (Skip Infrastructure)

```powershell
.\deploy.ps1 `
    -ResourceGroupName "rg-fileupload-dev" `
    -SkipInfrastructure
```

### Deploy to Different Azure Regions

```powershell
# Deploy to North Europe
.\deploy.ps1 -ResourceGroupName "rg-fileupload-dev" -Location "northeurope"

# Deploy to East US
.\deploy.ps1 -ResourceGroupName "rg-fileupload-dev" -Location "eastus"

# Deploy to West US
.\deploy.ps1 -ResourceGroupName "rg-fileupload-dev" -Location "westus"
```

## Configuration

### Deployment Parameters

| Parameter            | Description               | Default      | Options               |
| -------------------- | ------------------------- | ------------ | --------------------- |
| `ResourceGroupName`  | Azure resource group name | *Required*   | Any valid name        |
| `Location`           | Azure region              | `westeurope` | Any Azure region      |
| `AppName`            | Application name prefix   | `fileupload` | Any valid name        |
| `Environment`        | Environment designation   | `dev`        | `dev`, `test`, `prod` |
| `SkipInfrastructure` | Skip Bicep deployment     | `false`      | Switch parameter      |

### Infrastructure Parameters (main.bicepparam)

You can customize the infrastructure by modifying `infra/main.bicepparam`:

```bicep
param appServicePlanSku = 'B1'      // B1, S1, P1V2, P2V2, etc.
param storageSku = 'Standard_LRS'   // Standard_LRS, Standard_GRS, etc.
```

### Application Configuration

The application is configured through environment variables set in the Bicep template:

- `AZURE_STORAGE_CONNECTION_STRING`: Automatically configured via Managed Identity
- `NODE_ENV`: Set to the environment parameter
- `PORT`: Default 8080 (configured by Azure)

## File Upload Specifications

### Supported File Types

- **Images**: `.jpg`, `.jpeg`, `.png`, `.gif`, `.bmp`, `.webp`, `.svg`
- **Documents**: `.pdf`, `.doc`, `.docx`, `.xls`, `.xlsx`, `.ppt`, `.pptx`, `.txt`

### Limitations

- Maximum file size: **10MB**
- File type validation: Server-side and client-side
- Storage container: `uploads` (automatically created)

## Local Development

### Setup

1. Install dependencies:
   ```powershell
   cd app
   npm install
   ```

2. Create `.env` file:
   ```powershell
   cp .env.example .env
   ```

3. Configure Azure Storage connection string in `.env`:
   ```
   AZURE_STORAGE_CONNECTION_STRING=<your-connection-string>
   NODE_ENV=development
   ```

### Run Locally

```powershell
npm start
```

The application will be available at `http://localhost:3000`

### Development Commands

```powershell
# Install dependencies
npm install

# Start development server
npm start

# Run tests (if available)
npm test
```

## Monitoring and Troubleshooting

### View Application Logs

```powershell
# Stream live logs
az webapp log tail --name <web-app-name> --resource-group <resource-group-name>

# Download logs
az webapp log download --name <web-app-name> --resource-group <resource-group-name>
```

### Check Application Status

```powershell
# Get web app status
az webapp show --name <web-app-name> --resource-group <resource-group-name> --query state

# Test health endpoint
curl https://<web-app-name>.azurewebsites.net/health
```

### Common Issues

#### Issue: "Cannot upload files"
- **Solution**: Check that the Managed Identity has the "Storage Blob Data Contributor" role assigned
- **Verify**: `az role assignment list --scope <storage-account-id>`

#### Issue: "Deployment failed"
- **Solution**: Check Azure CLI is logged in: `az account show`
- **Solution**: Verify subscription has sufficient quota for resources

#### Issue: "Application not starting"
- **Solution**: Check application logs: `az webapp log tail`
- **Solution**: Verify Node.js version in package.json matches App Service runtime

## Security Features

- ✓ **Managed Identity**: No storage keys in code or configuration
- ✓ **RBAC**: Role-based access control for storage
- ✓ **HTTPS Only**: Enforced for all connections
- ✓ **TLS 1.2+**: Minimum TLS version enforced
- ✓ **Private Blob Access**: Blobs not publicly accessible
- ✓ **File Validation**: Server-side file type and size validation
- ✓ **Soft Delete**: 7-day retention for deleted blobs

## Cost Estimation

Approximate monthly costs (based on West Europe region):

| Resource         | SKU          | Estimated Cost           |
| ---------------- | ------------ | ------------------------ |
| App Service Plan | B1           | ~€10-15/month            |
| Storage Account  | Standard_LRS | ~€0.05/GB + transactions |
| **Total**        |              | **~€10-20/month**        |

*Note: Costs vary by region and usage. Use [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) for accurate estimates.*

## Cleanup

To delete all resources and avoid ongoing charges:

```powershell
.\cleanup.ps1 -ResourceGroupName "rg-fileupload-dev"
```

You will be prompted to confirm by typing `DELETE`.

To skip confirmation:

```powershell
.\cleanup.ps1 -ResourceGroupName "rg-fileupload-dev" -Force
```

## Project Structure

```
.
├── app/                          # Web application
│   ├── public/                   # Static files
│   │   └── index.html           # Frontend UI
│   ├── server.js                # Express server
│   ├── package.json             # Node.js dependencies
│   ├── web.config               # IIS configuration for Azure
│   ├── .env.example             # Environment variables template
│   └── .gitignore               # Git ignore rules
│
├── infra/                        # Infrastructure as Code
│   ├── main.bicep               # Main Bicep template
│   └── main.bicepparam          # Default parameters
│
├── deploy.ps1                    # Deployment script
├── cleanup.ps1                   # Resource cleanup script
├── .deployment-config            # Deployment configuration
└── README.md                     # This file
```

## Technology Stack

- **Infrastructure**: Azure Bicep
- **Runtime**: Node.js 20 LTS
- **Web Framework**: Express.js 4.21.2
- **Storage SDK**: @azure/storage-blob 12.24.0
- **File Upload**: Multer 1.4.5
- **Authentication**: Azure Managed Identity with RBAC

## Best Practices Implemented

1. **Infrastructure as Code**: Repeatable, version-controlled deployments
2. **Managed Identity**: Secure authentication without credentials
3. **Resource Tagging**: Proper resource organization and cost tracking
4. **Environment Separation**: Dev, test, and prod configurations
5. **HTTPS Enforcement**: Secure communication
6. **Soft Delete**: Blob recovery capability
7. **Health Checks**: Application monitoring endpoints
8. **Error Handling**: Comprehensive error handling and logging

## Next Steps

- [ ] Configure custom domain and SSL certificate
- [ ] Add Application Insights for monitoring
- [ ] Implement authentication (Azure AD, etc.)
- [ ] Add file size quotas per user
- [ ] Implement file virus scanning
- [ ] Add CDN for static content delivery
- [ ] Configure backup and disaster recovery

## Support

For issues or questions:

1. Check the [Troubleshooting](#monitoring-and-troubleshooting) section
2. Review Azure logs: `az webapp log tail`
3. Check Azure documentation: [Azure App Service](https://docs.microsoft.com/azure/app-service/)

## License

This project is provided as-is for demonstration purposes.

---

**Created with Azure Best Practices** | **Deployed with Bicep** | **Secured with Managed Identity**
