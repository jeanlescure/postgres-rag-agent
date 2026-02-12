# Phase 2: Knowledge Retrieval & Agentic Layer

## MCP Server 2: Knowledge Query

### Endpoint: `semantic_search`

**Input:**
- `query`: Natural language query string
- `limit`: Number of results (default: 5)
- `doc_filter`: Optional object with category, tags, date_range
- `threshold`: Similarity threshold (0-1, default: 0.5)

**Process:**

1. Generate embedding for query (same model as document embeddings)
2. Query `document_chunks` table with pgvector cosine similarity
3. Filter by `doc_filter` if provided (via document_metadata join)
4. Sort by similarity distance
5. Return top `limit` results with:
   - Chunk text
   - Similarity score
   - Document metadata (filename, title, category, date)
   - Chunk index (for context reconstruction)

**SQL Pattern:**

```sql
SELECT 
  dc.id,
  dc.text,
  dc.embedding <=> query_embedding AS distance,
  d.filename,
  dm.title,
  dm.category,
  d.uploaded_at
FROM document_chunks dc
JOIN documents d ON dc.doc_id = d.id
JOIN document_metadata dm ON d.id = dm.doc_id
WHERE dc.embedding <=> query_embedding < (1 - threshold)
AND (doc_filter IS NULL OR d.category = doc_filter.category)
ORDER BY distance
LIMIT limit
```

### Endpoint: `full_text_search`

**Input:**
- `query`: Full-text search query
- `filters`: Object with category, tags, date_range
- `limit`: Number of results (default: 10)

**Process:**

1. Query Elasticsearch with query string syntax
2. Apply filters (category, tags, date)
3. Return matching documents with:
   - Document metadata
   - Relevance score
   - Matched snippet (context around hits)
   - File metadata

**Use Cases:**
- User knows document title/filename
- Searching for specific keywords
- Broad discovery across corpus
- Date-range queries

### Endpoint: `hybrid_search`

**Input:**
- `query`: Query string
- `semantic_weight`: 0-1 (default: 0.5)
- `text_weight`: 0-1 (default: 0.5)
- `limit`: Combined results

**Process:**

1. Execute both `semantic_search` and `full_text_search` in parallel
2. Normalize scores (0-1 range)
3. Combine: `score = (semantic_score * semantic_weight) + (text_score * text_weight)`
4. Deduplicate results (same doc appears in both)
5. Sort by combined score
6. Return top `limit`

## MCP Server 3: Document Management

### Endpoint: `list_documents`

**Input:**
- `filters`: category, tags, date_range, status
- `sort_by`: filename, uploaded_at, category
- `limit`: Pagination limit
- `offset`: Pagination offset

**Response:**

```json
{
  "documents": [
    {
      "id": "uuid",
      "filename": "string",
      "category": "string",
      "tags": ["string"],
      "uploaded_at": "ISO-8601",
      "status": "complete",
      "chunks_count": 42,
      "total_tokens": 12500
    }
  ],
  "total": 150,
  "limit": 20,
  "offset": 0
}
```

### Endpoint: `document_status`

**Input:**
- `doc_id`: UUID

**Response:**

```json
{
  "id": "uuid",
  "filename": "string",
  "status": "complete",
  "indexed_at": "ISO-8601",
  "vectorized_at": "ISO-8601",
  "chunks_count": 42,
  "last_error": null,
  "embeddings": {
    "model": "text-embedding-3-small",
    "dimension": 1536,
    "provider": "openai"
  }
}
```

### Endpoint: `delete_document`

**Input:**
- `doc_id`: UUID
- `purge_index`: boolean (delete from ES too)

**Process:**

1. Delete from `document_chunks` (cascades via FK)
2. Delete from `document_metadata`
3. Delete from `documents`
4. If purge_index: DELETE from Elasticsearch by doc_id
5. Return: `{success: true, deleted_chunks: 42}`

### Endpoint: `document_details`

**Input:**
- `doc_id`: UUID

**Response:**

```json
{
  "id": "uuid",
  "filename": "string",
  "title": "string",
  "description": "string",
  "category": "string",
  "tags": ["string"],
  "source": "url or path",
  "uploaded_at": "ISO-8601",
  "hash": "sha256:...",
  "status": "complete",
  "metadata": {
    "page_count": 0,
    "word_count": 5000,
    "encoding": "utf-8"
  },
  "chunks": [
    {
      "index": 0,
      "text": "...",
      "tokens": 250
    }
  ]
}
```

## Agentic RAG Loop

### Agent Architecture

The OpenClaw agent has access to three MCP tools:

1. **semantic_search**: For meaning-based retrieval
2. **full_text_search**: For keyword/discovery-based retrieval
3. **hybrid_search**: When both approaches needed

### Agent Decision Logic

When receiving a query, the agent evaluates:

- **Is this a factual lookup?** → semantic_search (e.g., "How does pgai work?")
- **Is this a known-document search?** → full_text_search (e.g., "Find the contract with ABC Corp")
- **Is this exploratory or complex?** → hybrid_search (e.g., "What do we know about Barcelona relocation?")

### Context Injection Strategy

Retrieved chunks are injected into the agent's system prompt:

```
Context from knowledge base:
---
[Chunk 1]
Source: filename.md (category: topic)
Date: YYYY-MM-DD

[Chunk 2]
Source: another.md (category: topic)
---

Based on this context, answer the user's question.
```

**Context Limits:**
- Max 5-10 chunks per query (no context bloat)
- Total injected context: ~4000-6000 tokens
- Drop lowest-relevance chunks if over limit

### Conversation Memory

Store in PostgreSQL `conversation_history` table:

```sql
CREATE TABLE conversation_history (
  id UUID PRIMARY KEY,
  session_id TEXT,
  turn_number INTEGER,
  user_message TEXT,
  agent_response TEXT,
  retrieved_docs UUID[],
  search_method TEXT, -- 'semantic', 'full_text', 'hybrid'
  relevance_score FLOAT,
  created_at TIMESTAMP DEFAULT NOW()
);
```

**Use for:**
- Following up on previous questions
- Avoiding re-retrieving same docs
- Building context for multi-turn reasoning
- Learning what searches work well

## Integration Checklist

Phase 2 is complete when:
- [ ] All three MCP servers (Query, Management) callable from OpenClaw
- [ ] Semantic search returns relevant chunks with metadata
- [ ] Full-text search queries Elasticsearch correctly
- [ ] Hybrid search deduplicates and ranks properly
- [ ] Document list/status/delete operations work
- [ ] Agentic loop uses MCP tools and injects context
- [ ] Conversation history stored and retrievable
- [ ] Agent avoids context bloat (respects token limits)
