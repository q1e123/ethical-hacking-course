-- Run this in your Supabase SQL Editor before setup.py
-- https://supabase.com/dashboard/project/<your-ref>/sql
-- Safe to re-run: drops everything first and rebuilds from scratch.

-- 1. Teardown
drop function if exists match_documents(vector, int, jsonb);
drop table if exists documents;

-- 2. Enable pgvector
create extension if not exists vector;

-- 3. Documents table (384-dim for all-MiniLM-L6-v2)
create table documents (
  id        uuid primary key default gen_random_uuid(),
  content   text        not null,
  metadata  jsonb       default '{}',
  embedding vector(384)
);

-- 4. Similarity search function (used by LangChain SupabaseVectorStore)
create or replace function match_documents(
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
  from documents d
  where d.metadata @> filter
  order by d.embedding <=> query_embedding
  limit match_count;
end;
$$;
