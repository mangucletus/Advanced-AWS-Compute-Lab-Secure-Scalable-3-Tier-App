#!/bin/bash
yum update -y

# Install necessary packages
yum install -y docker git postgresql15

# Start and enable Docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install Node.js 18
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# Create application directory structure
mkdir -p /home/ec2-user/fileserver-app/server
cd /home/ec2-user/fileserver-app/server

# Create package.json for server
cat > package.json << "EOF"
{
  "name": "fileserver-backend",
  "version": "1.0.0",
  "description": "File Server Backend - Express.js API for file upload, download, and management",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "dev": "nodemon index.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "multer": "^1.4.5-lts.1",
    "pg": "^8.11.3",
    "aws-sdk": "^2.1486.0",
    "bcrypt": "^5.1.1",
    "jsonwebtoken": "^9.0.2",
    "nodemailer": "^6.9.7",
    "dotenv": "^16.3.1",
    "helmet": "^7.1.0",
    "express-rate-limit": "^7.1.5",
    "compression": "^1.7.4",
    "morgan": "^1.10.0"
  }
}
EOF

# Create database schema
cat > database.sql << "DBEOF"
-- File Server Database Schema

-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    role VARCHAR(20) DEFAULT 'user' CHECK (role IN ('admin', 'user')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create files table
CREATE TABLE IF NOT EXISTS files (
    id SERIAL PRIMARY KEY,
    original_name VARCHAR(255) NOT NULL,
    filename VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    mimetype VARCHAR(100),
    size BIGINT NOT NULL,
    s3_key VARCHAR(500),
    s3_bucket VARCHAR(100),
    uploaded_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create file_shares table (for tracking file sharing via email)
CREATE TABLE IF NOT EXISTS file_shares (
    id SERIAL PRIMARY KEY,
    file_id INTEGER REFERENCES files(id) ON DELETE CASCADE,
    shared_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    shared_with_email VARCHAR(100) NOT NULL,
    message TEXT,
    shared_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP
);

-- Create download_logs table (for tracking file downloads)
CREATE TABLE IF NOT EXISTS download_logs (
    id SERIAL PRIMARY KEY,
    file_id INTEGER REFERENCES files(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    ip_address INET,
    user_agent TEXT,
    downloaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_files_uploaded_by ON files(uploaded_by);
CREATE INDEX IF NOT EXISTS idx_files_uploaded_at ON files(uploaded_at);
CREATE INDEX IF NOT EXISTS idx_file_shares_file_id ON file_shares(file_id);
CREATE INDEX IF NOT EXISTS idx_download_logs_file_id ON download_logs(file_id);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS \$\$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
\$\$ language 'plpgsql';

-- Create triggers for updated_at
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at 
    BEFORE UPDATE ON users 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_files_updated_at ON files;
CREATE TRIGGER update_files_updated_at 
    BEFORE UPDATE ON files 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Insert sample admin user (password: admin123)
INSERT INTO users (username, email, password, role) VALUES 
('admin', 'admin@fileserver.local', '\$2b\$10\$rOJ0Jz8.QpNkL7j9KqN3C.VtD4xKfXnhKGdVS4zWm2hC3j7Wy5Jiq', 'admin')
ON CONFLICT (username) DO NOTHING;

COMMIT;
DBEOF

# Set up the database schema
export PGPASSWORD="${db_password}"
psql -h ${db_host} -U ${db_username} -d ${db_name} -f database.sql

# Create main server application
cat > index.js << "JSEOF"
const express = require("express");
const cors = require("cors");
const multer = require("multer");
const path = require("path");
const fs = require("fs");
const { Pool } = require("pg");
const AWS = require("aws-sdk");
const bcrypt = require("bcrypt");
const jwt = require("jsonwebtoken");
const nodemailer = require("nodemailer");
require("dotenv").config();

const app = express();
const PORT = process.env.SERVER_PORT || 8000;

const s3 = new AWS.S3({
  region: process.env.AWS_REGION || "eu-central-1"
});

const pool = new Pool({
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  port: process.env.DB_PORT || 5432,
  ssl: process.env.NODE_ENV === "production" ? { rejectUnauthorized: false } : false
});

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const uploadsDir = process.env.UPLOAD_DIR || "./uploads";
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadsDir);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + "-" + Math.round(Math.random() * 1E9);
    cb(null, file.fieldname + "-" + uniqueSuffix + path.extname(file.originalname));
  }
});

const upload = multer({
  storage: storage,
  limits: {
    fileSize: 10 * 1024 * 1024,
  },
  fileFilter: (req, file, cb) => {
    cb(null, true);
  }
});

