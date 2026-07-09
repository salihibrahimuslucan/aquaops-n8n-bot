# AquaOps Bot

n8n automation over a live ERP: a scheduled morning operations report, a Telegram
assistant with LLM intent classification, and an error watchdog, all reading a
production Supabase Postgres through a dedicated read-only role.

This started as an n8n learning project, but it runs against the live Aquatronic ERP
rather than toy data. The goal was genuine, end-to-end n8n operating experience. I
designed the architecture and the workflow topology, drove the implementation with an
LLM pair-programmer, and executed every step against the live ERP to prove it works
(see "Live test evidence"). The bug-and-fix notes below are not hypothetical. Each one
was hit and resolved.

## What it does

Two n8n workflows plus a watchdog (error workflow), all connected read-only to the live
Supabase ERP:

- **Flow A — ERP watcher** (`workflows/akis-a-erp-gozcusu.json`): every morning at
  08:45 it gathers critical stock, open production orders and the last 24 hours of
  stock movements, has Gemini write a summary in Turkish (the operator's language), and
  sends it by email (Gmail SMTP) and Telegram. If any item is below its critical
  threshold, a separate urgent-alert Telegram message goes out on a parallel branch.
- **Flow B — Telegram ERP assistant** (`workflows/akis-b-telegram-asistan.json`):
  incoming Telegram messages (stock / orders / FX rates / small talk) are
  intent-classified by Gemini, and the answer is produced by fixed, parameterized
  Postgres queries. **The LLM never generates SQL**, it only picks the intent.
- **Watchdog** (`workflows/bekci-error-workflow.json`): if Flow A or B fails, it sends
  a Telegram alert with the workflow name, error message and execution id. **It only
  works while it is itself active** (see "Lessons learned").

## Architecture

Local layout (`N8N_USER_FOLDER`):

```
n8n-ops-bot/
├── start_n8n.cmd          # start recipe: tunnel + n8n (see "Run it")
├── workflows/             # sanitized JSON exports, no secrets — committed
├── db/                    # DDL + rollback for the read-only n8n_ro role
├── tools/run_sql.js       # helper that applies the DDL
├── .secrets.env           # setup-time secret scratchpad — gitignored
└── .n8n/                  # n8n data: SQLite DB + encrypted credential store — gitignored
```

```
Telegram Trigger (webhook, via tunnel)      Schedule Trigger (08:45)
        ↓                                           ↓
  IF: chat_id == owner                    3× Postgres queries → bundle
        ↓ (guard passes)                            ↓
  Gemini: classify intent (JSON)          ┌─────────┴─────────┐
        ↓                            Gemini summary     IF: anything critical?
  Switch: stock / orders / fx / chat       ↓                    ↓ (yes)
        ↓                            Email + Telegram   Urgent alert (Telegram)
  Telegram sendMessage (reply)        (daily report)

      Any workflow throws → Watchdog (error workflow) → Telegram alert
```

## Security

**Secrets.** Nothing secret is committed to git or embedded in the workflow JSON:

- The canonical store is n8n's own encrypted credential store
  (`.n8n/database.sqlite`, encrypted with n8n's key). The Telegram bot token, Gemini
  API key, Gmail app password and the `n8n_ro` Postgres password live there and are
  referenced from the workflows by credential id only (`AqTelegramBot001`,
  `AqGeminiHeader001`, `AqGmailSmtp00001`, `AqErpPostgres001`).
- `.secrets.env` (gitignored) was a one-time scratchpad used to bulk-import the
  credentials during setup.

**Read-only DB role.** The bot talks to a live production database, so it connects
through a dedicated Postgres role that cannot write, regardless of what any workflow
does:

- `db/setup_n8n_ro.sql` creates `n8n_ro` with `SELECT`-only grants on the required
  tables, the matching RLS policy, and read-only transactions by default.
- `db/rollback_n8n_ro.sql` reverses all of it.
- Both are applied with `node tools/run_sql.js <connection-string> <sql-file>`.
- Verified in practice: reads via `n8n_ro` returned hundreds of rows; an `INSERT`
  attempt was rejected.

**Telegram guard.** Flow B answers only its owner: an IF node compares the incoming
`chat_id` against the configured one (`YOUR_CHAT_ID` in the sanitized export) before
anything else runs, and the Telegram Trigger webhook is validated with a
`secret_token`.

## Run it

```powershell
$env:N8N_USER_FOLDER = 'D:\n8n-ops-bot'
npm install --legacy-peer-deps   # required: plain `npm i` breaks n8n via a zod/@langchain peer-dependency conflict
```

n8n 2.29 removed the built-in `n8n start --tunnel` (it is silently ignored, no error).
The working recipe is a manual tunnel plus the `WEBHOOK_URL` environment variable:

```bash
# 1) Start the tunnel and keep it running
npx --yes localtunnel --port 5678
# note the https://XXX.loca.lt URL it prints

# 2) Start n8n pointing at that URL
N8N_USER_FOLDER='D:\n8n-ops-bot' \
GENERIC_TIMEZONE='Europe/Istanbul' \
WEBHOOK_URL='https://XXX.loca.lt/' \
"D:/n8n-ops-bot/node_modules/.bin/n8n.cmd" start
```

Boot takes anywhere from 30 seconds to 4 minutes ("Database is not ready!" and healthz
503 responses are normal during that window). It is ready when
`http://localhost:5678/healthz` returns `{"status":"ok"}`.

**Scheduling caveat:** Flow A's Schedule Trigger only fires if the n8n process is
running at 08:45. Missed triggers are not replayed. The clean fix is a Windows Task
Scheduler task that runs `start_n8n.cmd` (tunnel included) at logon; this is
deliberately not automated yet, and the manual recipe above is the current mode of
operation.

## Live test evidence

- **2026-07-07 — Flow A end-to-end (CLI):** real email + Telegram report delivered. The
  critical-stock list came from the live ERP and flagged a number of zero-stock items.
- **2026-07-07 — Flow B live, from a phone:**
  - a stock query ("412 stok?") returned live quantities for the AquaLIGHT 412 / 412C
    items (real figures generalized in this public copy);
  - an orders query ("emirler") correctly reported no open production orders;
  - an FX query ("kur") returned EUR/TRY 53.42, USD/TRY 46.80;
  - small talk produced a conversational reply. **The first attempt garbled the
    Turkish characters** (see the encoding lesson below). After the fix the reply came
    back in clean UTF-8, verified end to end.
- **2026-07-07 — Guard test:** a POST with a spoofed `chat_id=999` was sent to the
  webhook; execution stopped at the `Telegram Dinle` → `Salih Mi` IF guard, no
  downstream node ran, and no reply was sent.
- **2026-07-07 — Watchdog chaos test:** a throwaway webhook-triggered workflow that
  deliberately throws was executed. **On the first run the watchdog sent nothing**: it
  was inactive (see below). After activating it and re-triggering, the alert arrived
  correctly: workflow name + error message + execution id. The test workflow was
  deleted afterwards.

## Lessons learned

- **Error workflows must themselves be active.** `settings.errorWorkflow` pointed at
  the watchdog, but while the watchdog was inactive it silently did nothing. The
  failure only appeared in the log. Found the hard way in the chaos test above, fixed
  by activating it, then re-verified.
- **Execution mode changes error behavior.** `manual` executions (the "Test Workflow"
  button) do not fire the error workflow at all; `webhook`, `cli`, `error` and
  `internal` modes each hook differently. Chaos tests must use a real trigger.
- **Free tunnels are fragile.** The localtunnel free tier dies occasionally, and every
  restart mints a new URL, which forces an n8n restart with the new `WEBHOOK_URL`. A
  fixed domain via ngrok or cloudflared is the durable fix.
- **Encoding breaks in odd places.** Calling the LLM through the generic HTTP Request
  node, the `responseFormat` setting corrupted UTF-8 output (the garbled Turkish
  characters above). Telegram's `parse_mode` and `appendAttribution` options are
  similar small traps.
- **Windows-native n8n has sharp edges.** `--legacy-peer-deps` is mandatory,
  `N8N_USER_FOLDER` must be set explicitly, and the built-in tunnel is gone as of 2.29.
- **Concepts covered along the way:** Schedule / Telegram (webhook-based, with
  `secret_token` validation) / Manual / Webhook / Error triggers; IF guards, Switch
  routing and multi-output fan-out; HTTP Request, Postgres (parameterized queries over
  a read-only role), Telegram send, Email Send (SMTP with an app password); the Code
  node for packing and parsing data (`JSON.parse`, HTML escaping, length trimming); the
  encrypted, id-referenced credential store and `import:credentials` bulk loading;
  driving n8n programmatically over its REST API (login cookie, workflow CRUD,
  activate/deactivate with the mandatory `versionId`, archive-then-delete, and reading
  executions with `includeData=true`, which returns the Flatted serialization format —
  decoded with the `flatted` npm package).

## Ideas for a phase 2 (not built)

- **AI Agent node** — replace the fixed Switch branches with tool-calling, scoped so
  the model only chooses *which* fixed query to run and still never writes SQL.
- **Merge node** — run Flow A's three sequential Postgres queries in parallel and merge
  the results.
- **Native Gemini node** — the LLM is currently called via HTTP Request + manual JSON
  parsing; compare against n8n's official Gemini node for credential and response
  handling.
- **Persistent tunnel** — move to a fixed ngrok/cloudflared domain and wire
  `start_n8n.cmd` into Task Scheduler.
