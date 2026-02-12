# Phase 3: Production Hardening & Optimization

## Error Handling & Resilience

### Embedding Provider Failures

**Scenario:** OpenAI API is down, rate-limited, or returning errors

**Implementation:**

- pgEdge Vectorizer worker has built-in retry logic
- Queue failed jobs with exponential backoff
- Retry limits: 5 attempts over 24 hours
- Dead-letter queue for persistent failures
- Admin interface to view and retry failed jobs

**Monitoring:**

```sql
-- Track failed vectorization jobs
SELECT 
  d.id, 
  d.filename, 
  d.status,
  COUNT(retry_attempt) as retry_count
FROM documents d
WHERE status = 'failed' 
GROUP BY d.id
ORDER BY retry_count DESC;
```

### Elasticsearch Outages

**Scenario:** Elasticsearch is unavailable or slow

**Fallback Behavior:**

- If ES down: semantic_search still works (has pgai vectors)
- Return degraded results: semantic + conversation context
- Queue ES indexing requests for retry when service recovers
- Alert on ES unavailability

```sql
-- Check ES sync status
SELECT 
  d.id, 
  d.filename, 
  CASE WHEN d.es_synced_at IS NULL THEN 'pending' ELSE 'synced' END as status
FROM documents d
WHERE es_synced_at IS NULL OR es_synced_at < NOW() - INTERVAL '1 hour';
```

### Database Connection Pooling

- Use PgBouncer or pgBackend for connection limits
- Configure in Docker Compose
- Connection limits: 100 max, 20 min

```yaml
# docker-compose.yml addition
pgbouncer:
  image: pgbouncer/pgbouncer
  environment:
    DATABASES_HOST: postgres
    DATABASES_PORT: 5432
    DATABASES_USER: pglocaldev
    DATABASES_DBNAME: openclaw_rag
    PGBOUNCER_POOL_MODE: transaction
    PGBOUNCER_MAX_CLIENT_CONN: 100
    PGBOUNCER_DEFAULT_POOL_SIZE: 20
  ports:
    - 6432:6432
```

### Rate Limiting

- Embedding API calls: queue per-second limits
- Search queries: per-user rate limits
- Document ingestion: per-minute limits

```sql
CREATE TABLE rate_limits (
  id UUID PRIMARY KEY,
  resource_type TEXT, -- 'embedding', 'search', 'ingest'
  user_id TEXT,
  count_current INTEGER DEFAULT 0,
  limit_per_minute INTEGER,
  window_reset_at TIMESTAMP,
  updated_at TIMESTAMP DEFAULT NOW()
);
```

## Performance Optimization

### Vector Search Indexing

**IVFFlat Index for pgvector (Phase 3a):**

For datasets >100k chunks, create IVF index:

```sql
CREATE INDEX ON document_chunks 
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);
```

**pgvectorscale (Phase 3b):**

For >1M vectors, use Timescale's pgvectorscale:

```sql
SELECT * FROM pgvectorscale.hnswdw_index_create(
  'document_chunks'::regclass, 
  'embedding'::text
);
```

### Elasticsearch Optimization

- Index shards: 3 (for parallelism)
- Replicas: 1 (for HA)
- Refresh interval: 30s (balance indexing speed vs freshness)
- Query caching: top 100 queries cached

```json
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "refresh_interval": "30s",
    "index.queries.cache.enabled": true
  }
}
```

### Caching Layer

Add Redis for query results:

```yaml
# docker-compose addition
redis:
  image: redis:7-alpine
  ports:
    - 6379:6379
  volumes:
    - ./.docker/redis/data:/data
```

**Cache Strategy:**

- Cache semantic_search results for 1 hour (query + filter hash)
- Cache full_text_search results for 2 hours
- Cache document metadata for 24 hours
- Invalidate on document update

```python
# Pseudo-code
cache_key = f"semantic_search:{query_hash}:{filter_hash}"
cached = redis.get(cache_key)
if cached:
  return cached
else:
  results = pg_semantic_search(query, filters)
  redis.setex(cache_key, 3600, results)
  return results
```

### Batch Processing

**Document Ingestion Batching:**

Process multiple documents in parallel:

```python
# Ingest 10 documents concurrently
with ThreadPoolExecutor(max_workers=10) as executor:
  futures = [executor.submit(ingest_document, doc) for doc in docs]
  results = [f.result() for f in futures]
```

**Vectorization Batching:**

pgEdge vectorizer worker processes batches of chunks:

- Batch size: 100 chunks
- Parallel requests to embedding API: 5
- Reduces API calls and costs

## Monitoring & Observability

### Metrics to Track

```sql
-- Query performance
CREATE TABLE query_metrics (
  id UUID PRIMARY KEY,
  query_type TEXT, -- 'semantic', 'full_text', 'hybrid'
  query_text TEXT,
  execution_time_ms INTEGER,
  result_count INTEGER,
  cache_hit BOOLEAN,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Document ingestion performance
CREATE TABLE ingestion_metrics (
  id UUID PRIMARY KEY,
  doc_id UUID,
  file_size_bytes INTEGER,
  chunk_count INTEGER,
  embedding_time_ms INTEGER,
  es_indexing_time_ms INTEGER,
  status TEXT, -- 'success', 'failed'
  created_at TIMESTAMP DEFAULT NOW()
);
```

### Health Checks

Implement health endpoint at `/api/health`:

```json
{
  "status": "healthy",
  "components": {
    "postgres": "healthy",
    "elasticsearch": "healthy",
    "vectorizer_worker": "healthy",
    "redis": "healthy"
  },
  "uptime_seconds": 86400,
  "documents_total": 1200,
  "chunks_total": 45000,
  "last_sync": "2026-02-11T20:30:00Z"
}
```

### Logging

Structured logging to PostgreSQL:

```sql
CREATE TABLE logs (
  id UUID PRIMARY KEY,
  level TEXT, -- 'info', 'warn', 'error'
  component TEXT, -- 'vectorizer', 'search', 'ingest'
  message TEXT,
  metadata JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);
```

## Scaling Strategy

### Vertical (Phase 3a)
- Increase Docker service resources (CPU, memory)
- Larger PostgreSQL shared_buffers
- More Elasticsearch shards

### Horizontal (Phase 3b)
- Multiple pgEdge vectorizer workers
- PostgreSQL read replicas (for search queries)
- Elasticsearch cluster mode
- Load balancer for nginx-proxy

```yaml
# docker-compose horizontal setup
vectorizer_worker_1:
  # ... same config

vectorizer_worker_2:
  # ... same config

vectorizer_worker_3:
  # ... same config
```

## Security Hardening

### Input Validation

- Sanitize query strings (prevent injection)
- Validate file types (prevent binary uploads)
- Rate limit by source IP

### API Authentication

Add JWT tokens to MCP server:

```python
# MCP servers check Authorization header
@check_auth
def semantic_search(query, limit):
  # ...
```

### Data Privacy

- Sensitive document handling (PII detection)
- Optional document encryption at rest
- Audit logs for all data access

```sql
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY,
  user_id TEXT,
  action TEXT, -- 'search', 'ingest', 'delete'
  doc_id UUID,
  created_at TIMESTAMP DEFAULT NOW()
);
```

## Next Steps

Phase 3 is complete when:
- [ ] Error handling covers all failure scenarios
- [ ] Vectorizer retries and monitoring in place
- [ ] Vector search indexes created and performing
- [ ] Elasticsearch optimized and sharded
- [ ] Redis caching deployed and working
- [ ] Health checks passing
- [ ] Metrics collected and visible
- [ ] Load tests show acceptable performance
- [ ] Horizontal scaling ready for deployment
