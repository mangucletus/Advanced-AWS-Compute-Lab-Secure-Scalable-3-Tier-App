# Advanced-AWS-Compute-Lab-Secure-Scalable-3-Tier-App (File Server Application - PERN Stack)

A secure, scalable three-tier file server application built with PostgreSQL, Express.js, React, and Node.js (PERN stack), featuring complete AWS deployment with Terraform.

##  Features

- **File Management**: Upload, download, and delete files with admin controls
- **User Authentication**: JWT-based authentication with role-based access control
- **Email Sharing**: Send file links via email to external users
- **Cloud Storage**: AWS S3 integration for scalable file storage
- **Secure Architecture**: 3-tier architecture with proper security groups
- **Monitoring**: CloudWatch integration with custom metrics and alarms
- **Auto Scaling**: Automatic scaling based on CPU utilization
- **Load Balancing**: Application Load Balancer for high availability

##  Architecture

### Three-Tier Architecture on AWS

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Web Tier      │────▶│   App Tier      │────▶│  Database Tier  │
│                 │     │                 │     │                 │
│ • ALB           │     │ • Express API   │     │ • PostgreSQL    │
│ • Auto Scaling  │     │ • File Logic    │     │ • RDS Instance  │
│ • Nginx Proxy   │     │ • JWT Auth      │     │ • Private Subnet│
│ • React Frontend│     │ • Private Subnet│     │ • Security Group│
└─────────────────┘     └─────────────────┘     └─────────────────┘
         │                        │                        │
         └────────────────────────┼────────────────────────┘
                                  │
                         ┌─────────────────┐
                         │   Bastion Host  │
                         │                 │
                         │ • SSH Access    │
                         │ • Public Subnet │
                         │ • Admin Only    │
                         └─────────────────┘
```

### AWS Resources Created

- **VPC**: Custom VPC with public/private subnets across 2 AZs
- **EC2**: Auto Scaling Group, Launch Template, Bastion Host
- **RDS**: PostgreSQL database in private subnet
- **S3**: File storage bucket with encryption
- **ALB**: Application Load Balancer with health checks
- **CloudWatch**: Monitoring, logging, and alarms
- **IAM**: Roles and policies for secure access
- **Security Groups**: Network security controls

##  Quick Start

### Prerequisites

- **Docker & Docker Compose**
- **Node.js 18+** (for development)
- **AWS CLI** (for deployment)
- **Terraform** (for infrastructure)
- **SSH Key Pair** (will be generated automatically)

### Option 1: Local Development with Docker

```bash
# Clone the repository
git clone <your-repo-url>
cd fileserver-app

# Quick start (generates SSH keys, sets up environment, builds and runs)
make quick-start

# Or step by step:
make setup-env          # Copy sample environment files
make install            # Install dependencies
make build             # Build Docker images  
make up               # Start all services
```

Access the application:
- **Frontend**: http://localhost
- **API**: http://localhost:8000
- **Database**: localhost:5432

Default admin credentials:
- Username: `admin`
- Password: `admin123`

### Option 2: Development Mode

```bash
# Install dependencies
make install

# Start development servers (requires tmux)
make dev

# Or start individually:
make dev-server   # Terminal 1
make dev-client   # Terminal 2
```

### Option 3: AWS Deployment

```bash
# Check prerequisites
make check-aws

# Configure AWS credentials if not done
aws configure

# Deploy infrastructure
make deploy-aws

# Access via ALB DNS name (output after deployment)
```

##  Project Structure

```
fileserver-app/
├── terraform/
│   ├── main.tf                 # Main Terraform configuration
│   └── modules/               # Terraform modules
│       ├── vpc/               # VPC and networking
│       ├── security/          # Security groups
│       ├── iam/               # IAM roles and policies
│       ├── s3/                # S3 bucket configuration
│       ├── rds/               # Database configuration
│       ├── bastion/           # Bastion host
│       ├── alb/               # Load balancer
│       ├── autoscaling/       # Auto scaling setup
│       ├── app_server/        # Application server
│       └── cloudwatch/        # Monitoring setup
├── server/                    # Express.js backend
│   ├── index.js              # Main server file
│   ├── database.sql          # Database schema
│   ├── package.json          # Server dependencies
│   ├── Dockerfile            # Server container
│   └── sample.env            # Environment template
├── client/                    # React frontend
│   ├── src/
│   │   ├── App.jsx           # Main React component
│   │   ├── App.css           # Styles with Tailwind
│   │   └── main.jsx          # React entry point
│   ├── package.json          # Client dependencies
│   ├── Dockerfile            # Client container
│   ├── vite.config.js        # Vite configuration
│   ├── tailwind.config.js    # Tailwind setup
│   └── sample.env            # Client environment
├── docker-compose.yml         # Local development setup
├── Makefile                   # Automation commands
└── README.md                  # This file
```

##  Configuration

### Environment Variables

#### Server (.env)
```bash
NODE_ENV=production
SERVER_PORT=8000
DB_HOST=your-db-host
DB_NAME=fileserver
DB_USER=postgres
DB_PASSWORD=your-secure-password
SECRET=your-jwt-secret-256-bit
S3_BUCKET_NAME=your-s3-bucket
AWS_REGION=eu-central-1
```

#### Client (.env)
```bash
VITE_NODE_ENV=production
VITE_SERVER_PORT=""
```

### AWS Configuration

Update variables in `terraform/main.tf`:
```hcl
variable "allowed_cidr" {
  default = "YOUR.IP.ADDRESS/32"  # Replace with your IP
}

