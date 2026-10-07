-- Run this in your Supabase SQL Editor before setup.py
-- Uses a separate table from llm/rag-data-leak to avoid conflicts.
-- Safe to re-run: drops everything first and rebuilds from scratch.

-- Teardown
drop function if exists match_agent_documents(vector, int, jsonb);
drop table if exists agent_documents;

-- Setup
create extension if not exists vector;

create table agent_documents (
  id        uuid primary key default gen_random_uuid(),
  content   text        not null,
  metadata  jsonb       default '{}',
  embedding vector(384)
);

create or replace function match_agent_documents(
  query_embedding vector(384),
  match_count     int  default 5,
  filter          jsonb default '{}'
)
returns table (
  id         uuid,
  content    text,
  metadata   jsonb,
  similarity float
)
language plpgsql as $$
begin
  return query
  select
    d.id,
    d.content,
    d.metadata,
    1 - (d.embedding <=> query_embedding) as similarity
  from agent_documents d
  where d.metadata @> filter
  order by d.embedding <=> query_embedding
  limit match_count;
end;
$$;
