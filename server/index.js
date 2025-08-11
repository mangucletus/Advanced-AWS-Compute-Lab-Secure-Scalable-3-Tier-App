// server/index.js
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { Pool } = require('pg');
const AWS = require('aws-sdk');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const nodemailer = require('nodemailer');
require('dotenv').config();

const app = express();
const PORT = process.env.SERVER_PORT || 8000;

// AWS S3 Configuration
const s3 = new AWS.S3({
    region: process.env.AWS_REGION || 'eu-central-1'
});

// Database Configuration
const pool = new Pool({
    host: process.env.DB_HOST,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    port: process.env.DB_PORT || 5432,
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Ensure uploads directory exists
const uploadsDir = process.env.UPLOAD_DIR || './uploads';
if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
}

// Multer configuration for file uploads
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, uploadsDir);
    },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        cb(null, file.fieldname + '-' + uniqueSuffix + path.extname(file.originalname));
    }
});

const upload = multer({
    storage: storage,
    limits: {
        fileSize: 10 * 1024 * 1024, // 10MB limit
    },
    fileFilter: (req, file, cb) => {
        // Allow all file types for this lab
        cb(null, true);
    }
});

// Authentication middleware
const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        return res.status(401).json({ message: 'Access token required' });
    }

    jwt.verify(token, process.env.SECRET, (err, user) => {
        if (err) {
            return res.status(403).json({ message: 'Invalid or expired token' });
        }
        req.user = user;
        next();
    });
};

// Admin middleware
const requireAdmin = (req, res, next) => {
    if (req.user.role !== 'admin') {
        return res.status(403).json({ message: 'Admin access required' });
    }
    next();
};

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

// User registration
app.post('/api/register', async (req, res) => {
    try {
        const { username, email, password } = req.body;

        // Check if user exists
        const userExists = await pool.query(
            'SELECT id FROM users WHERE username = $1 OR email = $2',
            [username, email]
        );

        if (userExists.rows.length > 0) {
            return res.status(400).json({ message: 'User already exists' });
        }

        // Hash password
        const saltRounds = 10;
        const hashedPassword = await bcrypt.hash(password, saltRounds);

        // Create user (first user is admin)
        const userCount = await pool.query('SELECT COUNT(*) FROM users');
        const role = userCount.rows[0].count === '0' ? 'admin' : 'user';

        const result = await pool.query(
            'INSERT INTO users (username, email, password, role) VALUES ($1, $2, $3, $4) RETURNING id, username, email, role',
            [username, email, hashedPassword, role]
        );

        res.status(201).json({
            message: 'User created successfully',
            user: result.rows[0]
        });
    } catch (error) {
        console.error('Registration error:', error);
        res.status(500).json({ message: 'Internal server error' });
    }
});

// User login
app.post('/api/login', async (req, res) => {
    try {
        const { username, password } = req.body;

        // Find user
        const result = await pool.query(
            'SELECT * FROM users WHERE username = $1',
            [username]
        );

        if (result.rows.length === 0) {
            return res.status(401).json({ message: 'Invalid credentials' });
        }

        const user = result.rows[0];

        // Check password
        const validPassword = await bcrypt.compare(password, user.password);
        if (!validPassword) {
            return res.status(401).json({ message: 'Invalid credentials' });
        }

        // Generate JWT
        const token = jwt.sign(
            { id: user.id, username: user.username, role: user.role },
            process.env.SECRET,
            { expiresIn: '24h' }
        );

        res.json({
            token,
            user: {
                id: user.id,
                username: user.username,
                email: user.email,
                role: user.role
            }
        });
    } catch (error) {
        console.error('Login error:', error);
        res.status(500).json({ message: 'Internal server error' });
    }
});

// Upload file
app.post('/api/upload', authenticateToken, requireAdmin, upload.single('file'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ message: 'No file uploaded' });
        }

        const { originalname, filename, mimetype, size, path: filepath } = req.file;

        // Save file info to database
        const result = await pool.query(
            'INSERT INTO files (original_name, filename, file_path, mimetype, size, uploaded_by) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *',
            [originalname, filename, filepath, mimetype, size, req.user.id]
        );

        // Optionally upload to S3
        if (process.env.S3_BUCKET_NAME) {
            try {
                const fileContent = fs.readFileSync(filepath);
                const uploadParams = {
                    Bucket: process.env.S3_BUCKET_NAME,
                    Key: `files/${filename}`,
                    Body: fileContent,
                    ContentType: mimetype
                };

                await s3.upload(uploadParams).promise();

                // Update database with S3 info
                await pool.query(
                    'UPDATE files SET s3_key = $1, s3_bucket = $2 WHERE id = $3',
                    [`files/${filename}`, process.env.S3_BUCKET_NAME, result.rows[0].id]
                );
            } catch (s3Error) {
                console.error('S3 upload error:', s3Error);
                // Continue without S3 upload
            }
        }

        res.status(201).json({
            message: 'File uploaded successfully',
            file: result.rows[0]
        });
    } catch (error) {
        console.error('Upload error:', error);
        res.status(500).json({ message: 'Internal server error' });
    }
});

// Get all files
app.get('/api/files', authenticateToken, async (req, res) => {
    try {
        const result = await pool.query(`
      SELECT f.*, u.username as uploaded_by_username 
      FROM files f 
      LEFT JOIN users u ON f.uploaded_by = u.id 
      ORDER BY f.uploaded_at DESC
    `);

        res.json(result.rows);
    } catch (error) {
        console.error('Get files error:', error);
        res.status(500).json({ message: 'Internal server error' });
    }
});

