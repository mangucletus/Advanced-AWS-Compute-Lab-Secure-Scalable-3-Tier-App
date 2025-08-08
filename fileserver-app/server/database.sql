-- server/database.sql
-- File Server Database Schema

-- Create database (run this separately if needed)
-- CREATE DATABASE fileserver;

-- Connect to the fileserver database before running the following commands

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
CREATE INDEX IF NOT EXISTS idx_file_shares_shared_at ON file_shares(shared_at);
CREATE INDEX IF NOT EXISTS idx_download_logs_file_id ON download_logs(file_id);
CREATE INDEX IF NOT EXISTS idx_download_logs_user_id ON download_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_download_logs_downloaded_at ON download_logs(downloaded_at);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

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
-- Password hash for 'admin123' using bcrypt with salt rounds 10
INSERT INTO users (username, email, password, role) VALUES 
('admin', 'admin@fileserver.local', '$2b$10$rOJ0Jz8.QpNkL7j9KqN3C.VtD4xKfXnhKGdVS4zWm2hC3j7Wy5Jiq', 'admin')
ON CONFLICT (username) DO NOTHING;

-- Insert sample regular user (password: user123)
-- Password hash for 'user123' using bcrypt with salt rounds 10
INSERT INTO users (username, email, password, role) VALUES 
('testuser', 'user@fileserver.local', '$2b$10$mAKa2xLnWKZP3tYn1N0y.eF9XzG4rQ9NpP2xVzZ8mK3jI9QsA1B2K', 'user')
ON CONFLICT (username) DO NOTHING;

-- Create a view for file statistics
CREATE OR REPLACE VIEW file_statistics AS
SELECT 
    COUNT(*) as total_files,
    SUM(size) as total_size,
    AVG(size) as average_size,
    COUNT(DISTINCT uploaded_by) as unique_uploaders,
    MIN(uploaded_at) as first_upload,
    MAX(uploaded_at) as latest_upload
FROM files;

-- Create a view for user file counts
CREATE OR REPLACE VIEW user_file_counts AS
SELECT 
    u.id,
    u.username,
    u.email,
    u.role,
    COUNT(f.id) as file_count,
    COALESCE(SUM(f.size), 0) as total_file_size
FROM users u
LEFT JOIN files f ON u.id = f.uploaded_by
GROUP BY u.id, u.username, u.email, u.role;

-- Create a function to clean up old file shares (optional)
CREATE OR REPLACE FUNCTION cleanup_expired_shares()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM file_shares 
    WHERE expires_at IS NOT NULL AND expires_at < CURRENT_TIMESTAMP;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ language 'plpgsql';

-- Grant permissions (adjust based on your user setup)
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO fileserver_user;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO fileserver_user;

-- Sample data for testing (optional)
-- INSERT INTO files (original_name, filename, file_path, mimetype, size, uploaded_by) VALUES 
-- ('sample.txt', 'sample-12345.txt', './uploads/sample-12345.txt', 'text/plain', 1024, 1),
-- ('document.pdf', 'document-67890.pdf', './uploads/document-67890.pdf', 'application/pdf', 2048, 1);

COMMIT;