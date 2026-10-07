# RAG Data Exfiltration

**Threat**: Confidential documents stored in the same vector store as public knowledge get retrieved by semantically similar attacker queries and leaked through the LLM's response.

## Setup

### 1. Supabase — run SQL once

Open the [Supabase SQL Editor](https://supabase.com/dashboard) for your project and run `setup_supabase.sql`.

### 2. Environment

```
SUPABASE_URL=https://<ref>.supabase.co
SUPABASE_KEY=<service_role_key>
GROQ_API_KEY=<your_key>
```

### 3. Populate the vector store

```bash
cd llm/rag-data-leak
python setup.py
```

### 4. Run demos

```bash
# Baseline: normal chatbot behaviour
python rag_chain.py

# Attack: exfiltrate confidential documents
python attack.py
```

## What the attack shows

The same vector store holds:
- Public support docs (pricing, refund policy, support hours)
- Confidential docs (salaries, DB credentials, security incidents, discount matrix)

The retriever is blind to sensitivity — it ranks by cosine similarity alone. Queries like *"CEO compensation"* or *"database credentials"* pull confidential documents into the LLM context, which then summarises them in its response.