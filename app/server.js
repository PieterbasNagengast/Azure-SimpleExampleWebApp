const express = require('express');
const multer = require('multer');
const { BlobServiceClient } = require('@azure/storage-blob');
const { DefaultAzureCredential } = require('@azure/identity');
const path = require('path');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// Configure multer for memory storage
const upload = multer({
    storage: multer.memoryStorage(),
    limits: {
        fileSize: 10 * 1024 * 1024 // 10MB limit
    },
    fileFilter: (req, file, cb) => {
        // Allow common file types
        const allowedTypes = /jpeg|jpg|png|gif|pdf|doc|docx|txt|zip/;
        const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
        const mimetype = allowedTypes.test(file.mimetype);

        if (mimetype && extname) {
            return cb(null, true);
        } else {
            cb(new Error('Invalid file type. Allowed types: JPEG, PNG, GIF, PDF, DOC, DOCX, TXT, ZIP'));
        }
    }
});

// Azure Storage configuration
const STORAGE_ACCOUNT_NAME = process.env.AZURE_STORAGE_ACCOUNT_NAME;
const CONTAINER_NAME = process.env.AZURE_STORAGE_CONTAINER_NAME || 'uploads';

// Initialize Blob Service Client with Managed Identity
let blobServiceClient;
try {
    if (!STORAGE_ACCOUNT_NAME) {
        throw new Error('AZURE_STORAGE_ACCOUNT_NAME is not defined');
    }

    // Use DefaultAzureCredential for Managed Identity authentication
    const credential = new DefaultAzureCredential();
    const accountUrl = `https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net`;
    blobServiceClient = new BlobServiceClient(accountUrl, credential);

    console.log(`Initialized Azure Storage client for account: ${STORAGE_ACCOUNT_NAME}`);
} catch (error) {
    console.error('Error initializing Azure Storage:', error.message);
}

// Middleware
app.use(express.static('public'));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Routes
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Upload file endpoint
app.post('/upload', upload.single('file'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ error: 'No file uploaded' });
        }

        if (!blobServiceClient) {
            return res.status(500).json({ error: 'Azure Storage is not configured' });
        }

        // Get container client
        const containerClient = blobServiceClient.getContainerClient(CONTAINER_NAME);

        // Create container if it doesn't exist (private by default)
        await containerClient.createIfNotExists();

        // Generate unique blob name with timestamp
        const timestamp = Date.now();
        const blobName = `${timestamp}-${req.file.originalname}`;

        // Get block blob client
        const blockBlobClient = containerClient.getBlockBlobClient(blobName);

        // Upload file
        await blockBlobClient.uploadData(req.file.buffer, {
            blobHTTPHeaders: {
                blobContentType: req.file.mimetype
            }
        });

        console.log(`File uploaded successfully: ${blobName}`);

        res.json({
            success: true,
            message: 'File uploaded successfully',
            fileName: req.file.originalname,
            blobName: blobName,
            size: req.file.size,
            uploadDate: new Date().toISOString()
        });
    } catch (error) {
        console.error('Error uploading file:', error);
        res.status(500).json({
            error: 'Failed to upload file',
            details: error.message
        });
    }
});

// List uploaded files endpoint
app.get('/files', async (req, res) => {
    try {
        if (!blobServiceClient) {
            return res.status(500).json({ error: 'Azure Storage is not configured' });
        }

        const containerClient = blobServiceClient.getContainerClient(CONTAINER_NAME);

        // Check if container exists
        const exists = await containerClient.exists();
        if (!exists) {
            return res.json({ files: [] });
        }

        const files = [];

        // List all blobs in the container
        for await (const blob of containerClient.listBlobsFlat()) {
            files.push({
                name: blob.name,
                size: blob.properties.contentLength,
                lastModified: blob.properties.lastModified,
                contentType: blob.properties.contentType
            });
        }

        res.json({ files });
    } catch (error) {
        console.error('Error listing files:', error);
        res.status(500).json({
            error: 'Failed to list files',
            details: error.message
        });
    }
});

// Download file endpoint
app.get('/files/:name/download', async (req, res) => {
    try {
        if (!blobServiceClient) {
            return res.status(500).json({ error: 'Azure Storage is not configured' });
        }
        const blobName = decodeURIComponent(req.params.name);
        const containerClient = blobServiceClient.getContainerClient(CONTAINER_NAME);
        const blobClient = containerClient.getBlobClient(blobName);
        const exists = await blobClient.exists();
        if (!exists) {
            return res.status(404).json({ error: 'File not found' });
        }
        const downloadResponse = await blobClient.download();
        const originalName = blobName.replace(/^\d+-/, '');
        res.setHeader('Content-Type', downloadResponse.contentType || 'application/octet-stream');
        res.setHeader('Content-Disposition', `attachment; filename="${originalName}"`);
        downloadResponse.readableStreamBody.pipe(res);
    } catch (error) {
        console.error('Error downloading file:', error);
        res.status(500).json({ error: 'Failed to download file', details: error.message });
    }
});

// Delete file endpoint
app.delete('/files/:name', async (req, res) => {
    try {
        if (!blobServiceClient) {
            return res.status(500).json({ error: 'Azure Storage is not configured' });
        }
        const blobName = decodeURIComponent(req.params.name);
        const containerClient = blobServiceClient.getContainerClient(CONTAINER_NAME);
        const blobClient = containerClient.getBlobClient(blobName);
        const exists = await blobClient.exists();
        if (!exists) {
            return res.status(404).json({ error: 'File not found' });
        }
        await blobClient.delete();
        res.json({ success: true, message: 'File deleted', name: blobName });
    } catch (error) {
        console.error('Error deleting file:', error);
        res.status(500).json({ error: 'Failed to delete file', details: error.message });
    }
});

// Error handling middleware
app.use((error, req, res, next) => {
    if (error instanceof multer.MulterError) {
        if (error.code === 'LIMIT_FILE_SIZE') {
            return res.status(400).json({ error: 'File size exceeds 10MB limit' });
        }
        return res.status(400).json({ error: error.message });
    }

    res.status(500).json({ error: error.message });
});

// 404 handler
app.use((req, res) => {
    res.status(404).json({ error: 'Not found' });
});

// Start server
app.listen(PORT, () => {
    console.log(`Server is running on port ${PORT}`);
    console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
    console.log(`Storage configured: ${!!blobServiceClient}`);
});

module.exports = app;