const authenticateToken = (req, res, next) => {
  const authHeader = req.headers["authorization"];
  const token = authHeader && authHeader.split(" ")[1];

  if (!token) {
    return res.status(401).json({ message: "Access token required" });
  }

  jwt.verify(token, process.env.SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({ message: "Invalid or expired token" });
    }
    req.user = user;
    next();
  });
};

const requireAdmin = (req, res, next) => {
  if (req.user.role !== "admin") {
    return res.status(403).json({ message: "Admin access required" });
  }
  next();
};

app.get("/health", (req, res) => {
  res.json({ status: "OK", timestamp: new Date().toISOString() });
});

app.post("/api/register", async (req, res) => {
  try {
    const { username, email, password } = req.body;
    
    const userExists = await pool.query(
      "SELECT id FROM users WHERE username = \$1 OR email = \$2",
      [username, email]
    );
    
    if (userExists.rows.length > 0) {
      return res.status(400).json({ message: "User already exists" });
    }
    
    const saltRounds = 10;
    const hashedPassword = await bcrypt.hash(password, saltRounds);
    
    const userCount = await pool.query("SELECT COUNT(*) FROM users");
    const role = userCount.rows[0].count === "0" ? "admin" : "user";
    
    const result = await pool.query(
      "INSERT INTO users (username, email, password, role) VALUES (\$1, \$2, \$3, \$4) RETURNING id, username, email, role",
      [username, email, hashedPassword, role]
    );
    
    res.status(201).json({
      message: "User created successfully",
      user: result.rows[0]
    });
  } catch (error) {
    console.error("Registration error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
});

app.post("/api/login", async (req, res) => {
  try {
    const { username, password } = req.body;
    
    const result = await pool.query(
      "SELECT * FROM users WHERE username = \$1",
      [username]
    );
    
    if (result.rows.length === 0) {
      return res.status(401).json({ message: "Invalid credentials" });
    }
    
    const user = result.rows[0];
    
    const validPassword = await bcrypt.compare(password, user.password);
    if (!validPassword) {
      return res.status(401).json({ message: "Invalid credentials" });
    }
    
    const token = jwt.sign(
      { id: user.id, username: user.username, role: user.role },
      process.env.SECRET,
      { expiresIn: "24h" }
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
    console.error("Login error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
});

app.post("/api/upload", authenticateToken, requireAdmin, upload.single("file"), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ message: "No file uploaded" });
    }
    
    const { originalname, filename, mimetype, size, path: filepath } = req.file;
    
    const result = await pool.query(
      "INSERT INTO files (original_name, filename, file_path, mimetype, size, uploaded_by) VALUES (\$1, \$2, \$3, \$4, \$5, \$6) RETURNING *",
      [originalname, filename, filepath, mimetype, size, req.user.id]
    );
    
    if (process.env.S3_BUCKET_NAME) {
      try {
        const fileContent = fs.readFileSync(filepath);
        const uploadParams = {
          Bucket: process.env.S3_BUCKET_NAME,
          Key: "files/" + filename,
          Body: fileContent,
          ContentType: mimetype
        };
        
        await s3.upload(uploadParams).promise();
        
        await pool.query(
          "UPDATE files SET s3_key = \$1, s3_bucket = \$2 WHERE id = \$3",
          ["files/" + filename, process.env.S3_BUCKET_NAME, result.rows[0].id]
        );
      } catch (s3Error) {
        console.error("S3 upload error:", s3Error);
      }
    }
    
    res.status(201).json({
      message: "File uploaded successfully",
      file: result.rows[0]
    });
  } catch (error) {
    console.error("Upload error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
});

app.get("/api/files", authenticateToken, async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT f.*, u.username as uploaded_by_username FROM files f LEFT JOIN users u ON f.uploaded_by = u.id ORDER BY f.uploaded_at DESC"
    );
    
    res.json(result.rows);
  } catch (error) {
    console.error("Get files error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
});

app.get("/api/download/:id", authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    const result = await pool.query("SELECT * FROM files WHERE id = \$1", [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ message: "File not found" });
    }
    
    const file = result.rows[0];
    
    if (file.s3_key && file.s3_bucket) {
      try {
        const params = {
          Bucket: file.s3_bucket,
          Key: file.s3_key
        };
        
        const s3Object = await s3.getObject(params).promise();
        
        res.setHeader("Content-Disposition", "attachment; filename=\"" + file.original_name + "\"");
        res.setHeader("Content-Type", file.mimetype);
        res.send(s3Object.Body);
        return;
      } catch (s3Error) {
        console.error("S3 download error:", s3Error);
      }
    }
    
    if (fs.existsSync(file.file_path)) {
      res.setHeader("Content-Disposition", "attachment; filename=\"" + file.original_name + "\"");
      res.setHeader("Content-Type", file.mimetype);
      res.sendFile(path.resolve(file.file_path));
    } else {
      res.status(404).json({ message: "File not found on server" });
    }
  } catch (error) {
    console.error("Download error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
});

