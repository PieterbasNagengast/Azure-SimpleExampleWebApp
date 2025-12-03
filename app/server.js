const express = require('express');
const multer = require('multer');
const { BlobServiceClient } = require('@azure/storage-blob');
const { DefaultAzureCredential } = require('@azure/identity');
const createClient = require('@azure-rest/ai-vision-image-analysis').default;
const path = require('path');

const app = express();
const port = process.env.PORT || 8080;

// Max file size configuration (in MB, default 100MB)
const MAX_FILE_SIZE_MB = parseInt(process.env.MAX_FILE_SIZE_MB) || 100;
const MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024;

// Allowed file types configuration (comma-separated extensions or * for all)
const ALLOWED_FILE_TYPES = process.env.ALLOWED_FILE_TYPES || '*';
const allowedExtensions = ALLOWED_FILE_TYPES === '*' ? null :
    ALLOWED_FILE_TYPES.split(',').map(ext => ext.trim().toLowerCase());

// Default theme mode configuration
const DEFAULT_THEME_MODE = process.env.DEFAULT_THEME_MODE || 'auto';

// Application title and subtitle configuration
const APP_TITLE = process.env.APP_TITLE || 'MagicFiles';
const APP_SUBTITLE = process.env.APP_SUBTITLE || 'Your secure cloud file manager';

// Configure multer for memory storage
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: MAX_FILE_SIZE_BYTES }
});

// Azure Storage configuration
const storageAccountName = process.env.AZURE_STORAGE_ACCOUNT_NAME;
const containerName = process.env.AZURE_STORAGE_CONTAINER_NAME || 'uploads';
const visionEndpoint = process.env.VISION_ENDPOINT;

if (!storageAccountName) {
    console.error('AZURE_STORAGE_ACCOUNT_NAME environment variable is required');
    process.exit(1);
}

if (!visionEndpoint) {
    console.error('VISION_ENDPOINT environment variable is required');
    process.exit(1);
}

// Initialize Azure Blob Storage client with managed identity
const credential = new DefaultAzureCredential();
const blobServiceClient = new BlobServiceClient(
    `https://${storageAccountName}.blob.core.windows.net`,
    credential
);
const containerClient = blobServiceClient.getContainerClient(containerName);

// Initialize Azure AI Vision client with managed identity
const visionClient = createClient(visionEndpoint, credential);

// Middleware
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Health check endpoint (standard path for load balancers/gateways)
app.get('/health', async (req, res) => {
    try {
        // Check storage connectivity
        await containerClient.exists();

        res.status(200).json({
            status: 'healthy',
            timestamp: new Date().toISOString(),
            service: 'MagicFiles',
            checks: {
                storage: 'healthy'
            }
        });
    } catch (error) {
        console.error('Health check failed:', error);
        res.status(503).json({
            status: 'unhealthy',
            timestamp: new Date().toISOString(),
            service: 'MagicFiles',
            checks: {
                storage: 'unhealthy'
            },
            error: error.message
        });
    }
});