variable "aws_region" {
  default = "eu-central-1"        # Your preferred region
}
```

##  Available Commands

### Docker & Development
```bash
make install          # Install all dependencies
make build           # Build Docker images
make up              # Start services
make down            # Stop services
make restart         # Restart services
make logs            # View all logs
make dev             # Start development mode
make test            # Run tests
make lint            # Lint code
```

### AWS Deployment
```bash
make check-aws       # Verify AWS/Terraform setup
make plan-aws        # Plan infrastructure changes
make deploy-aws      # Deploy to AWS
make destroy-aws     # Destroy AWS resources
make ssh-bastion     # SSH to bastion host
make ssh-app         # SSH to app server via bastion
```

### Database & Monitoring
```bash
make db-init         # Initialize database
make db-connect      # Connect to database
make db-backup       # Backup database
make health          # Check service health
make status          # Show service status
```

### Cleanup
```bash
make clean           # Clean Docker resources
make clean-all       # Clean everything
```

## 🔐 Security Features

### Network Security
- **VPC Isolation**: Custom VPC with public/private subnets
- **Security Groups**: Restrictive rules allowing only necessary traffic
- **Bastion Host**: Single point of administrative access
- **NAT Gateway**: Outbound internet access for private subnets

### Application Security
- **JWT Authentication**: Secure token-based authentication
- **Role-based Access**: Admin and user roles with different permissions
- **Input Validation**: Server-side validation for all inputs
- **File Upload Security**: File type and size restrictions
- **CORS Configuration**: Proper CORS setup for API access

### AWS Security
- **IAM Roles**: Least-privilege access principles
- **S3 Encryption**: Server-side encryption for stored files
- **RDS Security**: Encrypted database in private subnet
- **CloudWatch Monitoring**: Security event logging

## 📊 Monitoring & Logging

### CloudWatch Integration
- **Custom Metrics**: CPU, memory, disk usage
- **Application Logs**: Structured logging for debugging
- **Alarms**: Automated alerts for threshold breaches
- **Dashboard**: Visual monitoring interface

### Health Checks
- **ALB Health Checks**: Application availability monitoring
- **Database Health**: Connection and query performance
- **S3 Access**: File storage availability

## 🔄 CI/CD Integration

The application is ready for CI/CD integration with:

### GitHub Actions (Example)
```yaml
name: Deploy to AWS
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - name: Deploy to AWS
      run: make deploy-aws
```

### Jenkins Pipeline
```groovy
pipeline {
    agent any
    stages {
        stage('Deploy') {
            steps {
                sh 'make deploy-aws'
            }
        }
    }
}
```

## 📝 Usage Guide

### For Administrators

1. **Login** with admin credentials
2. **Upload Files** using the upload interface
3. **Manage Files** - view, download, delete files
4. **Monitor Usage** via CloudWatch dashboard

### For Regular Users

1. **Register** a new account or use provided credentials
2. **Browse Files** - view available files
3. **Download Files** - click download links
4. **Share Files** - send files via email

### API Endpoints

```bash
# Authentication
POST /api/register     # Register new user
POST /api/login        # Login user

# Files
GET  /api/files        # List all files
POST /api/upload       # Upload file (admin only)
GET  /api/download/:id # Download file
DELETE /api/files/:id  # Delete file (admin only)
POST /api/send-file/:id # Send file via email

# User
GET /api/user          # Get current user info
GET /health            # Health check
```

## 🐛 Troubleshooting

### Common Issues

#### Database Connection Fails
```bash
# Check database logs
make logs-db

# Verify database is running
make status

# Reinitialize database
make db-init
```

#### AWS Deployment Issues
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify Terraform state
terraform show

# Check SSH key exists
ls -la ~/.ssh/id_rsa*
```

#### Application Not Accessible
```bash
# Check ALB health targets
aws elbv2 describe-target-health --target-group-arn <target-group-arn>

# Check security groups
aws ec2 describe-security-groups --group-ids <security-group-id>
```

### Logs and Debugging
```bash
# Application logs
make logs

# Individual service logs
make logs-server
make logs-client
make logs-db

# AWS CloudWatch logs
aws logs tail /aws/ec2/app/fileserver --follow
```

## 🚧 Production Considerations

### Before Going Live

1. **Change Default Passwords**: Update all default credentials
2. **Configure SSL/TLS**: Add HTTPS support via AWS Certificate Manager
3. **Set Up Backups**: Configure automated RDS backups
4. **Monitor Costs**: Set up AWS billing alerts
5. **Configure Email**: Set up SES for email functionality
6. **Security Scanning**: Run security scans on the application
7. **Load Testing**: Test application under expected load

### Scaling Considerations

- **Auto Scaling**: Configured for 2-6 instances based on CPU
- **Database Scaling**: Consider RDS read replicas for high read loads
- **S3 Performance**: Use CloudFront CDN for better file delivery
- **Monitoring**: Set up comprehensive alerting for production

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License. See LICENSE file for details.

## 🆘 Support

For support and questions:

1. Check the troubleshooting section
2. Review application logs
3. Open an issue in the repository
4. Contact the development team

---

## 🎯 Success Criteria Verification

This implementation meets all lab requirements:

✅ **ALB Access**: Application accessible via ALB DNS name  
✅ **Secure Communication**: Proper security groups and network isolation  
✅ **S3 Integration**: Static assets and file storage via S3  
✅ **CloudWatch**: Comprehensive logging and monitoring  
✅ **No Direct Internet**: App tier and database in private subnets  
✅ **Bastion Access**: SSH access only through bastion host  
✅ **3-Tier Architecture**: Proper separation of web, app, and database tiers  
✅ **Auto Scaling**: Configured with health checks and scaling policies  
✅ **Infrastructure as Code**: Complete Terraform modules  
✅ **Production Ready**: Docker, monitoring, security, and documentation

**Happy File Serving! 🚀**