app.delete("/api/files/:id", authenticateToken, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    
    const result = await pool.query("SELECT * FROM files WHERE id = \$1", [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ message: "File not found" });
    }
    
    const file = result.rows[0];
    
    if (file.s3_key && file.s3_bucket) {
      try {
        await s3.deleteObject({
          Bucket: file.s3_bucket,
          Key: file.s3_key
        }).promise();
      } catch (s3Error) {
        console.error("S3 delete error:", s3Error);
      }
    }
    
    if (fs.existsSync(file.file_path)) {
      fs.unlinkSync(file.file_path);
    }
    
    await pool.query("DELETE FROM files WHERE id = \$1", [id]);
    
    res.json({ message: "File deleted successfully" });
  } catch (error) {
    console.error("Delete error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
});

app.post("/api/send-file/:id", authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    const { email, message } = req.body;
    
    const result = await pool.query("SELECT * FROM files WHERE id = \$1", [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ message: "File not found" });
    }
    
    const file = result.rows[0];
    const downloadLink = req.protocol + "://" + req.get("host") + "/api/download/" + file.id;
    
    res.json({ 
      message: "Download link generated",
      downloadLink: downloadLink
    });
  } catch (error) {
    console.error("Send file error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
});

app.get("/api/user", authenticateToken, (req, res) => {
  res.json({
    id: req.user.id,
    username: req.user.username,
    role: req.user.role
  });
});

app.use((error, req, res, next) => {
  if (error instanceof multer.MulterError) {
    if (error.code === "LIMIT_FILE_SIZE") {
      return res.status(400).json({ message: "File too large" });
    }
  }
  
  console.error(error);
  res.status(500).json({ message: "Internal server error" });
});

app.listen(PORT, "0.0.0.0", () => {
  console.log("File Server running on port " + PORT);
  console.log("Environment: " + process.env.NODE_ENV);
  console.log("Database: " + process.env.DB_HOST + ":" + process.env.DB_PORT + "/" + process.env.DB_NAME);
});
JSEOF

# Create environment file
cat > .env << ENVEOF
NODE_ENV=production
DB_HOST=${db_host}
DB_NAME=${db_name}
DB_USER=${db_username}
DB_PASSWORD=${db_password}
DB_PORT=5432
SERVER_PORT=8000
CLIENT_PORT=""
VITE_SERVER_PORT=""
UPLOAD_DIR=./uploads
SECRET=$(openssl rand -base64 32)
S3_BUCKET_NAME=${s3_bucket_name}
AWS_REGION=eu-central-1
ENVEOF

# Install dependencies
npm install

# Create uploads directory
mkdir -p uploads

# Create Dockerfile
cat > Dockerfile << "DOCKEREOF"
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./

RUN npm ci --only=production

COPY . .

RUN mkdir -p uploads

EXPOSE 8000

CMD ["npm", "start"]
DOCKEREOF

# Build Docker image
docker build -t fileserver-app .

# Create Docker Compose file
cat > docker-compose.yml << "COMPOSEEOF"
version: '3.8'

services:
  app:
    image: fileserver-app
    ports:
      - "8000:8000"
    environment:
      - NODE_ENV=production
    env_file:
      - .env
    volumes:
      - ./uploads:/app/uploads
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
COMPOSEEOF

# Start the application
docker-compose up -d

# Install PM2 for process management
npm install -g pm2

# Start with PM2 as backup
pm2 start npm --name "fileserver-app" -- start
pm2 startup
pm2 save

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent

# CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << "CWEOF"
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/home/ec2-user/fileserver-app/server/logs/*.log",
            "log_group_name": "/aws/ec2/app/fileserver",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "CWAgent",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_iowait",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          "used_percent"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      }
    }
  }
}
CWEOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# Create health check endpoint
mkdir -p /home/ec2-user/health
cat > /home/ec2-user/health/index.html << "HEALTHEOF"
<!DOCTYPE html>
<html>
<head>
    <title>File Server Health Check</title>
</head>
<body>
    <h1>File Server is Running</h1>
    <p>Status: OK</p>
</body>
</html>
HEALTHEOF

# Change ownership
chown -R ec2-user:ec2-user /home/ec2-user