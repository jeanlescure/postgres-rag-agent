# PostgreSQL RAG Agent for OpenClaw

A production-ready retrieval-augmented generation (RAG) system built with PostgreSQL, Payload CMS, pgvector, Elasticsearch, and Apache Tika. Designed for the OpenClaw agent platform with multiple MCP servers for document ingestion, semantic search, and knowledge management.

## Features

- **PayloadCMS Backend**: Automatic CRUD APIs, GraphQL, and admin UI for documents
- **Vector Search**: pgvector + pgEdge Vectorizer for automatic embedding and chunking
- **Full-Text Search**: Elasticsearch integration for keyword-based document retrieval
- **Format Support**: Apache Tika for converting Word, PDF, XLSX, and other formats
- **Hash-Based Deduplication**: Prevents re-ingestion of duplicate documents
- **Agentic RAG**: MCP servers for semantic search, full-text search, and document management
- **Docker Development**: Easy local development with docker-compose and Makefile
- **Hot Reload**: PayloadCMS and vectorizer worker support hot module reload

## Quick Start

### Prerequisites

- Docker & Docker Compose
- Bun (for local development)
- Make
- Git

### Initialize

```bash
make init
```

This will:
1. Download SSL certificates for `local.devhost.name`
2. Create `.env` from `.env.example`
3. Install dependencies

### Run

```bash
make local-dev
```

Services start automatically:
- **PayloadCMS Admin**: https://local.devhost.name/admin
- **API**: https://local.devhost.name/api
- **Elasticsearch**: https://local.devhost.name/elasticsearch
- **Tika**: https://local.devhost.name/tika
- **Adminer (DB Browser)**: https://local.devhost.name/adminer

### Background Mode

```bash
make local-dev-daemon
make logs-all  # View logs
make local-dev-stop  # Stop
```

## Development Commands

```bash
make init                  # First-time setup
make local-dev             # Start services (foreground)
make local-dev-daemon      # Start services (background)
make local-dev-stop        # Stop services
make logs-all              # View all logs
make logs-cms              # View PayloadCMS logs
make logs-vectorizer       # View vectorizer logs
make restart-cms           # Restart a service
make cms-cli               # Open bash in PayloadCMS
make cms-migrate           # Run database migrations
make local-reset-db        # Wipe PostgreSQL and restart
make seed-documents        # Load sample documents
make health                # Check service health
make lint-all              # Lint all code
make build-all             # Build all services
make test-all              # Run all tests
```

## Project Structure

```
.
├── .plan/                          # Implementation phases
│   ├── PHASE_1.md                  # Foundation & infrastructure
│   ├── PHASE_2.md                  # Knowledge retrieval & agentic layer
│   ├── PHASE_3.md                  # Production hardening
│   └── PHASE_4.md                  # Advanced features & Graph RAG
├── docker-compose.yml              # Service definitions
├── Makefile                        # Development commands
├── .env.example                    # Environment template
├── README.md                       # This file
├── cms/                            # PayloadCMS application
│   ├── src/
│   │   ├── collections/            # Data schemas
│   │   │   ├── Documents.ts
│   │   │   ├── DocumentChunks.ts
│   │   │   └── DocumentMetadata.ts
│   │   ├── endpoints/              # Custom REST endpoints
│   │   ├── hooks/                  # Payload hooks
│   │   └── payload.config.ts
│   ├── package.json
│   └── Dockerfile
├── vectorizer-worker/              # pgEdge Vectorizer background worker
│   ├── src/
│   │   ├── worker.ts               # Main worker loop
│   │   ├── embeddings.ts           # Embedding provider logic
│   │   └── tika.ts                 # Apache Tika integration
│   ├── scripts/
│   │   └── seed-documents.ts       # Load sample documents
│   ├── package.json
│   └── Dockerfile
├── .docker/                        # Docker data volumes
│   ├── postgres/data/
│   └── elasticsearch/data/
└── certs/                          # SSL certificates (from local-dev-host-certs)
```

## Architecture

### Services

