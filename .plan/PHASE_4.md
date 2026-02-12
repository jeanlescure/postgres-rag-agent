# Phase 4: Agentic Enhancements & Advanced Features

## Multi-turn Reasoning

### Conversation Context Management

**Scenario:** User asks follow-up questions; agent needs to remember previous context

**Implementation:**

```sql
CREATE TABLE conversations (
  id UUID PRIMARY KEY,
  user_id TEXT,
  title TEXT,
  started_at TIMESTAMP DEFAULT NOW(),
  last_activity_at TIMESTAMP DEFAULT NOW(),
  context_summary TEXT, -- AI-generated summary for context injection
  status TEXT DEFAULT 'active' -- 'active', 'archived'
);

CREATE TABLE conversation_turns (
  id UUID PRIMARY KEY,
  conversation_id UUID REFERENCES conversations(id),
  turn_number INTEGER,
  user_message TEXT,
  agent_response TEXT,
  retrieved_docs UUID[],
  search_method TEXT,
  relevance_scores FLOAT[],
  context_injected JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);
```

### Context Injection for Multi-turn

On each turn:

1. Retrieve previous turns (last 5)
2. Extract key entities and facts
3. Inject as "conversation context" into agent prompt

```
Conversation Context:
---
Previous turns summary:
- User asked about Barcelona relocation (turns 1-3)
- Key decision: moving to Barcelona in 1-2 years
- Constraints: visa requirements, family considerations
---

Current question: ...
```

### Fact Extraction & Caching

After each turn, extract facts from response:

```sql
CREATE TABLE extracted_facts (
  id UUID PRIMARY KEY,
  conversation_id UUID,
  turn_id UUID,
  subject TEXT, -- 'Barcelona', 'visa', etc.
  fact TEXT,
  confidence FLOAT, -- 0-1, how certain is this fact
  created_at TIMESTAMP DEFAULT NOW()
);
```

This prevents re-asking the same questions in future turns.

### Follow-up Question Detection

Agent can detect when user's question implies context from previous turns:

```python
# Pseudo-code
if is_follow_up_question(user_input, conversation_context):
  # Prepend conversation context to search
  search_results = semantic_search(
    query=user_input,
    context_filter=extract_entities(conversation_context)
  )
```

## Graph RAG (Optional but Powerful)

### Entity Extraction

Extract entities from documents at ingestion time:

```sql
CREATE TABLE entities (
  id UUID PRIMARY KEY,
  doc_id UUID REFERENCES documents(id),
  name TEXT,
  type TEXT, -- 'person', 'organization', 'location', 'concept'
  metadata JSONB,
  embedding vector(1536), -- semantic embedding of entity
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE relationships (
  id UUID PRIMARY KEY,
  source_entity_id UUID REFERENCES entities(id),
  target_entity_id UUID REFERENCES entities(id),
  relation_type TEXT, -- 'located_in', 'founded_by', 'related_to'
  strength FLOAT, -- 0-1 confidence
  evidence_chunks UUID[], -- document chunks supporting this
  created_at TIMESTAMP DEFAULT NOW()
);
```

### Entity Extraction Pipeline

On document ingestion:

1. Split document into sentences
2. Run NER (Named Entity Recognition) model
3. Extract entity types: PERSON, ORG, LOCATION, DATE, CONCEPT
4. Embed each entity
5. Find relationships between entities (via LLM analysis of context)
6. Store in entities + relationships tables

**Tools:** spaCy NER + custom LLM prompt for relationship extraction

```python
# Pseudo-code
for chunk in document_chunks:
  entities = nlp(chunk.text).ents
  for entity in entities:
    store_entity(entity)
  
  # Find relationships
  relationships = llm.extract_relationships(chunk.text, entities)
  for rel in relationships:
    store_relationship(rel)
```

### Graph Traversal for Context Expansion

When user queries, expand semantic search results with related entities:

```python
# Find most relevant chunks
chunks = semantic_search(query)

# For each chunk, find related entities
for chunk in chunks:
  entities = get_entities_from_chunk(chunk)
  for entity in entities:
    # Find connected entities
    related = traverse_relationships(entity, depth=2)
    # Retrieve chunks mentioning related entities
    extended_chunks = chunks_mentioning_entities(related)

# Return combined results
return ranked_chunks(chunks + extended_chunks)
```

### Example: Barcelona Relocation Query

```
User: "Tell me about the Barcelona plan"

Entities found:
- Barcelona (LOCATION)
- Jean (PERSON)
- Diana (PERSON)
- Clever Synapse (ORGANIZATION)
- Digital nomad visa (CONCEPT)

Relationships:
- Jean -> moving_to -> Barcelona
- Diana -> moving_with -> Jean
- Clever Synapse -> relocation_of -> Barcelona
- Barcelona <- supports_visa <- Digital nomad visa

Graph traversal depth=2:
- Barcelona -> has_infrastructure -> maker spaces
- Barcelona -> has_cost_of_living -> [data]
- Barcelona -> EU_location -> [visa implications]

Results: Original chunks + related context about Barcelona ecosystem
```

