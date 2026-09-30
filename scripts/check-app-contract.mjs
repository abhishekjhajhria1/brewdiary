// The apps and the database, checked against each other. READ-ONLY.
//
// Every screen reaches the database through calls like
//
//   c.from('venue_staff').select('role, venue:venues(*)').eq('user_id', me)
//   c.rpc('claim_staff_enrolment', params: {'eid': id, 'code': code})
//
// and nothing checks one until somebody taps the button. A renamed column, an argument a
// migration changed, a table whose write policy was removed on purpose: each compiles,
// passes every unit test, and fails in a person's hand. This reads every such call in the
// venue app (mobile-bar), the users app (test_m_app) and the website (src), and asks the
// real schema whether it can work:
//
//   • the table or view exists, and every column the call names (selected, filtered,
//     ordered, inserted, updated, upserted on) is on it. Embedded tables are checked too,
//     with the link between the two and the !hint PostgREST needs when there are two links;
//   • a table with row-level security has a policy for what the call does. A write with no
//     policy fails every time; an update or delete with no read policy matches no row and
//     silently changes nothing;
//   • the function exists and takes exactly those argument names: none unknown, no required
//     one missing, not two versions that both fit. And a signed-in or signed-out caller may
//     run it.
//
// It proves the shape of each call, not the business rules behind it; those are what
// db:verify plays through. Run it against a database with every migration applied:
//
//   SUPABASE_DB_URL=… node scripts/check-app-contract.mjs            (npm run db:local does)
//   … --list      also print every call that passed
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { Client } from "pg";

// .env.local when run by hand; real env vars in CI, where no such file exists.
try {
  for (const line of readFileSync(".env.local", "utf8").split("\n")) {
    const t = line.trim();
    if (!t || t.startsWith("#")) continue;
    const i = t.indexOf("=");
    if (i > 0 && !(t.slice(0, i).trim() in process.env)) process.env[t.slice(0, i).trim()] = t.slice(i + 1).trim();
  }
} catch {
  /* no .env.local — rely on the real environment */
}
if (!process.env.SUPABASE_DB_URL) {
  console.error("SUPABASE_DB_URL is not set — put it in .env.local, or pass it as an env var in CI.");
  process.exit(1);
}
const LIST = process.argv.includes("--list");

const APPS = [
  { name: "venue app (mobile-bar)", dir: "mobile-bar/lib", exts: [".dart"] },
  { name: "users app (test_m_app)", dir: "test_m_app/lib", exts: [".dart"] },
  { name: "website (src)", dir: "src", exts: [".ts", ".tsx"] },
];
// Talks to the separate AI database (ai-db/), which has its own verify (scripts/ninkasi).
const SKIP_FILES = new Set(["src/lib/aidb.ts"]);

// ── reading source ──────────────────────────────────────────────────────────
// One pass over a file gives two copies of the same length: `code` with the comments
// blanked out, and `mask` with string contents blanked too, so brackets and commas can be
// matched on `mask` without a quote inside a string ever counting.

/** A string literal starting at i: { cs, ce, end, raw, q } (content start/end), or null. */
function stringAt(src, i, lang) {
  let raw = false;
  let j = i;
  if (lang === "dart" && src[i] === "r" && (src[i + 1] === "'" || src[i + 1] === '"') && !/[\w$]/.test(src[i - 1] ?? "")) {
    raw = true;
    j = i + 1;
  }
  const q = src[j];
  if (q !== "'" && q !== '"' && !(lang === "ts" && q === "`")) return null;
  const triple = lang === "dart" && src.startsWith(q.repeat(3), j);
  const delim = triple ? q.repeat(3) : q;
  let k = j + delim.length;
  const cs = k;
  while (k < src.length) {
    if (!raw && src[k] === "\\") {
      k += 2;
      continue;
    }
    if (src.startsWith(delim, k)) return { cs, ce: k, end: k + delim.length, raw, q: delim };
    if (!raw && src[k] === "$" && src[k + 1] === "{" && (lang === "dart" || q === "`")) {
      k = skipInterpolation(src, k + 2, lang);
      continue;
    }
    if (!triple && q !== "`" && src[k] === "\n") break; // unterminated: stop at the line
    k++;
  }
  return { cs, ce: k, end: k, raw, q: delim };
}
function skipInterpolation(src, k, lang) {
  let depth = 1;
  while (k < src.length && depth > 0) {
    const s = stringAt(src, k, lang);
    if (s) {
      k = s.end;
      continue;
    }
    if (src[k] === "{") depth++;
    else if (src[k] === "}") depth--;
    k++;
  }
  return k;
}

