// SERVER-ONLY. Local, free, open-source text embeddings for Ninkasi's RAG memory.
//
// Model: `Supabase/gte-small` (MIT, 384-dim) via Transformers.js — no API key, no
// cost, runs in-process. The pipeline is loaded once and cached for the lifetime of
// the server process (first call downloads ~30MB to the runtime cache).
//
// Swappable at zero code cost: set EMBED_API_URL (+ optional EMBED_API_KEY, EMBED_MODEL)
// to offload embedding to a hosted OpenAI-compatible endpoint if you ever outgrow the
// local model — same provider-agnostic pattern as the chat (AI_BASE_URL).
//
// Never import this from client code (it pulls in the ML runtime).

export const EMBED_DIM = 384;
const MODEL = "Supabase/gte-small";

type Extractor = (
  text: string,
  opts: { pooling: "mean"; normalize: boolean },
) => Promise<{ data: Float32Array | number[] }>;

let pipePromise: Promise<Extractor> | null = null;
async function getPipe(): Promise<Extractor> {
  if (!pipePromise) {
    pipePromise = (async () => {
      const { pipeline, env } = await import("@xenova/transformers");
      env.allowLocalModels = false; // fetch/cache from the hub, don't look for a local ./models dir
      const pipe = await pipeline("feature-extraction", MODEL);
      return pipe as unknown as Extractor;
    })();
  }
  return pipePromise;
}

/** Embed one text → a 384-dim unit vector (cosine-ready). Hosted endpoint if configured, else local. */
export async function embed(text: string): Promise<number[]> {
  const clean = text.replace(/\s+/g, " ").trim().slice(0, 2000);
  if (!clean) return new Array(EMBED_DIM).fill(0);

  if (process.env.EMBED_API_URL) return embedViaApi(clean, process.env.EMBED_API_URL);

  const pipe = await getPipe();
  const out = await pipe(clean, { pooling: "mean", normalize: true });
  return Array.from(out.data as Float32Array);
}

/** Optional hosted path — any OpenAI-compatible /embeddings endpoint. */
async function embedViaApi(text: string, url: string): Promise<number[]> {
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(process.env.EMBED_API_KEY ? { authorization: `Bearer ${process.env.EMBED_API_KEY}` } : {}),
    },
    body: JSON.stringify({ input: text, model: process.env.EMBED_MODEL || "text-embedding-3-small" }),
  });
  if (!res.ok) throw new Error(`embed api ${res.status}`);
  const json = (await res.json()) as { data: { embedding: number[] }[] };
  return json.data[0].embedding;
}
