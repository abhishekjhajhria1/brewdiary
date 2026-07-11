# 02 — Plain-English glossary

Every technical word used in this project, explained like you've never heard it. Keep this open in a
tab. Terms are grouped, not alphabetical, so related ideas sit together.

## The big picture: front-end, back-end, database
- **App / web app.** A program you use in a web browser (Chrome, Safari). brewdiary is a web app.
- **Front-end.** Everything the user sees and touches — the buttons, the calendar, the colors. Runs in
  the user's browser. *(Analogy: the dining room of a restaurant.)*
- **Back-end.** The behind-the-scenes machinery — saving data, checking passwords, talking to the AI.
  Runs on a server, not in the user's browser. *(Analogy: the kitchen.)*
- **Server.** A computer, somewhere in the cloud, that runs the back-end and answers requests from
  users' browsers. It's always on.
- **Database.** The organized filing cabinet where all the data lives permanently (accounts, drink
  entries, comments…). Ours is **Supabase** (see below).
- **The cloud.** Just "someone else's computers on the internet" that we rent instead of owning.

## The technologies this project uses (the "stack")
- **Stack.** The set of technologies a project is built from. Ours: Next.js + React + TypeScript +
  Tailwind (front-end) and Supabase (back-end + database).
- **JavaScript.** The programming language every web browser understands. It makes pages interactive.
- **TypeScript.** JavaScript with **type labels** added — you say "this is a number, this is text," and
  the computer catches mistakes *before* users ever see them. Files end in `.ts` or `.tsx`. *(Analogy:
  a recipe that says "2 cups flour" instead of just "flour," so you can't accidentally pour in soup.)*
- **React.** A tool for building user interfaces out of reusable pieces called **components**. Instead
  of one giant page, you build small blocks (a button, a calendar day, a chat bubble) and snap them
  together.
- **Component.** One reusable UI building block in React. In our code, a file like `DayCell.tsx` is the
  component for a single square on the calendar. *(Analogy: a LEGO brick.)*
- **Next.js.** A framework built on top of React that adds the "grown-up" features a real product needs:
  turning web addresses into pages (**routing**), running some code on the server, building the app for
  release, etc. It's the skeleton everything hangs on.
- **Framework.** A big pre-built starting kit that handles the boring, universal parts so you only write
  the parts unique to your app.
- **Tailwind (CSS).** The styling system. **CSS** is the language that controls how things *look*
  (colors, spacing, fonts). Tailwind lets you style by adding short labels right on an element, like
  `class="text-ink rounded-tile"`, instead of writing separate style files.
- **Node / npm.** **Node** lets JavaScript run *outside* a browser (needed to build the app and run the
  server). **npm** is its "app store" for code — it downloads the ~free building blocks (**packages**)
  the project depends on. `npm install` fetches them; `npm run dev` starts the app for development.
- **Package / dependency / library.** A chunk of someone else's code we reuse (e.g. the Supabase client,
  the OpenAI client). They live in the `node_modules` folder after `npm install`.

## Data words
- **Table.** One sheet in the database, like a spreadsheet tab. We have tables named `entries`,
  `profiles`, `friendships`, `comments`, etc.
- **Row / record.** One line in a table — one drink entry, one user, one comment.
- **Column / field.** One property on a row — an entry's `drink`, its `date`, its `mood`.
- **Query.** A request to the database, like "give me all of this user's entries from June."
- **Schema.** The blueprint of the database: which tables exist and what columns they have. Ours lives
  in the `supabase/*.sql` files.
- **SQL.** The language you use to talk to a database (create tables, ask for rows). Files end in `.sql`.
- **Migration.** A `.sql` file that changes the database's structure (adds a table, a column). We number
  them (`002_split.sql`, `003_circles.sql`…) so they run in order, like chapters.
- **JSON.** A simple, universal text format for data, using `{ }` and `[ ]`. How the front-end and
  back-end pass information to each other. Example: `{ "drink": "Negroni", "mood": "cozy" }`.
- **JSONL.** "JSON Lines" — a file with one JSON object per line. The format we save AI training
  examples in.

