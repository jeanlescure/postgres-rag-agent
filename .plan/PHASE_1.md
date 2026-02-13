# Phase 1: Foundation & Infrastructure

## Infrastructure Setup (Docker Compose + Makefile)

Use Docker Compose for containerized development. Reference: clever-stack-monolith structure (PayloadCMS on bun, Apache Tika integration).

### Services

- **nginx-proxy**: nginxproxy/nginx-proxy for reverse proxy + automatic SSL
  - Ports: 80, 443
  - Mounted certs directory: `./certs` (for local-dev-host-certs)
  - WebSocket support enabled
  - DEFAULT_HOST: local.devhost.name

- **PayloadCMS**: Payload on bun with hot module reload
  - Image: oven/bun:1.3-debian
  - Port: 3000 (HMR on 38935)
  - Database: PostgreSQL
  - Admin UI at `/admin`
  - Collections for: Documents, DocumentChunks, DocumentMetadata
  - Built-in CRUD APIs (REST + GraphQL)

- **PostgreSQL 17**: Core database
  - Volume: `./.docker/postgres/data`
  - Extensions: pgvector, pgEdge Vectorizer
  - Password: configurable via .env
  - DB: `openclaw_rag`

- **Elasticsearch**: Full-text search
  - Volume: `./.docker/elasticsearch/data`
  - Ports: 9200
  - Used for document/metadata search

- **Apache Tika**: Document format extraction
  - Image: apache/tika:2.9.2.1-full
  - Port: 9998
  - Converts Word, PDF, XLSX, etc. to plaintext
  - Fallback for unsupported formats

- **pgEdge Vectorizer Extension**: PostgreSQL extension for automatic text chunking and vector embedding
  - Installed as a PostgreSQL extension, not a separate service
  - Background workers built into PostgreSQL process itself
  - Triggers on INSERT/UPDATE to configured columns
  - Supports OpenAI, Voyage AI, and Ollama embedding providers
  - Automatic retry and rate limiting built-in

- **Adminer**: Database browser
  - Port: 9093 at `/adminer`
  - Quick DB inspection during development

### Local Development Setup

1. **Get certificates:**
   ```bash
   make get-certs-local-dev
   ```
   - Downloads `local-dev-host-certs` from GitHub
   - Sets up HTTPS on `local.devhost.name`

2. **Initialize environment:**
   ```bash
   make init
   ```
   - Installs dependencies (cms, app)
   - Gets environment variables
   - Downloads certs

3. **Run development environment:**
   ```bash
   make local-dev
   ```
   - Starts all services
   - PayloadCMS available at `https://local.devhost.name/admin`
   - Tika at `https://local.devhost.name/tika`
   - Elasticsearch at `https://local.devhost.name/elasticsearch`

## PayloadCMS Collections

Instead of raw SQL, define schema as TypeScript collections:

### Documents Collection

```typescript
// src/collections/Documents.ts
export const Documents: CollectionConfig = {
  slug: 'documents',
  admin: {
    useAsTitle: 'filename',
  },
  fields: [
    {
      name: 'filename',
      type: 'text',
      required: true,
    },
    {
      name: 'hash',
      type: 'text',
      unique: true,
      required: true,
    },
    {
      name: 'source',
      type: 'text',
    },
    {
      name: 'category',
      type: 'select',
      options: [
        { label: 'Projects', value: 'projects' },
        { label: 'Personal', value: 'personal' },
        { label: 'Reference', value: 'reference' },
      ],
    },
    {
      name: 'tags',
      type: 'array',
      fields: [
        {
          name: 'tag',
          type: 'text',
        },
      ],
    },
    {
      name: 'status',
      type: 'select',
      defaultValue: 'pending',
      options: [
        { label: 'Pending', value: 'pending' },
        { label: 'Indexing', value: 'indexing' },
        { label: 'Vectorizing', value: 'vectorizing' },
        { label: 'Complete', value: 'complete' },
        { label: 'Failed', value: 'failed' },
      ],
      admin: { readOnly: true },
    },
    {
      name: 'metadata',
      type: 'json',
    },
  ],
  hooks: {
    beforeCreate: [({ data }) => {
      // Hash validation
      if (!data.hash) {
        throw new Error('Hash required for deduplication');
      }
    }],
    afterCreate: [({ doc }) => {
      // Trigger vectorization
      // pgEdge worker picks up automatically
    }],
  },
};
```

### DocumentChunks Collection

```typescript
export const DocumentChunks: CollectionConfig = {
  slug: 'document-chunks',
  fields: [
    {
      name: 'document',
      type: 'relationship',
      relationTo: 'documents',
      required: true,
    },
    {
      name: 'chunkIndex',
      type: 'number',
      required: true,
    },
    {
      name: 'text',
      type: 'textarea',
      required: true,
    },
    {
      name: 'embedding',
      type: 'json', // Store pgvector embeddings
    },
    {
      name: 'metadata',
      type: 'json',
    },
  ],
  admin: {
    defaultColumns: ['document', 'chunkIndex', 'text'],
  },
};
```