// Legacy health check endpoint (kept for backwards compatibility)
app.get('/api/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Get configuration endpoint
app.get('/api/config', (req, res) => {
    res.json({
        maxFileSizeMB: MAX_FILE_SIZE_MB,
        maxFileSizeBytes: MAX_FILE_SIZE_BYTES,
        allowedFileTypes: ALLOWED_FILE_TYPES,
        allowedExtensions: allowedExtensions,
        defaultThemeMode: DEFAULT_THEME_MODE,
        appTitle: APP_TITLE,
        appSubtitle: APP_SUBTITLE
    });
});

// Get user information from Easy Auth headers
app.get('/api/user', (req, res) => {
    try {
        // Azure App Service Easy Auth injects user information in headers
        const principalName = req.headers['x-ms-client-principal-name'];
        const principalId = req.headers['x-ms-client-principal-id'];

        // If Easy Auth headers are present
        if (principalName) {
            res.json({
                name: principalName,
                id: principalId || 'unknown'
            });
        } else {
            // Fallback for local development
            res.json({
                name: 'Local User',
                id: 'local-dev'
            });
        }
    } catch (error) {
        console.error('Error fetching user info:', error);
        res.status(500).json({
            error: 'Failed to fetch user information',
            message: error.message
        });
    }
});

// List all files in the container
app.get('/api/files', async (req, res) => {
    try {
        const files = [];

        for await (const blob of containerClient.listBlobsFlat({ includeMetadata: true })) {
            const blobClient = containerClient.getBlobClient(blob.name);
            const properties = await blobClient.getProperties();

            const fileInfo = {
                name: blob.name,
                size: properties.contentLength,
                contentType: properties.contentType,
                lastModified: properties.lastModified,
                uploadedBy: properties.metadata?.uploadedby || 'Unknown',
                url: blobClient.url
            };

            // Add AI Vision metadata if available
            if (properties.metadata?.imagewidth && properties.metadata?.imageheight) {
                fileInfo.imageWidth = parseInt(properties.metadata.imagewidth);
                fileInfo.imageHeight = parseInt(properties.metadata.imageheight);
            }

            if (properties.metadata?.detectedobjects) {
                fileInfo.detectedObjects = properties.metadata.detectedobjects.split('|').map(obj => {
                    const [name, confidence, bbox] = obj.split(':');
                    const [x, y, w, h] = bbox.split(',').map(Number);
                    return {
                        name,
                        confidence: parseFloat(confidence),
                        boundingBox: { x, y, w, h }
                    };
                });
            }

            if (properties.metadata?.imagetags) {
                fileInfo.imageTags = properties.metadata.imagetags.split(',').map(tag => {
                    const [name, confidence] = tag.split(':');
                    return { name, confidence: parseFloat(confidence) };
                });
            }

            files.push(fileInfo);
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

            // Validate file type if restrictions are set
            if (allowedExtensions) {
                const fileExt = path.extname(req.file.originalname).toLowerCase();
                if (!allowedExtensions.includes(fileExt)) {
                    return res.status(400).json({
                        error: 'File type not allowed',
                        message: `Only ${ALLOWED_FILE_TYPES} files are allowed`
                    });
                }
            }

            // Get user UPN from Easy Auth headers
            const userUpn = req.headers['x-ms-client-principal-name'] || 'Local User';

            const blobName = `${Date.now()}-${req.file.originalname}`;
            const blockBlobClient = containerClient.getBlockBlobClient(blobName);

            // Prepare metadata
            const metadata = {
                uploadedby: userUpn,
                uploaddate: new Date().toISOString()
            };

            // Detect objects if file is an image
            const isImage = req.file.mimetype.startsWith('image/');
            if (isImage) {
                try {
                    console.log('Analyzing image for object detection...');
                    const result = await visionClient.path('/imageanalysis:analyze').post({
                        body: req.file.buffer,
                        queryParameters: {
                            features: ['Objects', 'Tags']
                        },
                        contentType: 'application/octet-stream'
                    });

                    if (result.status === '200') {
                        const analysis = result.body;

                        // Save image metadata for dimensions
                        if (analysis.metadata) {
                            metadata.imagewidth = analysis.metadata.width.toString();
                            metadata.imageheight = analysis.metadata.height.toString();
                        }

                        // Extract detected objects with bounding boxes
                        if (analysis.objectsResult && analysis.objectsResult.values && analysis.objectsResult.values.length > 0) {
                            const detectedObjects = analysis.objectsResult.values.map(obj => {
                                const bbox = obj.boundingBox;
                                return `${obj.tags[0].name}:${obj.tags[0].confidence.toFixed(2)}:${bbox.x},${bbox.y},${bbox.w},${bbox.h}`;
                            });
                            metadata.detectedobjects = detectedObjects.join('|');
                        }

                        // Extract tags
                        if (analysis.tagsResult && analysis.tagsResult.values && analysis.tagsResult.values.length > 0) {
                            const tags = analysis.tagsResult.values
                                .filter(tag => tag.confidence > 0.7)
                                .map(tag => `${tag.name}:${tag.confidence.toFixed(2)}`);
                            metadata.imagetags = tags.join(',');
                        }
                    }
                } catch (visionError) {
                    console.error('AI Vision analysis failed:', visionError);
                    // Continue with upload even if vision analysis fails
                }
            }

            await blockBlobClient.uploadData(req.file.buffer, {
                blobHTTPHeaders: {
                    blobContentType: req.file.mimetype
                },
                metadata: metadata
            });

            res.json({
                message: 'File uploaded successfully',
                fileName: blobName,
                originalName: req.file.originalname,
                size: req.file.size,
                detectedObjects: metadata.detectedobjects || null,
                imageTags: metadata.imagetags || null
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
