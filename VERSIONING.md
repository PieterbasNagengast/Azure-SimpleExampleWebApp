# Version Management Guide

## Overview
This application uses semantic versioning (MAJOR.MINOR.PATCH) displayed in the UI header.

## Version Display
- **Location**: Bottom right of the header (e.g., "v1.0.0")
- **Hover**: Shows full details (version, build date, commit SHA)
- **Click**: Displays version info in status message

## How Versioning Works

### 1. Manual Version Updates
Update the version in `app/package.json`:
```json
{
  "version": "1.2.3"
}
```

### 2. Automatic Version Injection (GitHub Actions)
The CI/CD pipeline automatically updates `app/public/version.json` during deployment:
- **Version**: From `package.json`
- **Build Date**: Current UTC timestamp
- **Commit**: Git commit SHA (short)

### 3. Version File Structure
`app/public/version.json`:
```json
{
  "version": "1.0.0",
  "buildDate": "2025-11-18T10:30:00Z",
  "commit": "abc1234"
}
```

## Semantic Versioning Guidelines

### MAJOR version (X.0.0)
Increment when making incompatible changes:
- Breaking API changes
- Major infrastructure changes
- Complete UI redesign

### MINOR version (1.X.0)
Increment when adding functionality:
- New features
- New configuration options
- Non-breaking enhancements

### PATCH version (1.0.X)
Increment for bug fixes:
- Bug fixes
- Security patches
- Performance improvements

## GitHub Actions Workflow

### Setup Required Secrets
In your GitHub repository, add these secrets:
1. `AZURE_WEBAPP_NAME` - Your Azure Web App name
2. `AZURE_WEBAPP_PUBLISH_PROFILE` - Download from Azure Portal

### Automatic Deployment
The workflow (`.github/workflows/deploy.yml`) triggers on:
- Push to `main` branch
- Manual workflow dispatch

### What the Workflow Does
1. Reads version from `package.json`
2. Generates `version.json` with:
   - Version number
   - Build timestamp
   - Git commit SHA
3. Installs dependencies
4. Deploys to Azure Web App

## Local Development
For local development, `version.json` shows:
```json
{
  "version": "1.0.0",
  "buildDate": "2025-11-18T00:00:00Z",
  "commit": "local-dev"
}
```

## Release Process

### Step 1: Update Version
```bash
# Update package.json version
npm version patch  # 1.0.0 -> 1.0.1
npm version minor  # 1.0.1 -> 1.1.0
npm version major  # 1.1.0 -> 2.0.0
```

### Step 2: Commit and Push
```bash
git add app/package.json
git commit -m "chore: bump version to 1.1.0"
git push origin main
```

### Step 3: Automatic Deployment
GitHub Actions automatically:
- Builds the application
- Updates version.json
- Deploys to Azure

### Step 4: Verify
Check the version badge in the deployed app!

## Alternative: Environment Variable Approach
You can also set version via Azure App Settings:
```bash
az webapp config appsettings set \
  --settings APP_VERSION="1.0.0"
```

Then update server.js to serve it via `/api/config`.

## Tips
- Always update version before merging to `main`
- Use git tags to match releases: `git tag v1.0.0`
- Document changes in CHANGELOG.md
- Version badge is visible in both light/dark modes