## Accounts, security, and keys
- **Authentication (auth).** Proving who you are — signing up and logging in. Supabase handles ours.
- **Session / cookie.** After you log in, the browser holds a **cookie** (a small token) that says
  "this person is logged in," so you don't retype your password on every click.
- **Environment variable.** A secret or setting kept *outside* the code, in a file called `.env.local`,
  so it never gets shared publicly. Example: the AI provider's secret key. Names like `AI_API_KEY`.
- **API key.** A secret password that proves *we* are allowed to use a paid service (like the Groq AI).
  If it leaks, strangers can spend our money — so it's kept server-side only and never sent to browsers.
- **Server-side / client-side.** Server-side = runs on our server (safe place for secrets). Client-side
  = runs in the user's browser (never put secrets here — anyone can read it).
- **RLS (Row-Level Security).** A database rule that says *which rows each user is allowed to see or
  change*. It's why User A can never read User B's private diary even though both are in the same table.
  This is enforced by the database itself, not just by our code — a very strong guarantee.
- **Rate limiting.** Capping how many times someone can hit a feature in a short window (e.g. 20 AI
  chats per minute) so nobody can spam it and run up our bill.

## Web plumbing
- **API.** A doorway one program uses to ask another program for something. When the browser needs the
  AI to answer, it calls **our** API, which calls the **AI provider's** API.
- **API route / endpoint.** A specific back-end doorway at a web address. Ours: `/api/bartender` handles
  chat with Ninkasi. Files under `src/app/api/`.
- **Request / response.** A request is the question the browser sends; the response is the answer it
  gets back.
- **Streaming.** Sending a reply piece-by-piece as it's generated, so the chat "types out" live instead
  of appearing all at once.
- **Route / page.** A web address that shows a screen. `/you` shows the You screen, `/together` the
  social hub. In Next.js, folders under `src/app/` become routes.
- **Deploy / hosting.** Putting the finished app on the internet so real users can visit it (e.g. on
  Vercel). "Going live."
- **Build.** Packaging the code into an optimized version ready to run. `npm run build`. If it fails,
  something's broken — so we run it before calling anything "done."

## React-specific words (you'll see these in doc 04)
- **State.** Data that can change while you use the app, and the screen updates when it does — e.g. the
  text you're typing, or the list of chat messages so far.
- **Hook.** A reusable React function whose name starts with `use…` (like `useEntries`, `useProfile`).
  It gives a component access to data or behavior. Think of hooks as "plug-in outlets" a component uses
  to get what it needs (the current user, the list of drinks, etc.).
- **Props.** The inputs you hand a component, like arguments to a recipe. A `DayCell` component gets
  props telling it which date it is and how many drinks were logged.
- **localStorage.** A small storage box inside the browser itself. We use it for on-device stuff (your
  theme choice, and a logged-out visitor's first drink before they make an account).

## AI words (full detail in doc 05)
- **LLM (Large Language Model).** The kind of AI that understands and writes text — the "brain" behind a
  chatbot. Ninkasi is powered by one.
- **Model.** One specific trained AI brain, with a name and a size (e.g. "Qwen2.5-7B"). "7B" = 7 billion
  **parameters** (its internal dials); bigger is usually smarter but costlier to run.
- **Prompt.** The text you send an AI. A **system prompt** is a hidden instruction that sets the AI's
  personality and rules (Ninkasi's whole character is a system prompt).
- **Fine-tuning / training.** Teaching an existing model new behavior by showing it many examples. We'll
  fine-tune an open model on Ninkasi-style conversations so it "becomes" Ninkasi natively.
- **Teacher / student (distillation).** A clever, cheap plan: a big smart model (the **teacher**, Groq)
  answers users now; we collect those good answers; then we train a smaller model we own (the
  **student**) to imitate them. Distillation = pouring the big model's skill into a small one.
- **Token.** The unit AIs read and bill by — roughly a word-piece. Longer messages = more tokens = more
  cost. (Why we cap message length.)
- **Provider-agnostic / OpenAI-compatible.** Many AI companies speak the same "shape" of API (the one
  OpenAI popularized). Because our code speaks that shape, we can switch AI providers by changing one
  setting — no code rewrite.

Next: **[03 — How the code is organized](03-how-the-code-is-organized.md)**.
