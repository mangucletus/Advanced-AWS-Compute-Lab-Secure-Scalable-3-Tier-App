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

# Set up the database schema
export PGPASSWORD="${db_password}"
psql -h ${db_host} -U ${db_username} -d ${db_name} -f database.sql



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


# Build Docker image
docker build -t fileserver-app .

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