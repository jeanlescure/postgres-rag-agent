# Phase 1: Foundation & Infrastructure

## Infrastructure Setup (Docker Compose)

Use Docker Compose for containerized development and deployment. Reference: `dianalu.design` docker-compose.yml structure.

### Services

- **nginx-proxy**: nginxproxy/nginx-proxy for reverse proxy + automatic SSL
  - Ports: 80, 443
  - Mounted certs directory: `./certs` (for local-dev-host-certs)
  - WebSocket support enabled
  - DEFAULT_HOST: local.devhost.name

- **PostgreSQL 17**: Core database
  - Volume: `./.docker/postgres/data`
  - Credentials: configurable via environment
  - Extensions needed: pgvector, pgEdge Vectorizer

- **Elasticsearch**: Full-text search engine
  - Volume: `./.docker/elasticsearch/data`
  - Exposed for queries from app and agent

- **pgEdge Vectorizer Worker**: Background service
  - Stateless worker pulling jobs from PostgreSQL queue
  - Embedding provider: configurable (OpenAI, Ollama, etc.)

- **Adminer**: Database browser (optional dev tool)
  - Port: 9093 at `/adminer`

- **OpenClaw Agent Container** (future): Run OpenClaw integration
  - MCP servers for ingestion, querying, management
  - Connected to PostgreSQL + Elasticsearch

### Local Development Setup

- Use `https://github.com/simplyhexagonal/local-dev-host-certs` for HTTPS on `local.devhost.name`
- Generate certs, place in `./certs` directory
- nginx-proxy automatically picks them up
- All services communicate internally via docker network

## Database Schema

### Core Tables

```sql
-- Documents table
CREATE TABLE documents (
  id UUID PRIMARY KEY,
  filename TEXT NOT NULL,
  source TEXT,
  hash VARCHAR(64) UNIQUE NOT NULL,
  uploaded_at TIMESTAMP DEFAULT NOW(),
  category TEXT,
  status TEXT DEFAULT 'pending', -- pending, indexing, vectorizing, complete, failed
  metadata JSONB,
  created_by TEXT,
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Document chunks (vectorized)
CREATE TABLE document_chunks (
  id UUID PRIMARY KEY,
  doc_id UUID REFERENCES documents(id) ON DELETE CASCADE,
  chunk_index INTEGER,
  text TEXT NOT NULL,
  embedding vector(1536), -- dimension depends on model
  metadata JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Document metadata for Elasticsearch sync
CREATE TABLE document_metadata (
  doc_id UUID PRIMARY KEY REFERENCES documents(id) ON DELETE CASCADE,
  title TEXT,
  description TEXT,
  tags TEXT[],
  category TEXT,
  keywords TEXT[],
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Vectorizer queue (managed by pgEdge)
-- pgEdge creates this automatically
```

## pgEdge Vectorizer Setup

### Configuration

- Declare vectorizer in PostgreSQL for `documents` table
- Load from: `metadata.content` column or external file references
- Parse with: pgEdge Document Loader (HTML, Markdown, RST, SGML)
- Chunk using: pgEdge chunking config
- Embed using: Configured provider (OpenAI, Ollama, etc.)
- Destination: `document_chunks` table

### Example SQL

```sql
SELECT ai.create_vectorizer(
  'documents'::regclass,
  if_not_exists => true,
  loading => ai.loading_column(column_name=>'text'),
  destination => ai.destination_table(target_table=>'document_chunks'),
  embedding => ai.embedding_openai(model=>'text-embedding-3-small', dimensions=>'1536')
)
```

## Elasticsearch Integration

### Index Mapping

```json
{
  "mappings": {
    "properties": {
      "doc_id": { "type": "keyword" },
      "filename": { "type": "text", "analyzer": "standard" },
      "title": { "type": "text", "analyzer": "standard" },
      "description": { "type": "text" },
      "content": { "type": "text", "analyzer": "standard" },
      "category": { "type": "keyword" },
      "tags": { "type": "keyword" },
      "uploaded_at": { "type": "date" },
      "source": { "type": "keyword" }
    }
  }
}
```

### Sync Strategy

- PostgreSQL trigger on document insert/update
- Post to Elasticsearch bulk API
- Handle failures gracefully

## MCP Server 1: Document Ingestion

### Endpoint: `ingest_document`

**Input:**
- `file_path`: Local or remote file path
- `category`: Document category (for filtering/organization)
- `tags`: Array of tags
- `format`: Optional explicit format hint

**Process:**

1. Hash file content (MD5/SHA256)
2. Check if hash exists in `documents` table
   - If yes: return existing doc_id, skip processing
   - If no: proceed
3. Load file using Apache Tika (if unsupported format) or pgEdge Document Loader
4. Insert into `documents` table with status='pending'
5. Create entry in `document_metadata`
6. Index in Elasticsearch
7. Set status='vectorizing' (pgEdge worker picks up automatically)
8. Return: `{doc_id, chunks_created, status}`

**Error Handling:**
- Duplicate hash detection (prevents bloat)
- Format conversion failures → fallback to Tika
- ES indexing failures → retry queue
- Vectorization failures → marked as 'failed', can retry

## Environment Configuration

Create `.env` file:

```env
POSTGRES_USER=pglocaldev
POSTGRES_PASSWORD=<secure-password>
POSTGRES_DB=openclaw_rag

ELASTICSEARCH_HOST=elasticsearch:9200

OPENAI_API_KEY=<your-key>
# OR for local embeddings:
# OLLAMA_HOST=http://ollama:11434
# OLLAMA_MODEL=nomic-embed-text

VECTOR_DIMENSION=1536
EMBEDDING_MODEL=text-embedding-3-small
```

## Next Steps

Phase 1 is complete when:
- [ ] Docker Compose setup runs all services
- [ ] PostgreSQL migrations applied
- [ ] pgEdge Vectorizer configured and worker running
- [ ] Elasticsearch initialized and schema mapped
- [ ] Document Ingestion MCP server callable and tested
- [ ] Hash dedup prevents duplicate ingestion
