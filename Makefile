# Makefile for File Server Application

.PHONY: help build build-client build-server up down restart logs clean install install-client install-server dev test lint deploy-aws destroy-aws

# Colors for output
RED=\033[0;31m
GREEN=\033[0;32m
YELLOW=\033[0;33m
BLUE=\033[0;34m
NC=\033[0m # No Color

help: ## Show this help message
	@echo "File Server Application - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "$(BLUE)%-20s$(NC) %s\n", $$1, $$2}'

# Installation commands
install: install-server install-client ## Install all dependencies
	@echo "$(GREEN)✓ All dependencies installed successfully$(NC)"

install-server: ## Install server dependencies
	@echo "$(YELLOW)Installing server dependencies...$(NC)"
	cd server && npm install

install-client: ## Install client dependencies  
	@echo "$(YELLOW)Installing client dependencies...$(NC)"
	cd client && npm install

# Environment setup
setup-env: ## Copy sample environment files
	@echo "$(YELLOW)Setting up environment files...$(NC)"
	cp server/sample.env server/.env
	cp client/sample.env client/.env
	@echo "$(GREEN)✓ Environment files created. Please edit them with your values.$(NC)"

# Development commands
dev-server: ## Start development server
	@echo "$(YELLOW)Starting development server...$(NC)"
	cd server && npm run dev

dev-client: ## Start development client
	@echo "$(YELLOW)Starting development client...$(NC)"
	cd client && npm run dev

dev: ## Start both development server and client (requires tmux)
	@echo "$(YELLOW)Starting development environment...$(NC)"
	tmux new-session -d -s fileserver-dev 'cd server && npm run dev'
	tmux split-window -h 'cd client && npm run dev'
	tmux attach-session -t fileserver-dev

# Docker commands
build: build-server build-client ## Build all Docker images
	@echo "$(GREEN)✓ All Docker images built successfully$(NC)"

build-server: ## Build server Docker image
	@echo "$(YELLOW)Building server Docker image...$(NC)"
	docker build -t fileserver-backend:latest ./server

build-client: ## Build client Docker image
	@echo "$(YELLOW)Building client Docker image...$(NC)"
	docker build -t fileserver-frontend:latest ./client

up: ## Start all services with Docker Compose
	@echo "$(YELLOW)Starting File Server application...$(NC)"
	docker-compose up -d
	@echo "$(GREEN)✓ Application started at http://localhost$(NC)"

down: ## Stop all services
	@echo "$(YELLOW)Stopping File Server application...$(NC)"
	docker-compose down

restart: down up ## Restart all services

logs: ## Show application logs
	docker-compose logs -f

logs-server: ## Show server logs only
	docker-compose logs -f backend

logs-client: ## Show client logs only
	docker-compose logs -f frontend

logs-db: ## Show database logs only
	docker-compose logs -f database

# Database commands
db-init: ## Initialize database with schema
	@echo "$(YELLOW)Initializing database...$(NC)"
	docker-compose exec database psql -U postgres -d fileserver -f /docker-entrypoint-initdb.d/01-schema.sql

db-connect: ## Connect to database
	docker-compose exec database psql -U postgres -d fileserver

db-backup: ## Backup database
	@echo "$(YELLOW)Creating database backup...$(NC)"
	mkdir -p backups
	docker-compose exec database pg_dump -U postgres -d fileserver > backups/fileserver-$(shell date +%Y%m%d-%H%M%S).sql
	@echo "$(GREEN)✓ Database backup created in backups/ directory$(NC)"

# Testing and linting
test: test-server ## Run all tests
	@echo "$(GREEN)✓ All tests passed$(NC)"

test-server: ## Run server tests
	@echo "$(YELLOW)Running server tests...$(NC)"
	cd server && npm test

lint: lint-server lint-client ## Run linting for all code
	@echo "$(GREEN)✓ All linting checks passed$(NC)"

lint-server: ## Lint server code
	@echo "$(YELLOW)Linting server code...$(NC)"
	cd server && npm run lint

lint-client: ## Lint client code
	@echo "$(YELLOW)Linting client code...$(NC)"
	cd client && npm run lint

# Production build
build-prod: ## Build production assets
	@echo "$(YELLOW)Building production assets...$(NC)"
	cd client && npm run build
	@echo "$(GREEN)✓ Production build completed$(NC)"

# AWS Deployment commands
check-aws: ## Check AWS CLI and Terraform installation
	@echo "$(YELLOW)Checking AWS and Terraform installation...$(NC)"
	@which aws > /dev/null || (echo "$(RED)AWS CLI is not installed$(NC)" && exit 1)
	@which terraform > /dev/null || (echo "$(RED)Terraform is not installed$(NC)" && exit 1)
	@aws sts get-caller-identity > /dev/null || (echo "$(RED)AWS credentials not configured$(NC)" && exit 1)
	@echo "$(GREEN)✓ AWS and Terraform are properly configured$(NC)"

init-terraform: check-aws ## Initialize Terraform
	@echo "$(YELLOW)Initializing Terraform...$(NC)"
	terraform init
	@echo "$(GREEN)✓ Terraform initialized$(NC)"

plan-aws: init-terraform ## Plan AWS infrastructure deployment
	@echo "$(YELLOW)Planning AWS infrastructure...$(NC)"
	terraform plan -out=tfplan
	@echo "$(GREEN)✓ Terraform plan created$(NC)"

deploy-aws: plan-aws ## Deploy to AWS infrastructure
	@echo "$(YELLOW)Deploying to AWS...$(NC)"
	terraform apply tfplan
	@echo "$(GREEN)✓ AWS infrastructure deployed successfully$(NC)"
	@echo "$(BLUE)Application URL: http://$$(terraform output -raw alb_dns_name)$(NC)"
	@echo "$(BLUE)Bastion IP: $$(terraform output -raw bastion_ip)$(NC)"

destroy-aws: ## Destroy AWS infrastructure
	@echo "$(RED)WARNING: This will destroy all AWS resources!$(NC)"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@echo "$(YELLOW)Destroying AWS infrastructure...$(NC)"
	terraform destroy
	@echo "$(GREEN)✓ AWS infrastructure destroyed$(NC)"

ssh-bastion: ## SSH to bastion host
	@echo "$(YELLOW)Connecting to bastion host...$(NC)"
	ssh -i ~/.ssh/id_rsa ec2-user@$$(terraform output -raw bastion_ip)

ssh-app: ## SSH to app server via bastion
	@echo "$(YELLOW)Connecting to app server via bastion...$(NC)"
	ssh -i ~/.ssh/id_rsa -J ec2-user@$$(terraform output -raw bastion_ip) ec2-user@$$(terraform output -raw app_server_private_ip)

# Cleanup commands
clean: ## Clean up Docker resources
	@echo "$(YELLOW)Cleaning up Docker resources...$(NC)"
	docker-compose down -v
	docker system prune -f
	@echo "$(GREEN)✓ Docker cleanup completed$(NC)"

clean-all: clean ## Clean up everything including node_modules
	@echo "$(YELLOW)Cleaning up all build artifacts...$(NC)"
	rm -rf server/node_modules
	rm -rf client/node_modules
	rm -rf client/dist
	rm -rf backups
	rm -f tfplan
	@echo "$(GREEN)✓ Complete cleanup finished$(NC)"

# Monitoring and status
status: ## Show service status
	@echo "$(BLUE)File Server Application Status:$(NC)"
	@echo ""
	docker-compose ps

health: ## Check health of all services
	@echo "$(YELLOW)Checking service health...$(NC)"
	@curl -s http://localhost:8000/health | jq . 2>/dev/null || echo "Backend health check failed"
	@curl -s http://localhost/ > /dev/null && echo "$(GREEN)✓ Frontend is responsive$(NC)" || echo "$(RED)✗ Frontend is not responding$(NC)"

# Generate SSH key pair if not exists
generate-ssh: ## Generate SSH key pair for AWS
	@if [ ! -f ~/.ssh/id_rsa ]; then \
		echo "$(YELLOW)Generating SSH key pair...$(NC)"; \
		ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""; \
		echo "$(GREEN)✓ SSH key pair generated$(NC)"; \
	else \
		echo "$(GREEN)✓ SSH key pair already exists$(NC)"; \
	fi

# Quick start for new developers
quick-start: generate-ssh setup-env install build up ## Quick start for development
	@echo ""
	@echo "$(GREEN)🎉 File Server is ready!$(NC)"
	@echo ""
	@echo "$(BLUE)Frontend:$(NC) http://localhost"
	@echo "$(BLUE)Backend API:$(NC) http://localhost:8000"
	@echo "$(BLUE)Database:$(NC) localhost:5432"
	@echo ""
	@echo "$(YELLOW)Default admin login:$(NC)"
	@echo "  Username: admin"
	@echo "  Password: admin123"
	@echo ""
	@echo "Run '$(BLUE)make logs$(NC)' to see application logs"
	@echo "Run '$(BLUE)make help$(NC)' to see all available commands"