// Download file
app.get('/api/download/:id', authenticateToken, async (req, res) => {
    try {
        const { id } = req.params;

        const result = await pool.query('SELECT * FROM files WHERE id = $1', [id]);

        if (result.rows.length === 0) {
            return res.status(404).json({ message: 'File not found' });
        }

        const file = result.rows[0];

        // Try S3 first, then local file
        if (file.s3_key && file.s3_bucket) {
            try {
                const params = {
                    Bucket: file.s3_bucket,
                    Key: file.s3_key
                };

                const s3Object = await s3.getObject(params).promise();

                res.setHeader('Content-Disposition', `attachment; filename="${file.original_name}"`);
                res.setHeader('Content-Type', file.mimetype);
                res.send(s3Object.Body);
                return;
            } catch (s3Error) {
                console.error('S3 download error:', s3Error);
            }
        }

        // Fallback to local file
        if (fs.existsSync(file.file_path)) {
            res.setHeader('Content-Disposition', `attachment; filename="${file.original_name}"`);
            res.setHeader('Content-Type', file.mimetype);
            res.sendFile(path.resolve(file.file_path));
        } else {
            res.status(404).json({ message: 'File not found on server' });
        }
    } catch (error) {
        console.error('Download error:', error);
        res.status(500).json({ message: 'Internal server error' });
    }
});

// Delete file
app.delete('/api/files/:id', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const { id } = req.params;

        const result = await pool.query('SELECT * FROM files WHERE id = $1', [id]);

        if (result.rows.length === 0) {
            return res.status(404).json({ message: 'File not found' });
        }

        const file = result.rows[0];

        // Delete from S3 if exists
        if (file.s3_key && file.s3_bucket) {
            try {
                await s3.deleteObject({
                    Bucket: file.s3_bucket,
                    Key: file.s3_key
                }).promise();
            } catch (s3Error) {
                console.error('S3 delete error:', s3Error);
            }
        }

        // Delete local file
        if (fs.existsSync(file.file_path)) {
            fs.unlinkSync(file.file_path);
        }

        // Delete from database
        await pool.query('DELETE FROM files WHERE id = $1', [id]);

        res.json({ message: 'File deleted successfully' });
    } catch (error) {
        console.error('Delete error:', error);
        res.status(500).json({ message: 'Internal server error' });
    }
});

// Send file via email
app.post('/api/send-file/:id', authenticateToken, async (req, res) => {
    try {
        const { id } = req.params;
        const { email, message } = req.body;

        const result = await pool.query('SELECT * FROM files WHERE id = $1', [id]);

        if (result.rows.length === 0) {
            return res.status(404).json({ message: 'File not found' });
        }

        const file = result.rows[0];

        // Configure email transporter (using Gmail as example)
        const transporter = nodemailer.createTransporter({
            service: 'gmail',
            auth: {
                user: process.env.EMAIL_USER,
                pass: process.env.EMAIL_PASS
            }
        });

        // Create download link (temporary solution)
        const downloadLink = `${req.protocol}://${req.get('host')}/api/download/${file.id}`;

        const mailOptions = {
            from: process.env.EMAIL_USER,
            to: email,
            subject: `File shared: ${file.original_name}`,
            html: `
        <h3>File Shared with You</h3>
        <p>User ${req.user.username} has shared a file with you.</p>
        <p><strong>File:</strong> ${file.original_name}</p>
        <p><strong>Size:</strong> ${(file.size / 1024).toFixed(2)} KB</p>
        ${message ? `<p><strong>Message:</strong> ${message}</p>` : ''}
        <p><a href="${downloadLink}">Click here to download</a></p>
        <p><small>This link requires authentication to access.</small></p>
      `
        };

        // Only send email if email configuration is available
        if (process.env.EMAIL_USER && process.env.EMAIL_PASS) {
            await transporter.sendMail(mailOptions);
            res.json({ message: 'File link sent successfully' });
        } else {
            // Return download link if email is not configured
            res.json({
                message: 'Email not configured. Here is the download link:',
                downloadLink: downloadLink
            });
        }
    } catch (error) {
        console.error('Send file error:', error);
        res.status(500).json({ message: 'Internal server error' });
    }
});

// Get user info
app.get('/api/user', authenticateToken, (req, res) => {
    res.json({
        id: req.user.id,
        username: req.user.username,
        role: req.user.role
    });
});

// Error handling middleware
app.use((error, req, res, next) => {
    if (error instanceof multer.MulterError) {
        if (error.code === 'LIMIT_FILE_SIZE') {
            return res.status(400).json({ message: 'File too large' });
        }
    }

    console.error(error);
    res.status(500).json({ message: 'Internal server error' });
});

// Serve static files in production
if (process.env.NODE_ENV === 'production') {
    app.use(express.static(path.join(__dirname, '../client/dist')));

    app.get('*', (req, res) => {
        res.sendFile(path.join(__dirname, '../client/dist/index.html'));
    });
}

app.listen(PORT, '0.0.0.0', () => {
    console.log(`File Server running on port ${PORT}`);
    console.log(`Environment: ${process.env.NODE_ENV}`);
    console.log(`Database: ${process.env.DB_HOST}:${process.env.DB_PORT}/${process.env.DB_NAME}`);
});