function lex(src, lang) {
  const code = src.split("");
  const mask = src.split("");
  const blank = (arr, a, b, ch = " ") => {
    for (let k = a; k < b; k++) if (arr[k] !== "\n") arr[k] = ch;
  };
  let i = 0;
  let lastSig = ""; // the last significant character, to tell a TS regex from a division
  while (i < src.length) {
    const c = src[i];
    const d = src[i + 1];
    if (c === "/" && d === "/") {
      let j = src.indexOf("\n", i);
      if (j < 0) j = src.length;
      blank(code, i, j);
      blank(mask, i, j);
      i = j;
      continue;
    }
    if (c === "/" && d === "*") {
      let j = src.indexOf("*/", i + 2);
      j = j < 0 ? src.length : j + 2;
      blank(code, i, j);
      blank(mask, i, j);
      i = j;
      continue;
    }
    if (lang === "ts" && c === "/" && (lastSig === "" || "(,=:[!&|?{};+-*%<>~^".includes(lastSig))) {
      let j = i + 1;
      let cls = false;
      while (j < src.length && src[j] !== "\n") {
        if (src[j] === "\\") j += 2;
        else if (src[j] === "[") (cls = true), j++;
        else if (src[j] === "]") (cls = false), j++;
        else if (src[j] === "/" && !cls) break;
        else j++;
      }
      blank(mask, i + 1, j, "\u0001");
      i = j + 1;
      while (/[a-z]/.test(src[i] ?? "")) i++;
      lastSig = "x";
      continue;
    }
    const s = stringAt(src, i, lang);
    if (s) {
      blank(mask, s.cs, s.ce, "\u0001");
      i = s.end;
      lastSig = "x";
      continue;
    }
    if (!/\s/.test(c)) lastSig = c;
    i++;
  }
  return { code: code.join(""), mask: protectGenerics(mask.join("")) };
}

// `Map<String, dynamic>` holds a comma that isn't an argument separator: hide commas inside
// anything that reads as a type argument list.
function protectGenerics(mask) {
  const out = mask.split("");
  for (let i = 0; i < out.length; i++) {
    if (out[i] !== "<" || !/[\w\s>]/.test(out[i - 1] ?? " ") || !/[\s\w]/.test(out[i + 1] ?? "")) continue;
    let depth = 0;
    let j = i;
    let good = false;
    for (; j < out.length; j++) {
      const ch = out[j];
      if (ch === "<") depth++;
      else if (ch === ">") {
        depth--;
        if (depth === 0) {
          good = true;
          break;
        }
      } else if (!/[\w\s,?.[\]|]/.test(ch)) break;
    }
    if (good && out.slice(i, j).includes(",")) for (let k = i; k < j; k++) if (out[k] === ",") out[k] = "\u0002";
  }
  return out.join("");
}

const OPEN = "([{";
const CLOSE = ")]}";
function matchBracket(mask, i) {
  let depth = 0;
  for (let k = i; k < mask.length; k++) {
    if (OPEN.includes(mask[k])) depth++;
    else if (CLOSE.includes(mask[k]) && --depth === 0) return k;
  }
  return mask.length - 1;
}
/** Top-level comma-separated pieces of mask[a, b) as [start, end) ranges, trimmed. */
function splitTop(mask, a, b) {
  const parts = [];
  let depth = 0;
  let s = a;
  for (let k = a; k < b; k++) {
    const ch = mask[k];
    if (OPEN.includes(ch)) depth++;
    else if (CLOSE.includes(ch)) depth--;
    else if (ch === "," && depth === 0) {
      parts.push([s, k]);
      s = k + 1;
    }
  }
  parts.push([s, b]);
  return parts
    .map(([x, y]) => {
      while (x < y && /\s/.test(mask[x])) x++;
      while (y > x && /\s/.test(mask[y - 1])) y--;
      return [x, y];
    })
    .filter(([x, y]) => y > x);
}

