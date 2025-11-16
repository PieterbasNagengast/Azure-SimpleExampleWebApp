const express = require('express');
const helmet = require('helmet');
const compression = require('compression');
const multer = require('multer');
const { BlobServiceClient } = require('@azure/storage-blob');
const { DefaultAzureCredential } = require('@azure/identity');
const pino = require('pino');
const pinoHttp = require('pino-http');
const path = require('path');
const crypto = require('crypto');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;
const NODE_ENV = process.env.NODE_ENV || 'development';

const logger = pino({
    level: process.env.LOG_LEVEL || (NODE_ENV === 'production' ? 'info' : 'debug'),
    redact: ['req.headers.authorization']
});

app.use(pinoHttp({
    logger,
    genReqId: () => crypto.randomUUID(),
    customLogLevel: (res, err) => {
        if (err || res.statusCode >= 500) return 'error';
        if (res.statusCode >= 400) return 'warn';
        return 'info';
    }
}));

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
const STORAGE_CONNECTION_STRING = process.env.AZURE_STORAGE_CONNECTION_STRING;
const CONTAINER_NAME = process.env.AZURE_STORAGE_CONTAINER_NAME || 'uploads';

if (!STORAGE_ACCOUNT_NAME && !STORAGE_CONNECTION_STRING) {
    logger.warn('Neither AZURE_STORAGE_ACCOUNT_NAME nor AZURE_STORAGE_CONNECTION_STRING is defined; blob operations will fail until configured.');
}

// Initialize Blob Service Client with Managed Identity
let blobServiceClient;
try {
    if (STORAGE_CONNECTION_STRING) {
        blobServiceClient = BlobServiceClient.fromConnectionString(STORAGE_CONNECTION_STRING);
        logger.info('Initialized Azure Storage client using connection string');
    } else if (STORAGE_ACCOUNT_NAME) {
        const credential = new DefaultAzureCredential();
        const accountUrl = `https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net`;
        blobServiceClient = new BlobServiceClient(accountUrl, credential);
        logger.info({ account: STORAGE_ACCOUNT_NAME }, 'Initialized Azure Storage client using managed identity');
    } else {
        throw new Error('Storage configuration missing. Provide AZURE_STORAGE_CONNECTION_STRING or AZURE_STORAGE_ACCOUNT_NAME.');
    }
} catch (error) {
    logger.error({ err: error }, 'Error initializing Azure Storage');
}

let containerClientPromise;

async function getContainerClient() {
    if (!blobServiceClient) {
        throw new Error('Azure Storage is not configured. Provide AZURE_STORAGE_CONNECTION_STRING or configure managed identity with AZURE_STORAGE_ACCOUNT_NAME.');
    }

    if (!containerClientPromise) {
        const containerClient = blobServiceClient.getContainerClient(CONTAINER_NAME);
        containerClientPromise = ensureContainer(containerClient)
            .then(() => containerClient)
            .catch((error) => {
                containerClientPromise = undefined;
                throw error;
            });
    }

    return containerClientPromise;
}

async function ensureContainer(containerClient) {
    // Skip container existence check - assume container exists or will be created via infrastructure
    // The Storage Blob Data Contributor role doesn't include permissions for GetContainerProperties
    // which is required by containerClient.exists()
    return;
}

function translateStorageError(error, defaultMessage) {
    const message = error?.message || defaultMessage;
    const errorCode = error?.details?.errorCode || error?.code;
    const requestId = error?.details?.requestId || error?.response?.headers?.get?.('x-ms-request-id');
    const statusCode = typeof error?.statusCode === 'number' ? error.statusCode : undefined;

    if (message.includes('not configured')) {
        return {
            status: 503,
            body: {
                error: 'Storage service unavailable',
                details: message,
                guidance: 'Set AZURE_STORAGE_CONNECTION_STRING or configure AZURE_STORAGE_ACCOUNT_NAME with a managed identity.'
            }
        };
    }

    if (statusCode === 403) {
        return {
            status: 403,
            body: {
                error: 'Storage access denied',
                details: message,
                guidance: 'Confirm the identity used by the app has Storage Blob Data Contributor (or equivalent) permissions, or that the SAS token/connection string is valid.',
                code: errorCode,
                requestId
            }
        };
    }

    if (error?.statusCode === 404) {
        return {
            status: 404,
            body: {
                error: 'Storage resource not found',
                details: 'The requested blob or container could not be located.'
            }
        };
    }

    const responseBody = {
        status: statusCode || 500,
        body: {
            error: defaultMessage,
            details: message,
            code: errorCode,
            requestId,
            statusCode
        }
    };

    return responseBody;
}

// Middleware
app.use(helmet({
    contentSecurityPolicy: {
        useDefaults: true,
        directives: {
            "script-src": ["'self'", "'unsafe-inline'"],
            "style-src": ["'self'", "'unsafe-inline'"],
            "img-src": ["'self'", 'data:']
        }
    },
    crossOriginEmbedderPolicy: false
}));
app.use(compression());
app.use(express.static('public'));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Routes
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        storageConfigured: Boolean(blobServiceClient)
    });
});

app.get('/ready', async (req, res) => {
    try {
        await getContainerClient();
        res.json({ status: 'ready' });
    } catch (error) {
        req.log.error({ err: error }, 'Readiness check failed');
        res.status(503).json({ status: 'unavailable', reason: error.message });
    }
});

// Upload file endpoint
app.post('/upload', upload.single('file'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ error: 'No file uploaded' });
        }

        const containerClient = await getContainerClient();

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

        req.log.info({ blob: blobName, size: req.file.size }, 'File uploaded');

        res.json({
            success: true,
            message: 'File uploaded successfully',
            fileName: req.file.originalname,
            blobName: blobName,
            size: req.file.size,
            uploadDate: new Date().toISOString()
        });
    } catch (error) {
        req.log.error({ err: error }, 'Error uploading file');
        const translated = translateStorageError(error, 'Failed to upload file');
        res.status(translated.status).json(translated.body);
    }
});

// List uploaded files endpoint
app.get('/files', async (req, res) => {
    try {
        const containerClient = await getContainerClient();

        // Check if container exists (createIfNotExists resolves even when existing)
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
        req.log.error({ err: error }, 'Error listing files');
        const translated = translateStorageError(error, 'Failed to list files');
        res.status(translated.status).json(translated.body);
    }
});

// Download file endpoint
app.get('/files/:name/download', async (req, res) => {
    try {
        const blobName = decodeURIComponent(req.params.name);
        const containerClient = await getContainerClient();
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
        req.log.error({ err: error }, 'Error downloading file');
        const translated = translateStorageError(error, 'Failed to download file');
        res.status(translated.status).json(translated.body);
    }
});

// Delete file endpoint
app.delete('/files/:name', async (req, res) => {
    try {
        const blobName = decodeURIComponent(req.params.name);
        const containerClient = await getContainerClient();
        const blobClient = containerClient.getBlobClient(blobName);
        const exists = await blobClient.exists();
        if (!exists) {
            return res.status(404).json({ error: 'File not found' });
        }
        await blobClient.delete();
        res.json({ success: true, message: 'File deleted', name: blobName });
    } catch (error) {
        req.log.error({ err: error }, 'Error deleting file');
        const translated = translateStorageError(error, 'Failed to delete file');
        res.status(translated.status).json(translated.body);
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
    logger.info({ port: PORT, env: NODE_ENV, storageConfigured: !!blobServiceClient }, 'Server started');
});

module.exports = app;
