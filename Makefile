.PHONY: help

check-certs: ## Check SSL certs for scheduled renewal
	@echo "Checking SSL certificates for scheduled renewal..." ; \
	cd certs && bunx --yes scheduled-renewal-notice

get-certs-local-dev: ## Download the latest SSL certs for "local.devhost.name"
	@rm -rf ./certs ; \
	git clone https://github.com/simplyhexagonal/local-dev-host-certs.git certs ; \
	cp ./certs/local.devhost.name.crt ./certs/default.crt ; \
	cp ./certs/local.devhost.name.key ./certs/default.key ; \
	make check-certs

get-env-local-dev: ## Create local dev .env file from .env.example
	@if [ ! -f .env ]; then \
		cp .env.example .env ; \
		echo "✅ Created .env from .env.example" ; \
	else \
		echo "✅ .env already exists" ; \
	fi

install-dependencies: ## Install dependencies for cms and vectorizer-worker
	cd cms && bun install
	cd vectorizer-worker && bun install

init: ## Initialize project (certs, env, dependencies)
	make get-certs-local-dev
	make get-env-local-dev
	make install-dependencies
	@echo "✅ Project initialized. Run 'make local-dev' to start."

local-dev: ## Run local dev environment using Docker Compose
	@make check-certs && echo "🚀 Running local dev environment." && \
	docker compose up

local-dev-daemon: ## Run local dev environment in background
	@make check-certs && echo "🚀 Running local dev environment in the background." && \
	echo "📋 You can stop with 'make local-dev-stop'." && \
	echo "📜 View logs with 'make logs-all'." && \
	docker compose up -d

local-dev-stop: ## Stop local dev containers
	docker compose stop

local-dev-down: ## Remove local dev containers and volumes
	docker compose down

local-dev-logs: ## Show logs for running services
	docker compose logs -f

restart-cms: ## Restart PayloadCMS container
	docker compose restart cms

restart-vectorizer: ## Restart vectorizer-worker container
	docker compose restart vectorizer-worker

restart-postgres: ## Restart PostgreSQL container
	docker compose restart postgres

restart-elasticsearch: ## Restart Elasticsearch container
	docker compose restart elasticsearch

restart-all: ## Restart all containers
	docker compose restart

stop-cms: ## Stop PayloadCMS container
	docker compose stop cms

logs-cms: ## Show PayloadCMS logs
	docker compose logs -f cms

logs-vectorizer: ## Show vectorizer-worker logs
	docker compose logs -f vectorizer-worker

logs-postgres: ## Show PostgreSQL logs
	docker compose logs -f postgres

logs-elasticsearch: ## Show Elasticsearch logs
	docker compose logs -f elasticsearch

logs-all: ## Show logs from all containers
	docker compose logs -f

cms-cli: ## Open bash in PayloadCMS container
	docker compose exec -it cms bash

cms-migrate: ## Run PayloadCMS database migrations
	docker compose exec -it cms bun run payload migrate

vectorizer-cli: ## Open bash in vectorizer-worker container
	docker compose exec -it vectorizer-worker bash

local-reset-db: ## Reset PostgreSQL database (deletes all data)
	@echo "⚠️  Resetting PostgreSQL database..."
	docker compose stop postgres
	rm -rf ./.docker/postgres/data
	docker compose up -d postgres
	@echo "✅ Database reset. Waiting for PostgreSQL to be ready..."
	sleep 5

seed-documents: ## Load sample documents into the database
	@echo "📥 Seeding sample documents..."
	docker compose exec -it vectorizer-worker bun run scripts/seed-documents.ts

health: ## Check health of all services
	@echo "🏥 Checking service health..."
	@curl -s http://localhost:9200/_cluster/health | jq '.status' && echo "✅ Elasticsearch healthy" || echo "❌ Elasticsearch down"
	@psql postgres://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@localhost:5432/$(POSTGRES_DB) -c "SELECT 1;" > /dev/null 2>&1 && echo "✅ PostgreSQL healthy" || echo "❌ PostgreSQL down"
	@curl -s http://localhost:9998/api/version > /dev/null 2>&1 && echo "✅ Tika healthy" || echo "❌ Tika down"
	@curl -s http://localhost:3000/api/health > /dev/null 2>&1 && echo "✅ PayloadCMS healthy" || echo "❌ PayloadCMS down"

lint-cms: ## Lint PayloadCMS code
	bunx --yes @biomejs/biome check cms/src

lint-cms-fix: ## Fix lint issues in PayloadCMS
	bunx --yes @biomejs/biome check --write cms/src

lint-vectorizer: ## Lint vectorizer-worker code
	bunx --yes @biomejs/biome check vectorizer-worker/src

lint-vectorizer-fix: ## Fix lint issues in vectorizer-worker
	bunx --yes @biomejs/biome check --write vectorizer-worker/src

lint-all: lint-cms lint-vectorizer ## Lint all code

lint-all-fix: lint-cms-fix lint-vectorizer-fix ## Fix all lint issues

build-cms: ## Build PayloadCMS
	cd cms && bun run build

build-vectorizer: ## Build vectorizer-worker
	cd vectorizer-worker && bun run build

build-all: build-cms build-vectorizer ## Build all services

test-cms: ## Run PayloadCMS tests
	cd cms && bun run test

test-vectorizer: ## Run vectorizer-worker tests
	cd vectorizer-worker && bun run test

test-all: test-cms test-vectorizer ## Run all tests

dev-setup: ## One-time development setup
	@echo "🔧 Setting up development environment..."
	mkdir -p .config/nginx-proxy
	mkdir -p .docker/postgres/data
	mkdir -p .docker/elasticsearch/data
	touch .config/nginx-proxy/10.custom.conf
	@echo "✅ Development directories created"

help: ## Show help
	@echo "🚀 Postgres RAG Agent - Development Commands"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick start:"
	@echo "  make init         # Initialize project"
	@echo "  make local-dev    # Start development environment"
	@echo "  make help         # Show this help"