// ── values: string literals, map / object literals, and names that lead to one ──────
class Source {
  constructor(path, text) {
    this.path = path;
    this.lang = path.endsWith(".dart") ? "dart" : "ts";
    const { code, mask } = lex(text, this.lang);
    this.code = code;
    this.mask = mask;
    this.lineStarts = [0];
    for (let k = 0; k < text.length; k++) if (text[k] === "\n") this.lineStarts.push(k + 1);
  }
  line(pos) {
    let lo = 0;
    let hi = this.lineStarts.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (this.lineStarts[mid] <= pos) lo = mid;
      else hi = mid - 1;
    }
    return lo + 1;
  }
  skipWs(k) {
    while (k < this.mask.length && /\s/.test(this.mask[k])) k++;
    return k;
  }

  /** The text of [a, b) as a string, if it is only string literals (adjacent or joined by
   *  +) with no interpolation; otherwise undefined. */
  stringValue(a, b) {
    let k = this.skipWs(a);
    let out = "";
    let any = false;
    while (k < b) {
      const s = stringAt(this.code, k, this.lang);
      if (!s) return undefined;
      const body = this.code.slice(s.cs, s.ce);
      if (!s.raw && (this.lang === "dart" ? /\$[{\w]/.test(body) : s.q === "`" && body.includes("${"))) return undefined;
      out += s.raw ? body : body.replace(/\\(.)/g, (_, ch) => (ch === "n" ? "\n" : ch));
      any = true;
      k = this.skipWs(s.end);
      if (this.code[k] === "+") k = this.skipWs(k + 1);
    }
    return any ? out : undefined;
  }

  /** Resolve an expression to a string: a literal, or a name declared as one. */
  resolveString(a, b, at, seen = new Set()) {
    const direct = this.stringValue(a, b);
    if (direct !== undefined) return direct;
    const name = this.code.slice(a, b).trim();
    if (!/^[A-Za-z_$][\w$]*$/.test(name) || seen.has(name)) return undefined;
    seen.add(name);
    const decl = this.findDecl(name, at);
    if (!decl) return undefined;
    const end = this.exprEnd(decl);
    return this.resolveString(decl, end, decl, seen);
  }

  /** The start of the value in the nearest `NAME = …` declaration before `at` (or anywhere
   *  in the file, for a class constant declared further down). */
  findDecl(name, at) {
    const re = new RegExp(
      String.raw`(?:\b(?:final|var|const|let|static)\s+(?:[\w<>?,\u0002\s[\]]+\s+)?)${name.replace(/\$/g, "\\$")}\s*(?::\s*[\w<>?,\u0002\s[\]|.]+)?=(?![=>])`,
      "g",
    );
    let before = null;
    let any = null;
    let m;
    while ((m = re.exec(this.mask))) {
      const pos = m.index + m[0].length;
      if (m.index < at) before = pos;
      else if (any === null) any = pos;
    }
    const p = before ?? any;
    return p === null ? null : this.skipWs(p);
  }
  /** Where an expression starting at k ends: the first top-level `;` or `,` or closer. */
  exprEnd(k) {
    let depth = 0;
    for (let j = k; j < this.mask.length; j++) {
      const ch = this.mask[j];
      if (OPEN.includes(ch)) depth++;
      else if (CLOSE.includes(ch)) {
        if (depth === 0) return j;
        depth--;
      } else if ((ch === ";" || ch === ",") && depth === 0) return j;
    }
    return this.mask.length;
  }

  /** The keys a map / object literal (or a list of them) will send. Returns
   *  { keys: Set, complete: bool } — complete is false when a spread or a computed key
   *  hides some of them; null when the value can't be read at all. */
  keysOf(a, b, at, depth = 0) {
    if (depth > 4) return null;
    let k = this.skipWs(a);
    // `const <String, dynamic>{…}` / `<String, Object?>{…}` / TS `({…})` / `{…} as X`
    if (this.code.startsWith("const ", k)) k = this.skipWs(k + 6);
    if (this.mask[k] === "<") {
      let d = 0;
      for (; k < b; k++) {
        if (this.mask[k] === "<") d++;
        else if (this.mask[k] === ">" && --d === 0) break;
      }
      k = this.skipWs(k + 1);
    }
    if (this.mask[k] === "(" && this.lang === "ts") {
      const close = matchBracket(this.mask, k);
      const inner = this.keysOf(k + 1, close, at, depth + 1);
      if (inner) return inner;
    }
    if (this.mask[k] === "{") return this.mapKeys(k, matchBracket(this.mask, k), at, depth);
    if (this.mask[k] === "[") {
      const close = matchBracket(this.mask, k);
      const out = { keys: new Set(), complete: true };
      let found = false;
      for (const [x, y] of splitTop(this.mask, k + 1, close)) {
        const r = this.keysOf(x, y, at, depth + 1);
        if (!r) {
          out.complete = false;
          continue;
        }
        found = true;
        r.keys.forEach((key) => out.keys.add(key));
        out.complete &&= r.complete;
      }
      return found ? out : null;
    }
    const text = this.code.slice(k, b).trim();
    // a name declared as a literal
    if (/^[A-Za-z_$][\w$]*$/.test(text)) {
      const decl = this.findDecl(text, at);
      if (decl === null) return null;
      const r = this.keysOf(decl, this.exprEnd(decl), decl, depth + 1);
      if (r) this.laterAssignments(text, decl, at).forEach((key) => r.keys.add(key));
      return r;
    }
    // helper(...) / xs.map((e) => helper(...)).toList() / xs.map(helper)
    const call = text.match(/(?:^|=>\s*|\.map\(\s*)([A-Za-z_$][\w$]*)\s*(?:\(|\))/);
    if (call) return this.returnedKeys(call[1], depth + 1);
    return null;
  }

  mapKeys(open, close, at, depth) {
    const out = { keys: new Set(), complete: true };
    for (let [x, y] of splitTop(this.mask, open + 1, close)) {
      const addEntry = (p, q) => {
        p = this.skipWs(p);
        if (this.code.startsWith("...", p)) {
          const r = this.keysOf(p + (this.code[p + 3] === "?" ? 4 : 3), q, at, depth + 1);
          if (r) {
            r.keys.forEach((key) => out.keys.add(key));
            out.complete &&= r.complete;
          } else out.complete = false;
          return;
        }
        if (this.lang === "dart" && /^(if|for)\s*\(/.test(this.code.slice(p, p + 5))) {
          const po = this.code.indexOf("(", p);
          const pc = matchBracket(this.mask, po);
          const rest = this.skipWs(pc + 1);
          // `if (c) 'a': 1 else 'b': 2`
          const elseAt = this.mask.slice(rest, q).search(/\belse\b/);
          if (elseAt >= 0) {
            addEntry(rest, rest + elseAt);
            addEntry(rest + elseAt + 4, q);
          } else addEntry(rest, q);
          return;
        }
        const s = stringAt(this.code, p, this.lang);
        if (s) {
          const after = this.skipWs(s.end);
          if (this.code[after] === ":") out.keys.add(this.code.slice(s.cs, s.ce));
          return;
        }
        if (this.lang === "ts") {
          const id = this.code.slice(p, q).match(/^([A-Za-z_$][\w$]*)\s*(:|$)/);
          if (id) {
            out.keys.add(id[1]);
            return;
          }
        }
        out.complete = false; // a computed key or something unreadable
      };
      addEntry(x, y);
    }
    return out;
  }

  /** `NAME['key'] = …` (Dart) / `NAME.key = …` / `NAME["key"] = …` between from and to. */
  laterAssignments(name, from, to) {
    const keys = [];
    const body = this.code.slice(from, to);
    const re = new RegExp(String.raw`\b${name}\s*(?:\[\s*['"]([\w]+)['"]\s*\]|\.([A-Za-z_]\w*))\s*=(?!=)`, "g");
    let m;
    while ((m = re.exec(body))) keys.push(m[1] ?? m[2]);
    return keys;
  }

  /** The keys of the map a helper function returns (`Map<…> _row(Entry e) => {…}`). */
  returnedKeys(name, depth) {
    const re = new RegExp(String.raw`\b${name}\s*(?:=\s*(?:async\s*)?)?\(`, "g");
    let m;
    while ((m = re.exec(this.mask))) {
      const po = this.mask.indexOf("(", m.index + name.length);
      const pc = matchBracket(this.mask, po);
      let k = this.skipWs(pc + 1);
      if (this.lang === "ts" && this.mask[k] === ":") {
        // a return type annotation: skip to => or {
        while (k < this.mask.length && !(this.mask.startsWith("=>", k) || this.mask[k] === "{")) k++;
      }
      if (this.mask.startsWith("=>", k)) {
        k = this.skipWs(k + 2);
        const r = this.keysOf(k, this.exprEnd(k), k, depth);
        if (r) return r;
      } else if (this.mask[k] === "{" && !/[=(,:]\s*$/.test(this.mask.slice(Math.max(0, m.index - 3), m.index))) {
        const bc = matchBracket(this.mask, k);
        const ret = this.mask.slice(k, bc).search(/\breturn\s*[{[<(]/);
        if (ret >= 0) {
          const rs = this.skipWs(k + ret + 6);
          const r = this.keysOf(rs, this.exprEnd(rs), rs, depth);
          if (r) return r;
        }
      }
    }
    return null;
  }
}

// ── PostgREST select strings ─────────────────────────────────────────────────
/** 'a, b:c, rel!hint(x, y), ...spread(z), count()' → [{ kind, name, alias, hints, inner }] */
function parseSelect(str) {
  const items = [];
  let depth = 0;
  let s = 0;
  const parts = [];
  for (let k = 0; k < str.length; k++) {
    if (str[k] === "(") depth++;
    else if (str[k] === ")") depth--;
    else if (str[k] === "," && depth === 0) {
      parts.push(str.slice(s, k));
      s = k + 1;
    }
  }
  parts.push(str.slice(s));
  for (let p of parts) {
    p = p.trim();
    if (!p) continue;
    if (p.startsWith("...")) p = p.slice(3).trim();
    if (p === "*") {
      items.push({ kind: "star" });
      continue;
    }
    let alias = null;
    const am = p.match(/^"?([A-Za-z_]\w*)"?\s*:(?!:)\s*/);
    if (am) {
      alias = am[1];
      p = p.slice(am[0].length);
    }
    const paren = p.indexOf("(");
    if (paren >= 0) {
      const head = p.slice(0, paren).trim();
      const inner = p.slice(paren + 1, p.lastIndexOf(")"));
      if (head.includes(".") || /^(count|sum|avg|min|max)$/.test(head)) {
        // an aggregate: count() / amount.sum()
        const col = head.split(".")[0];
        if (head.includes(".")) items.push({ kind: "col", name: col, alias });
        continue;
      }
      const [name, ...hints] = head.split("!").map((x) => x.trim());
      items.push({ kind: "embed", name, alias, hints, inner: parseSelect(inner) });
      continue;
    }
    const name = p
      .split("::")[0]
      .split("->")[0]
      .trim()
      .replace(/^"|"$/g, "");
    items.push({ kind: "col", name, alias });
  }
  return items;
}

// ── the schema ───────────────────────────────────────────────────────────────
const db = new Client({ connectionString: process.env.SUPABASE_DB_URL, ssl: { rejectUnauthorized: false } });
await db.connect();
const q = async (sql, params = []) => (await db.query(sql, params)).rows;

const roles = new Set((await q(`select rolname from pg_roles where rolname in ('anon','authenticated')`)).map((r) => r.rolname));
const rels = new Map(); // name → { kind, rls, cols: Set }
for (const r of await q(`
  select c.relname, c.relkind, c.relrowsecurity rls
  from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','v','m','p','f')`)) {
  rels.set(r.relname, { kind: r.relkind, rls: r.rls, cols: new Set(), priv: {} });
}
for (const r of await q(`
  select a.attrelid::regclass::text rel, c.relname, a.attname
  from pg_attribute a join pg_class c on c.oid = a.attrelid
  where c.relnamespace = 'public'::regnamespace and a.attnum > 0 and not a.attisdropped`)) {
  rels.get(r.relname)?.cols.add(r.attname);
}
// computed fields: a function taking the table's row can be selected like a column
for (const r of await q(`
  select p.proname, t.typname from pg_proc p join pg_type t on t.oid = p.proargtypes[0]
  where p.pronamespace = 'public'::regnamespace and p.pronargs = 1 and t.typtype = 'c'`)) {
  rels.get(r.typname)?.cols.add(r.proname);
}
const fks = await q(`
  select c.conname, s.relname src, d.relname dst,
    array(select a.attname from unnest(c.conkey) k join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k) src_cols
  from pg_constraint c
  join pg_class s on s.oid = c.conrelid
  join pg_class d on d.oid = c.confrelid
  where c.contype = 'f' and s.relnamespace = 'public'::regnamespace and d.relnamespace = 'public'::regnamespace`);
const policies = await q(`select tablename, cmd, roles::text[] roles, permissive from pg_policies where schemaname = 'public'`);
const fns = new Map(); // name → [{ args: [{name, hasDefault}], exec }]
for (const r of await q(`
  select p.proname, p.pronargs, p.pronargdefaults, p.proargnames, p.proargmodes::text[] modes,
    ${roles.has("authenticated") ? "has_function_privilege('authenticated', p.oid, 'EXECUTE')" : "true"}
    or ${roles.has("anon") ? "has_function_privilege('anon', p.oid, 'EXECUTE')" : "true"} exec
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p')`)) {
  const names = r.proargnames ?? [];
  const modes = r.modes ?? names.map(() => "i");
  const ins = names.filter((_, i) => ["i", "b", "v"].includes(modes[i] ?? "i"));
  const args = ins.map((name, i) => ({ name, hasDefault: i >= r.pronargs - r.pronargdefaults }));
  if (!fns.has(r.proname)) fns.set(r.proname, []);
  fns.get(r.proname).push({ args, unnamed: r.pronargs > 0 && ins.filter(Boolean).length < r.pronargs, exec: r.exec });
}
// What the app's own roles (signed in / signed out) may do to each table at all.
const grants = new Map();
if (roles.size) {
  const who = [...roles].map((r) => `'${r}'`).join(",");
  for (const r of await q(`
    select c.relname,
      bool_or(has_table_privilege(r.rolname, c.oid, 'SELECT')) "SELECT",
      bool_or(has_table_privilege(r.rolname, c.oid, 'INSERT')) "INSERT",
      bool_or(has_table_privilege(r.rolname, c.oid, 'UPDATE')) "UPDATE",
      bool_or(has_table_privilege(r.rolname, c.oid, 'DELETE')) "DELETE"
    from pg_class c cross join pg_roles r
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','v','m','p','f') and r.rolname in (${who})
    group by c.relname`)) grants.set(r.relname, r);
}
const granted = (table, cmd) => !roles.size || grants.get(table)?.[cmd] === true;

const hasPolicy = (table, cmd) =>
  policies.some(
    (p) =>
      p.tablename === table &&
      (p.cmd === cmd || p.cmd === "ALL") &&
      p.permissive === "PERMISSIVE" &&
      p.roles.some((r) => r === "public" || r === "authenticated" || r === "anon"),
  );

// ── checking one call ────────────────────────────────────────────────────────
const FILTERS = new Set([
  "eq", "neq", "gt", "gte", "lt", "lte", "like", "ilike", "likeAllOf", "likeAnyOf", "ilikeAllOf", "ilikeAnyOf",
  "is", "isFilter", "is_", "in", "in_", "inFilter", "contains", "containedBy", "overlaps", "textSearch",
  "rangeGt", "rangeGte", "rangeLt", "rangeLte", "rangeAdjacent", "filter", "not",
]);

/** Columns and embeds of a select string against a table. Returns problems. */
function checkSelect(table, items, where = "select") {
  const errs = [];
  const rel = rels.get(table);
  if (!rel) return errs;
  for (const it of items) {
    if (it.kind === "star") continue;
    if (it.kind === "col") {
      if (!rel.cols.has(it.name)) errs.push(`${where}: ${table} has no column "${it.name}"`);
      continue;
    }
    // an embedded table
    const hintNames = it.hints.filter((h) => !["inner", "left"].includes(h));
    let target = rels.has(it.name) ? it.name : null;
    let viaColumn = null;
    if (!target) {
      viaColumn = fks.find((f) => f.src === table && f.src_cols.length === 1 && f.src_cols[0] === it.name);
      if (viaColumn) target = viaColumn.dst;
    }
    if (!target) {
      errs.push(`${where}: nothing called "${it.name}" to embed in ${table}`);
      continue;
    }
    const views = rel.kind === "v" || rels.get(target).kind === "v";
    if (!viaColumn && !views) {
      let links = fks.filter((f) => (f.src === table && f.dst === target) || (f.src === target && f.dst === table));
      if (hintNames.length)
        links = links.filter((f) => hintNames.some((h) => f.conname === h || f.src_cols.includes(h)));
      if (links.length === 0) {
        const junction = fks.some(
          (a) => a.dst === table && fks.some((b) => b.src === a.src && b.dst === target && (!hintNames.length || hintNames.includes(a.src))),
        );
        if (!junction) errs.push(`${where}: no link between ${table} and ${target}${hintNames.length ? ` via !${hintNames.join("!")}` : ""}`);
      } else if (links.length > 1) {
        errs.push(`${where}: ${table} → ${target} has ${links.length} links; PostgREST needs a !hint (${links.map((l) => l.conname).join(", ")})`);
      }
    }
    errs.push(...checkSelect(target, it.inner, where));
  }
  return errs;
}

/** Where a dotted filter column (`member.handle`) lands, via the select's embeds. */
function embedTarget(table, items, alias) {
  const e = items.find((it) => it.kind === "embed" && (it.alias === alias || it.name === alias));
  if (!e) return null;
  if (rels.has(e.name)) return e.name;
  return fks.find((f) => f.src === table && f.src_cols[0] === e.name)?.dst ?? null;
}


function checkFrom(results, src, app, m, adminFile) {
  const openAt = m.index + m[0].length - 1;
  const closeAt = matchBracket(src.mask, openAt);
  const args = splitTop(src.mask, openAt + 1, closeAt);
  if (!args.length) return;
  const table = src.stringValue(args[0][0], args[0][1]);
  if (table === undefined || !/^[a-z_][a-z0-9_]*$/.test(table)) return; // not a table name
  const line = src.line(m.index);
  const r = { app, file: src.path, line, what: `${table}`, errs: [], notes: [] };
  results.push(r);

  // the chain after .from(…)
  const calls = [];
  let k = closeAt + 1;
  for (;;) {
    k = src.skipWs(k);
    if ((src.mask[k] === "!" || src.mask[k] === "?") && src.mask[k + 1] !== "=") k = src.skipWs(k + 1);
    if (src.mask[k] !== "." || src.mask[k + 1] === ".") break;
    k = src.skipWs(k + 1);
    const id = src.mask.slice(k).match(/^[A-Za-z_]\w*/);
    if (!id) break;
    k = src.skipWs(k + id[0].length);
    if (src.mask[k] === "<") {
      let d = 0;
      for (; k < src.mask.length; k++) {
        if (src.mask[k] === "<") d++;
        else if (src.mask[k] === ">" && --d === 0) break;
      }
      k = src.skipWs(k + 1);
    }
    if (src.mask[k] !== "(") break;
    const c = matchBracket(src.mask, k);
    calls.push({ name: id[0], args: splitTop(src.mask, k + 1, c) });
    k = c + 1;
  }

  const rel = rels.get(table);
  if (!rel) {
    r.errs.push(`no table or view called "${table}"`);
    return;
  }
  const names = calls.map((c) => c.name);
  const op = names.includes("upsert") ? "upsert" : names.includes("insert") ? "insert" : names.includes("update") ? "update" : names.includes("delete") ? "delete" : "select";
  r.what = `${table} ${op}`;

  let items = [];
  const selectCall = calls.find((c) => c.name === "select");
  if (selectCall) {
    if (!selectCall.args.length) items = [{ kind: "star" }];
    else {
      const str = src.resolveString(selectCall.args[0][0], selectCall.args[0][1], m.index);
      if (str === undefined) r.notes.push("select list built at run time");
      else {
        items = parseSelect(str);
        r.errs.push(...checkSelect(table, items));
      }
    }
  }
  const col = (name, where) => {
    if (name.includes(".")) {
      const [alias, c] = name.split(".");
      const target = embedTarget(table, items, alias);
      if (target && !rels.get(target).cols.has(c)) r.errs.push(`${where}: ${target} has no column "${c}"`);
      return;
    }
    if (!rel.cols.has(name)) r.errs.push(`${where}: ${table} has no column "${name}"`);
  };
  let filtered = false;
  let onConflict = null;
  let ignoreDuplicates = false;
  for (const c of calls) {
    if (FILTERS.has(c.name) && c.args.length) {
      filtered = true;
      const name = src.stringValue(c.args[0][0], c.args[0][1]);
      if (name !== undefined) col(name, c.name);
    } else if (c.name === "order" && c.args.length) {
      const rest = c.args.slice(1).map(([a, b]) => src.code.slice(a, b)).join(",");
      if (/referencedTable|foreignTable/.test(rest)) continue;
      const name = src.stringValue(c.args[0][0], c.args[0][1]);
      if (name !== undefined) col(name, "order");
    } else if (c.name === "match" && c.args.length) {
      filtered = true;
      const keys = src.keysOf(c.args[0][0], c.args[0][1], m.index);
      keys?.keys.forEach((key) => col(key, "match"));
    } else if (c.name === "or" && c.args.length) {
      filtered = true;
      const expr = src.stringValue(c.args[0][0], c.args[0][1]);
      if (expr !== undefined && !expr.includes("(")) for (const part of expr.split(",")) col(part.split(".")[0].trim(), "or");
    } else if (["insert", "upsert", "update"].includes(c.name) && c.args.length) {
      const keys = src.keysOf(c.args[0][0], c.args[0][1], m.index);
      if (!keys) r.notes.push(`${c.name} values built at run time`);
      else {
        keys.keys.forEach((key) => col(key, c.name));
        if (!keys.complete) r.notes.push(`${c.name}: some keys come from a spread`);
      }
      for (const [a, b] of c.args.slice(1)) {
        const text = src.code.slice(a, b);
        const oc = text.match(/onConflict\s*:\s*(['"`])([^'"`]*)\1/);
        if (oc) onConflict = oc[2];
        if (/ignoreDuplicates\s*:\s*true/.test(text)) ignoreDuplicates = true;
      }
    }
  }
  if (onConflict) for (const c of onConflict.split(",")) col(c.trim(), "onConflict");

  // Row-level security and grants: what this call needs to be allowed at all.
  if (adminFile || rel.kind === "v") return;
  const need = new Set();
  if (op === "select") need.add("SELECT");
  if (op === "insert") need.add("INSERT");
  if (op === "update") need.add("UPDATE");
  if (op === "delete") need.add("DELETE");
  if (op === "upsert") {
    need.add("INSERT");
    if (!ignoreDuplicates) need.add("UPDATE").add("SELECT");
  }
  if ((op === "update" || op === "delete") && filtered) need.add("SELECT");
  if (op !== "select" && selectCall) need.add("SELECT");
  for (const cmd of need) {
    if (rel.rls && !hasPolicy(table, cmd)) {
      const why =
        cmd === "SELECT" && op !== "select"
          ? `no read policy on ${table}, so the ${op} can't see a row to act on`
          : `${table} has row-level security and no ${cmd} policy — the ${op} is refused every time`;
      r.errs.push(why);
    }
    if (!granted(table, cmd)) r.errs.push(`the app's roles hold no ${cmd} grant on ${table}`);
  }
}

function checkRpc(results, src, app, m, adminFile) {
  const openAt = m.index + m[0].length - 1;
  const closeAt = matchBracket(src.mask, openAt);
  const args = splitTop(src.mask, openAt + 1, closeAt);
  if (!args.length) return;
  const line = src.line(m.index);
  let fnNames = [];
  const lit = src.stringValue(args[0][0], args[0][1]);
  if (lit !== undefined) fnNames = [lit];
  else {
    // `isV2 ? 'challenge_board_v2' : 'challenge_board'` — check every name it can be
    const re = /(['"])([a-z_][a-z0-9_]*)\1/g;
    let mm;
    while ((mm = re.exec(src.code.slice(args[0][0], args[0][1])))) fnNames.push(mm[2]);
  }
  if (!fnNames.length) {
    results.push({ app, file: src.path, line, what: "rpc(?)", errs: [], notes: ["function name chosen at run time"] });
    return;
  }
  // the arguments: Dart `params: {…}`, TS a second positional object
  let keys = { keys: new Set(), complete: true };
  let sent = false;
  for (const [a, b] of args.slice(1)) {
    const text = src.code.slice(a, b);
    if (src.lang === "dart") {
      const pm = text.match(/^params\s*:\s*/);
      if (!pm) continue;
      sent = true;
      keys = src.keysOf(a + pm[0].length, b, m.index);
    } else {
      sent = true;
      keys = src.keysOf(a, b, m.index);
    }
    break;
  }
  for (const fn of fnNames) {
    const r = { app, file: src.path, line, what: `rpc ${fn}`, errs: [], notes: [] };
    results.push(r);
    const versions = fns.get(fn);
    if (!versions) {
      r.errs.push(`no function called ${fn}()`);
      continue;
    }
    if (!keys) {
      r.notes.push("arguments built at run time");
      continue;
    }
    const given = [...keys.keys];
    const fits = versions.filter((v) => {
      if (v.unnamed) return false;
      const names = v.args.map((x) => x.name);
      if (!given.every((g) => names.includes(g))) return false;
      if (!keys.complete) return true;
      return v.args.every((x) => x.hasDefault || given.includes(x.name));
    });
    if (fits.length === 0) {
      const sig = versions.map((v) => `${fn}(${v.args.map((x) => x.name + (x.hasDefault ? "?" : "")).join(", ")})`).join(" / ");
      r.errs.push(`${fn}() doesn't take {${given.join(", ")}}${sent ? "" : " (no params sent)"} — the database has ${sig}`);
    } else if (fits.length > 1 && keys.complete) {
      r.errs.push(`${fn}() has ${fits.length} versions that all fit {${given.join(", ")}}: PostgREST can't choose (drop the old one)`);
    } else if (!adminFile && !fits.some((v) => v.exec)) {
      r.errs.push(`neither a signed-in nor a signed-out caller may run ${fn}()`);
    }
    if (!keys.complete) r.notes.push("some arguments come from a spread");
  }
}

// ── run ─────────────────────────────────────────────────────────────────────
function walk(dir, exts, out = []) {
  let entries = [];
  try {
    entries = readdirSync(dir);
  } catch {
    return out;
  }
  for (const e of entries) {
    if ([".dart_tool", "build", "node_modules", ".next"].includes(e)) continue;
    const p = join(dir, e);
    if (statSync(p).isDirectory()) walk(p, exts, out);
    else if (exts.some((x) => p.endsWith(x)) && !/\.(g|freezed)\.dart$/.test(p)) out.push(p);
  }
  return out;
}

// Receivers that have a .from() of their own and are not a database client.
const NOT_A_CLIENT = /(?:\bstorage|\b(?:Map|Array|Buffer|Set|Object|DateTime|TZDateTime|List|Uint8List|Uint8Array|Iterable|String|Stream|Future|Duration|Color|Headers|URLSearchParams)(?:\s*<[^()]*>)?)\s*[!?]?\s*$/;

function scan(results, path, text, appName) {
  if (!/\.(from|rpc)\s*\(/.test(text)) return;
  const src = new Source(path, text);
  // A server route holding the service-role key bypasses RLS: check its shape only.
  const adminFile = text.includes("SUPABASE_SERVICE_ROLE_KEY");
  const re = /\.\s*(from|rpc)\s*\(/g;
  let m;
  while ((m = re.exec(src.mask))) {
    const before = src.mask.slice(Math.max(0, m.index - 60), m.index);
    if (NOT_A_CLIENT.test(before)) continue;
    if (m[1] === "from") checkFrom(results, src, appName, m, adminFile);
    else checkRpc(results, src, appName, m, adminFile);
  }
}

// ── first, the checker checks itself ─────────────────────────────────────────
// A checker that passes everything looks exactly like a codebase with no mistakes. So it
// must catch each of these known-bad calls (and pass the good ones) before its verdict on
// the apps means anything. The cases lean on tables every schema since 053 has.
const SELF_TEST = [
  ["dart", "c.from('no_such_table').select();", /no table or view/],
  ["dart", "c.from('venue_staff').select('role, nope');", /no column "nope"/],
  ["dart", "c.from('venue_staff').select('role').eq('nope', 1);", /no column "nope"/],
  ["dart", "c.from('venue_staff').select('role').order('nope');", /no column "nope"/],
  ["dart", "c.from('venue_areas').insert({'venue_id': v, if (x) 'nope': 1});", /no column "nope"/],
  ["dart", "final row = <String, dynamic>{'venue_id': v, 'name': n};\nrow['nope'] = 1;\nc.from('venue_areas').insert(row);", /no column "nope"/],
  ["dart", "Map<String, dynamic> _row(A a) => {'venue_id': a.v, 'nope': 1};\nvoid f() { c.from('venue_areas').insert(xs.map((a) => _row(a)).toList()); }", /no column "nope"/],
  ["dart", "c.from('staff_enrolments').select('id');", /no SELECT policy/],
  ["dart", "c.from('staff_events').insert({'venue_id': v, 'kind': 'joined'});", /no INSERT policy/],
  ["dart", "c.from('venue_staff').update({'role': 'server'}).eq('user_id', u);", /no UPDATE policy/],
  ["dart", "c.from('blocks').select('blocked:profiles(id)');", /needs a !hint/],
  ["dart", "c.from('venue_staff').select('x:circles(id)');", /no link between/],
  ["dart", "c.from('venue_staff').select('member:profiles(id, nope)');", /profiles has no column "nope"/],
  ["dart", "c.rpc('no_such_function_at_all');", /no function called/],
  ["dart", "c.rpc('claim_staff_enrolment', params: {'eid': e});", /doesn't take/],
  ["dart", "c.rpc('claim_staff_enrolment', params: {'eid': e, 'code': k, 'extra': 1});", /doesn't take/],
  ["dart", "c.rpc(v2 ? 'team_roster' : 'no_such_function_either', params: {'vid': v});", /no function called no_such_function_either/],
  ["ts", "await supabase!.from(\"venue_staff\").select(\"role, nope\").eq(\"user_id\", me);", /no column "nope"/],
  ["ts", "await supabase.rpc(\"claim_staff_enrolment\", { eid });", /doesn't take/],
  ["ts", "const patch: Record<string, unknown> = { name: n };\npatch.nope = 1;\nawait supabase.from(\"venue_areas\").update(patch).eq(\"id\", id);", /no column "nope"/],
  // …and these must pass
  ["dart", "c.from('venue_staff').select('role, venue:venues(*)').eq('user_id', me);", null],
  ["dart", "c.from('blocks').select('blocked:profiles!blocks_blocked_id_fkey(id, handle)').eq('blocker_id', me);", null],
  ["dart", "c.rpc('lock_staff', params: {'vid': v, 'uid': u});", null],
  // …and these aren't database calls at all
  ["dart", "Map<String, dynamic>.from(r as Map); c.storage.from('photos').remove([p]); tz.TZDateTime.from(t, tz.local);", "none"],
  ["ts", "await supabase.rpc(\"lock_staff\", { vid, uid, reason: r });", null],
  ["ts", "const re = /[\"']/; await supabase.from(\"venue_areas\").select(\"id, name\").eq(\"venue_id\", v);", null],
];
let selfBroken = 0;
if (fns.has("claim_staff_enrolment")) {
  for (const [lang, snippet, expect] of SELF_TEST) {
    const res = [];
    scan(res, `self-test.${lang === "dart" ? "dart" : "ts"}`, snippet, "self-test");
    const errs = res.flatMap((r) => r.errs);
    const good =
      expect === "none" ? res.length === 0 : expect ? errs.some((e) => expect.test(e)) : res.length > 0 && errs.length === 0;
    if (!good) {
      selfBroken++;
      const what = expect === "none" ? "read a non-database call as one" : expect ? `missed ${expect}` : "flagged a good call";
      console.log(`  CHECKER BROKEN: ${what} in: ${snippet.replace(/\n/g, " ")}${errs.length ? `  → ${errs.join(" | ")}` : ""}`);
    }
  }
  console.log(`── the checker checked itself: ${SELF_TEST.length - selfBroken}/${SELF_TEST.length} known cases right`);
} else {
  console.log("── self-test skipped (it needs migration 053's tables)");
}

// ── then, the apps ──────────────────────────────────────────────────────────
const results = [];
try {
  for (const app of APPS) {
    for (const path of walk(app.dir, app.exts)) {
      if (SKIP_FILES.has(path)) continue;
      scan(results, path, readFileSync(path, "utf8"), app.name);
    }
  }
} finally {
  await db.end();
}

let failed = 0;
for (const app of APPS) {
  const mine = results.filter((r) => r.app === app.name);
  const bad = mine.filter((r) => r.errs.length);
  const partial = mine.filter((r) => !r.errs.length && r.notes.length);
  failed += bad.length;
  console.log(`\n── ${app.name}: ${mine.length} database calls ─────────────────`);
  for (const r of mine) {
    if (r.errs.length) for (const e of r.errs) console.log(`  FAIL ${r.file}:${r.line}  ${r.what} — ${e}`);
    else if (LIST) console.log(`  ok   ${r.file}:${r.line}  ${r.what}${r.notes.length ? `  (${r.notes.join("; ")})` : ""}`);
  }
  console.log(`  ${mine.length - bad.length} fit the schema, ${bad.length} don't` +
    (partial.length ? `; ${partial.length} partly built at run time (the parts written out were checked)` : ""));
}
console.log("\n═══════════════════════════════════════════════════════");
console.log(`  ${results.length - failed} calls fit, ${failed} don't   (read-only — nothing was changed)`);
if (selfBroken) console.log(`  …and the checker itself missed ${selfBroken} known case(s): its verdict can't be trusted`);
process.exit(failed || selfBroken ? 1 : 0);