### DocumentMetadata Collection

```typescript
export const DocumentMetadata: CollectionConfig = {
  slug: 'document-metadata',
  fields: [
    {
      name: 'document',
      type: 'relationship',
      relationTo: 'documents',
      required: true,
      unique: true,
    },
    {
      name: 'title',
      type: 'text',
    },
    {
      name: 'description',
      type: 'textarea',
    },
    {
      name: 'keywords',
      type: 'array',
      fields: [{ name: 'keyword', type: 'text' }],
    },
  ],
};
```

## Makefile Targets

Key commands for developer experience:

```bash
make init              # One-shot: get certs, env, install deps
make get-certs-local-dev
make local-dev        # Start all services (foreground)
make local-dev-daemon # Start all services (background)
make local-dev-stop   # Stop containers
make logs-cms         # View PayloadCMS logs
make logs-all         # View all logs
make cms-migrate      # Run database migrations
make cms-cli          # Access PayloadCMS container shell
make local-reset-db   # Wipe PostgreSQL and start fresh
make seed-documents   # Load sample documents
```

## pgEdge Vectorizer Extension Setup

Install and configure the pgEdge Vectorizer extension in PostgreSQL:

```sql
-- Create extensions
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgedge_vectorizer;

-- Configure vectorization on the documents table
SELECT pgedge_vectorizer.enable_vectorization(
  source_table := 'documents',
  source_column := 'text',
  chunk_strategy := 'token_based',
  chunk_size := 512,
  chunk_overlap := 50
);
```

The pgEdge Vectorizer extension automatically creates a chunks table (e.g., documents_text_chunks) with columns for chunk text and embeddings. Background workers process the queue asynchronously and call your configured embedding provider (OpenAI, Voyage, or Ollama).

## Document Ingestion Flow

1. **API/MCP call:** `POST /api/documents` with file
2. **Payload beforeCreate hook:**
   - Compute file hash
   - Check for duplicates in DB
   - If hash exists: return existing doc_id (skip processing)
   - If new: proceed
3. **Document created in DB**
4. **afterCreate hook:**
   - Call Apache Tika for format conversion (if needed)
   - Extract plaintext
   - Trigger pgEdge vectorizer (status='vectorizing')
   - Queue Elasticsearch indexing
5. **pgEdge worker:** Auto-chunks, embeds, stores in document_chunks
6. **Elasticsearch sync:** Document + metadata indexed for full-text search
7. **Status updated:** Complete or failed

## Environment Configuration

Create `.env` file (git-ignored):

```env
# Database
POSTGRES_USER=pglocaldev
POSTGRES_PASSWORD=secure_password_here
POSTGRES_DB=openclaw_rag

# Elasticsearch
ELASTICSEARCH_HOST=elasticsearch:9200

# Embeddings
OPENAI_API_KEY=sk-...
# OR local:
# OLLAMA_HOST=http://ollama:11434
# OLLAMA_MODEL=nomic-embed-text

# Payload CMS
PAYLOAD_SECRET=very_secret_key_here

# Vector settings
VECTOR_DIMENSION=1536
EMBEDDING_MODEL=text-embedding-3-small
CHUNK_SIZE=512
CHUNK_OVERLAP=50
```

## Directory Structure

```
.
├── .plan/                    # Phase documentation
├── docker-compose.yml        # Services definition
├── Makefile                  # Dev commands
├── .env.example              # Template env file
├── cms/                      # PayloadCMS application
│   ├── src/
│   │   ├── collections/
│   │   │   ├── Documents.ts
│   │   │   ├── DocumentChunks.ts
│   │   │   └── DocumentMetadata.ts
│   │   ├── endpoints/        # Custom REST endpoints
│   │   ├── hooks/            # Payload hooks
│   │   └── payload.config.ts
│   ├── package.json
│   └── Dockerfile
├── .docker/
│   └── postgres/data/        # PostgreSQL data volume
└── certs/                    # SSL certificates (from local-dev-host-certs)
```

## Next Steps

Phase 1 is complete when:
- [ ] `make init` runs without errors
- [ ] `make local-dev` starts all services
- [ ] PayloadCMS admin UI accessible at `/admin`
- [ ] Collections created with proper relationships
- [ ] PostgreSQL pgvector extension installed
- [ ] pgEdge Vectorizer configured and running
- [ ] Apache Tika accessible for format conversion
- [ ] Elasticsearch initialized and available
- [ ] Sample document ingestion works end-to-end
- [ ] Hash dedup prevents re-ingestion
- [ ] Document status updates through workflow
