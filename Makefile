.PHONY: help docker-build docker-up docker-down docker-logs docker-shell docker-migrate docker-console docker-clean

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

docker-build: ## Build Docker images
	docker-compose --env-file .env.docker build

docker-up: ## Start all services
	docker-compose --env-file .env.docker up -d

docker-down: ## Stop all services
	docker-compose down

docker-logs: ## View logs from all services
	docker-compose logs -f

docker-logs-web: ## View logs from web service
	docker-compose logs -f web

docker-logs-jobs: ## View logs from jobs service
	docker-compose logs -f jobs

docker-logs-slack: ## View logs from slack_socket_mode service
	docker-compose logs -f slack_socket_mode

docker-shell: ## Open a shell in the web container
	docker-compose exec web /bin/bash

docker-migrate: ## Run database migrations
	docker-compose exec web bin/rails db:migrate

docker-console: ## Open Rails console
	docker-compose exec web bin/rails console

docker-clean: ## Stop services and remove volumes (⚠️ deletes data)
	docker-compose down -v

docker-restart: ## Restart all services
	docker-compose restart

docker-ps: ## Show running services
	docker-compose ps

docker-setup: ## Initial setup: create .env.docker from example
	@if [ ! -f .env.docker ]; then \
		cp docker-compose.env.example .env.docker; \
		echo "Created .env.docker from example. Please edit it with your values."; \
	else \
		echo ".env.docker already exists. Skipping."; \
	fi
