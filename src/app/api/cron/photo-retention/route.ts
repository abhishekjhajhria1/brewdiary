// Daily: remove diary photos older than a year (057). Run by Vercel Cron, which
// sends `Authorization: Bearer $CRON_SECRET`; anything else is refused. The entry
// itself stays — only its pictures go.
import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { PHOTO_DAYS, removePhotoFiles } from "@/lib/photoRetention";

export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "Not allowed." }, { status: 401 });
  }
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY; // server-only, never NEXT_PUBLIC_
  if (!url || !serviceKey) {
    return NextResponse.json({ error: "Photo retention isn't configured on this server." }, { status: 500 });
  }
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  let removed = 0;
  for (let round = 0; round < 10; round++) {
    const { data, error } = await admin.rpc("photo_files_older_than", { days: PHOTO_DAYS, max_rows: 500 });
    if (error) return NextResponse.json({ error: error.message, removed }, { status: 500 });
    const names = ((data ?? []) as { name: string }[]).map((r) => r.name).filter(Boolean);
    if (!names.length) break;
    const gone = await removePhotoFiles(admin, names);
    removed += gone;
    if (gone < names.length) break; // storage refused some; tomorrow's run picks them up
  }
  return NextResponse.json({ ok: true, removed });
}