| Service | Purpose | Port |
|---------|---------|------|
| **nginx-proxy** | Reverse proxy + SSL termination | 80, 443 |
| **PayloadCMS** | Headless CMS + API backend | 3000 |
| **PostgreSQL** | Primary data store + vectors | 5432 |
| **Elasticsearch** | Full-text search index | 9200 |
| **Apache Tika** | Document format conversion | 9998 |
| **Vectorizer Worker** | Background embedding service | (background) |
| **Adminer** | Database UI (dev only) | 9093 |

### Data Flow

1. **Document Ingestion**
   - User uploads file via API
   - PayloadCMS beforeCreate hook validates hash (deduplication)
   - Apache Tika extracts plaintext (if needed)
   - Document stored in PostgreSQL

2. **Vectorization**
   - afterCreate hook triggers pgEdge Vectorizer
   - Status changes to `vectorizing`
   - Background worker picks up job, generates embeddings
   - Chunks stored in `DocumentChunks` collection
   - Status changes to `complete`

3. **Indexing**
   - Elasticsearch sync hook indexes document metadata
   - Full-text search becomes available

4. **Retrieval (Agent)**
   - Agent calls `semantic_search` MCP → pgvector (similarity search)
   - Agent calls `full_text_search` MCP → Elasticsearch (keyword search)
   - Results injected into agent context

## Configuration

Edit `.env` to customize:

- **Embeddings**: Switch between OpenAI and Ollama (local)
- **Chunk size**: Adjust `CHUNK_SIZE` for different document types
- **Vector dimension**: Must match your embedding model
- **Database**: PostgreSQL credentials and name

## API Examples

### Create Document

```bash
curl -X POST https://local.devhost.name/api/documents \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "my-doc.pdf",
    "hash": "sha256:abcd1234...",
    "category": "projects",
    "tags": ["important", "ai"],
    "status": "pending"
  }'
```

### Query Collections

**REST:**
```bash
GET https://local.devhost.name/api/documents
GET https://local.devhost.name/api/document-chunks
GET https://local.devhost.name/api/document-metadata
```

**GraphQL:**
```bash
POST https://local.devhost.name/api/graphql
```

## MCP Servers (Phase 2)

When fully implemented:

- `document-ingestion-mcp`: Upload and ingest documents
- `knowledge-query-mcp`: Semantic + full-text search
- `document-management-mcp`: List, delete, manage documents

## Troubleshooting

### Services won't start
```bash
make local-reset-db      # Reset database
docker compose down -v   # Remove all volumes
make local-dev           # Start fresh
```

### Certificate errors
```bash
make get-certs-local-dev
docker compose restart proxy
```

### PayloadCMS won't connect to database
```bash
make cms-migrate         # Run migrations
docker compose restart cms
```

### Vectorizer stuck
```bash
make logs-vectorizer     # Check logs
docker compose restart vectorizer-worker
```

## Implementation Phases

See `.plan/` directory for detailed implementation roadmap:

- **Phase 1**: Foundation & Infrastructure (this folder) ✅
- **Phase 2**: Knowledge Retrieval & Agentic Layer
- **Phase 3**: Production Hardening & Optimization
- **Phase 4**: Advanced Features & Graph RAG

## Technology Stack

- **Runtime**: Bun (TypeScript/JavaScript)
- **CMS**: Payload v3 (headless)
- **Database**: PostgreSQL 17 + pgvector + pgEdge
- **Search**: Elasticsearch 8.x
- **Vector Embeddings**: OpenAI API or Ollama (local)
- **Document Processing**: Apache Tika
- **Proxy**: nginx-proxy
- **Reverse Proxy**: nginx-proxy with SSL auto-renewal
- **Container Orchestration**: Docker Compose

## Contributing

This is a team project. Follow these guidelines:

1. Create a branch for your feature
2. Follow linting rules: `make lint-all-fix`
3. Test your changes: `make test-all`
4. Commit with clear messages
5. Push and create a PR

## License

Proprietary - Clever Synapse / OpenClaw

## Support

For issues or questions:
1. Check `.plan/` documentation
2. Review logs: `make logs-all`
3. Run health check: `make health`
4. Reset database if corrupted: `make local-reset-db`
