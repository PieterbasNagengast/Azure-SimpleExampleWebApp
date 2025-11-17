const express = require('express');
const multer = require('multer');
const { BlobServiceClient } = require('@azure/storage-blob');
const { DefaultAzureCredential } = require('@azure/identity');
const path = require('path');

const app = express();
const port = process.env.PORT || 8080;

// Max file size configuration (in MB, default 100MB)
const MAX_FILE_SIZE_MB = parseInt(process.env.MAX_FILE_SIZE_MB) || 100;
const MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024;

// Configure multer for memory storage
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: MAX_FILE_SIZE_BYTES }
});

// Azure Storage configuration
const storageAccountName = process.env.AZURE_STORAGE_ACCOUNT_NAME;
const containerName = process.env.AZURE_STORAGE_CONTAINER_NAME || 'uploads';

if (!storageAccountName) {
    console.error('AZURE_STORAGE_ACCOUNT_NAME environment variable is required');
    process.exit(1);
}

// Initialize Azure Blob Storage client with managed identity
const credential = new DefaultAzureCredential();
const blobServiceClient = new BlobServiceClient(
    `https://${storageAccountName}.blob.core.windows.net`,
    credential
);
const containerClient = blobServiceClient.getContainerClient(containerName);

// Middleware
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Health check endpoint
app.get('/api/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Get configuration endpoint
app.get('/api/config', (req, res) => {
    res.json({
        maxFileSizeMB: MAX_FILE_SIZE_MB,
        maxFileSizeBytes: MAX_FILE_SIZE_BYTES
    });
});

// List all files in the container
app.get('/api/files', async (req, res) => {
    try {
        const files = [];

        for await (const blob of containerClient.listBlobsFlat()) {
            const blobClient = containerClient.getBlobClient(blob.name);
            const properties = await blobClient.getProperties();

            files.push({
                name: blob.name,
                size: properties.contentLength,
                contentType: properties.contentType,
                lastModified: properties.lastModified,
                url: blobClient.url
            });
        }

        res.json({ files });
    } catch (error) {
        console.error('Error listing files:', error);
        res.status(500).json({
            error: 'Failed to list files',
            message: error.message
        });
    }
});

// Upload a file
app.post('/api/upload', (req, res) => {
    upload.single('file')(req, res, async (err) => {
        // Handle multer errors (including file size limit)
        if (err instanceof multer.MulterError) {
            if (err.code === 'LIMIT_FILE_SIZE') {
                return res.status(400).json({
                    error: 'File too large',
                    message: `File size exceeds ${MAX_FILE_SIZE_MB}MB limit`
                });
            }
            return res.status(400).json({
                error: 'Upload error',
                message: err.message
            });
        } else if (err) {
            return res.status(500).json({
                error: 'Upload failed',
                message: err.message
            });
        }

        try {
            if (!req.file) {
                return res.status(400).json({ error: 'No file provided' });
            }

            const blobName = `${Date.now()}-${req.file.originalname}`;
            const blockBlobClient = containerClient.getBlockBlobClient(blobName);

            await blockBlobClient.uploadData(req.file.buffer, {
                blobHTTPHeaders: {
                    blobContentType: req.file.mimetype
                }
            });

            res.json({
                message: 'File uploaded successfully',
                fileName: blobName,
                originalName: req.file.originalname,
                size: req.file.size
            });
        } catch (error) {
            console.error('Error uploading file:', error);
            res.status(500).json({
                error: 'Failed to upload file',
                message: error.message
            });
        }
    });
});

// Download a file
app.get('/api/download/:filename', async (req, res) => {
    try {
        const { filename } = req.params;
        const blobClient = containerClient.getBlobClient(filename);

        // Check if blob exists
        const exists = await blobClient.exists();
        if (!exists) {
            return res.status(404).json({ error: 'File not found' });
        }

        // Get blob properties for content type
        const properties = await blobClient.getProperties();

        // Download blob
        const downloadResponse = await blobClient.download();

        // Set headers
        res.setHeader('Content-Type', properties.contentType || 'application/octet-stream');
        res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
        res.setHeader('Content-Length', properties.contentLength);

        // Stream the blob to response
        downloadResponse.readableStreamBody.pipe(res);
    } catch (error) {
        console.error('Error downloading file:', error);
        res.status(500).json({
            error: 'Failed to download file',
            message: error.message
        });
    }
});

// Delete a file
app.delete('/api/files/:filename', async (req, res) => {
    try {
        const { filename } = req.params;
        const blobClient = containerClient.getBlobClient(filename);

        // Check if blob exists
        const exists = await blobClient.exists();
        if (!exists) {
            return res.status(404).json({ error: 'File not found' });
        }

        await blobClient.delete();

        res.json({
            message: 'File deleted successfully',
            fileName: filename
        });
    } catch (error) {
        console.error('Error deleting file:', error);
        res.status(500).json({
            error: 'Failed to delete file',
            message: error.message
        });
    }
});

// Serve the main HTML page
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(port, () => {
    console.log(`Server is running on port ${port}`);
    console.log(`Storage Account: ${storageAccountName}`);
    console.log(`Container: ${containerName}`);
});