## Document Organization & Tagging

### Intelligent Categorization

On ingestion, auto-categorize documents:

```python
# Ask LLM to categorize
category = llm.categorize(
  document_text,
  known_categories=['projects', 'personal', 'business', 'reference', 'archive']
)

# Auto-tag with entities/topics
tags = llm.extract_tags(
  document_text,
  context=previous_documents
)

# Store tags
update_document_metadata(doc_id, category=category, tags=tags)
```

### Smart Folder Structure

Allow hierarchical organization in metadata:

```sql
CREATE TABLE document_collections (
  id UUID PRIMARY KEY,
  name TEXT,
  description TEXT,
  parent_id UUID REFERENCES document_collections(id),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE document_collection_members (
  id UUID PRIMARY KEY,
  collection_id UUID REFERENCES document_collections(id),
  doc_id UUID REFERENCES documents(id),
  order_index INTEGER
);
```

**Example hierarchy:**
- Clever Synapse
  - Barcelona Relocation
    - Visa Research
    - Maker Spaces
  - Team Docs
    - Meeting Notes
    - Contracts
- Personal
  - Health
  - Finances

## Relevance & Feedback Loop

### User Feedback on Results

Track which results were useful:

```sql
CREATE TABLE search_feedback (
  id UUID PRIMARY KEY,
  search_id UUID,
  result_doc_id UUID,
  turn_id UUID,
  helpful BOOLEAN, -- true = helpful, false = not helpful
  relevance_score_before FLOAT,
  relevance_score_after FLOAT, -- after feedback
  user_comment TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);
```

### Relevance Model Improvement

Periodically retrain relevance scoring:

1. Collect feedback data (last month)
2. Analyze what made results "helpful"
3. Adjust semantic_search threshold or weighting
4. Re-rank historical results
5. Measure improvement

## Knowledge Export & Reporting

### Document Summary Generation

Periodic summaries for user review:

```sql
-- Generate summary for each document
SELECT 
  d.filename,
  llm_summarize(dc.text) as summary,
  COUNT(DISTINCT dc.id) as chunks,
  d.uploaded_at
FROM documents d
JOIN document_chunks dc ON d.id = dc.doc_id
GROUP BY d.id
```

### Category Reports

Monthly/quarterly reports:

```
Knowledge Base Report - Q1 2026

Documents by Category:
- Projects: 42 documents, 15,000 chunks
- Personal: 28 documents, 8,500 chunks
- Reference: 95 documents, 35,000 chunks

Top Entities Mentioned:
1. Barcelona: 127 mentions
2. Clever Synapse: 89 mentions
3. Visa/Immigration: 54 mentions

Search Activity:
- Most frequent queries: "Barcelona", "relocation", "visa"
- Average query results: 3.2 relevant chunks
- User satisfaction: 82% (from feedback)
```

### Export Capabilities

- Export by category/tag
- Export conversation transcripts
- Export as markdown for reading
- Export as JSON for analysis

## Clever Synapse Integration

### Branded Knowledge Management

Link to Clever Synapse business operations:

- Client projects → automatically organized in knowledge base
- Proposals → indexed for quick retrieval
- Past work → searchable portfolio
- Lessons learned → extracted and surfaced

### Brand Consistency

Ensure answers align with Clever Synapse brand/values:

```python
# Inject brand guidelines into system prompt
system_prompt = f"""
You are Celeste, an assistant for Clever Synapse.

Brand Values:
- Innovation through artisanal excellence
- Long-term client relationships
- Transparency and authenticity
- Sustainability and careful growth

When answering questions, reflect these values.
"""
```

## Advanced Query Types

### Question Answering

```
User: "How long do proposals take for ultra-high-net-worth clients?"
Agent: Searches for proposal timelines + client feedback + case studies
       Returns synthesized answer with sources
```

### Comparison Queries

```
User: "How does Barcelona compare to Costa Rica for relocation?"
Agent: Graph traversal finds both locations, pulls all related chunks
       Synthesizes comparison across multiple documents
```

### Predictive Queries

```
User: "What challenges should we expect when relocating to Barcelona?"
Agent: Finds similar relocation experiences in knowledge base
       Synthesizes potential challenges with mitigation strategies
```

## Integration Checklist

Phase 4 is complete when:
- [ ] Multi-turn conversations preserve context across turns
- [ ] Fact extraction prevents re-asking same questions
- [ ] Entities extracted and stored on document ingestion
- [ ] Relationship graph built and traversable
- [ ] Graph traversal expands search results meaningfully
- [ ] Documents auto-categorized and tagged
- [ ] Collection hierarchies support organization
- [ ] User feedback collected and stored
- [ ] Relevance model improves over time
- [ ] Export/reporting features working
- [ ] Clever Synapse branding integrated
- [ ] Advanced query types (comparison, prediction) working
