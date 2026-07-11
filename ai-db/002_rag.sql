-- ============================================================================
-- NINKASI DATA PLANE — 002: RAG memory (pgvector).
-- Runs on top of ai-db/schema.sql, in the SEPARATE AI Supabase project.
--
-- Gives Ninkasi a growing MEMORY: each consented exchange is stored with an
-- embedding (a 384-dim vector from the open-source `gte-small` model, computed
-- server-side — see src/lib/embed.ts). At chat time we embed the new question and
-- retrieve the most similar past exchanges to ground the reply. No retraining —
-- it improves automatically as the corpus grows.
--
-- Apply in the AI project's SQL editor (or: node scripts/db.mjs ai-db/002_rag.sql AI_SUPABASE_DB_URL).
-- Idempotent-ish.
-- ============================================================================

-- pgvector (Supabase ships it; this just enables it for this project)
create extension if not exists vector;

-- the embedding of each exchange's PROMPT (what future questions match against).
-- 384 dims = gte-small. If you ever switch embedding models, the dimension must match.
alter table public.exchanges add column if not exists embedding vector(384);

-- approximate-nearest-neighbour index for fast cosine search as the table grows.
-- HNSW builds incrementally (good for a table that starts small and accumulates).
create index if not exists exchanges_embedding_idx
  on public.exchanges using hnsw (embedding vector_cosine_ops);

-- Top-k past exchanges most similar to a query embedding. Returns the prompt+reply
-- (what we inject into the grounding context) and a 0..1 cosine similarity.
-- Called ONLY from our server via the service key (this DB is deny-all otherwise).
create or replace function public.match_exchanges(
  query_embedding vector(384),
  match_count int default 5,
  min_similarity float default 0.0
)
returns table (id uuid, prompt text, reply text, similarity float)
language sql stable as $$
  select e.id, e.prompt, e.reply,
         1 - (e.embedding <=> query_embedding) as similarity
  from public.exchanges e
  where e.embedding is not null
    and 1 - (e.embedding <=> query_embedding) >= min_similarity
  order by e.embedding <=> query_embedding
  limit greatest(match_count, 1);
$$;

-- keep it sealed: only the server's service_role may run it
revoke all on function public.match_exchanges(vector, int, float) from public, anon, authenticated;
grant execute on function public.match_exchanges(vector, int, float) to service_role;
