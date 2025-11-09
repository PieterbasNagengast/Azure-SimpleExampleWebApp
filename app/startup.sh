#!/bin/sh
set -e

echo "=== Startup Script ==="
echo "Node version: $(node --version)"
echo "NPM version: $(npm --version)"
echo "Current directory: $(pwd)"
echo "Files in current directory:"
ls -la

echo ""
echo "=== Installing dependencies ==="
npm install --production

echo ""
echo "=== Environment variables ==="
echo "AZURE_STORAGE_ACCOUNT_NAME: ${AZURE_STORAGE_ACCOUNT_NAME:-not set}"
echo "AZURE_STORAGE_CONTAINER_NAME: ${AZURE_STORAGE_CONTAINER_NAME:-not set}"
echo "NODE_ENV: ${NODE_ENV:-not set}"
echo "PORT: ${PORT:-not set}"

echo ""
echo "=== Starting application ==="
node server.js
