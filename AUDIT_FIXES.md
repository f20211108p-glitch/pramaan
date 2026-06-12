# Production Audit — Findings & Fixes (2026-06-11)

## Round 6 — audit of previously unexamined modules (voice, CRM, RAG ingest, crons, tracing, evals)

Verdict: the hardened core is sound; the *periphery* was not production-grade. Fixed now:

1. **Boot safety:** the voice stack (mixed LiveKit 0.x/1.x APIs — cannot import under the pinned SDK) was imported at FastAPI startup via the router chain — a potential boot-blocker for the whole API. Voice imports are now lazy; a broken voice stack degrades those endpoints to 503 instead of killing the service.
2. **Voice compliance hygiene** (stack remains config-gated off until rebuilt): outbound lead query now requires recorded consent; calls blocked outside 09:00–21:00 IST (TRAI); the prompt rule "NEVER mention that you are an AI" replaced with honest AI disclosure; hot/warm prioritization fixed (`tier.desc()` sorted *warm first* lexicographically — now an explicit rank).
3. **CRM sync was broken for every dashboard-onboarded client:** onboarding sent `crm_type="sell_do"`, registry key is `"selldo"`. Fixed.
4. **Broker digests failed 100% at the Meta API:** template body params contained newlines (Meta error #132000). All template params now sanitized to single-line.
5. **Cron follow-ups were invisible to the conversation engine:** re-engagement and hot/warm follow-up sends are now persisted via `save_message`, so the qualifier sees the question the lead is answering and the dashboard shows the full thread.
6. **RAG ingestion:** PDF extraction/chunking moved off the event loop (`to_thread`); re-ingestion now replaces a project's chunks instead of doubling them; 50 MB upload cap.
7. **Tracing silently dead:** `langfuse` pinned `>=2,<3` (tracing.py uses the v2 API; v3 removed it and every trace failed silently).

Known-remaining from this round (deliberate): voice agent worker process doesn't exist — voice must stay disabled until rebuilt on one SDK generation; eval gate is vacuous (judges static fixtures, passes on missing API key); voice's invalid lead stages; PII masking in traces; per-keystroke search debounce; Langfuse sharing the app database in compose. Two reviewer claims were verified FALSE and not acted on: `tests/` exists (18 files), and `dashboard/src/app/projects/page.tsx` exists.

## Round 5 — adversarial review of the booking loop (same day)

Independent re-review of round 4 confirmed the loop sound on the happy path and found 4 issues — all fixed:

1. **MEDIUM** No DB backstop for `site_visit_booked`: if the stage write failed, a repeat confirmation re-ran all side effects (duplicate bill, duplicate broker alert, duplicate calendar event). The unique index now covers `(client_id, lead_id, event_type)` for both `qualified_lead` and `site_visit_booked` (index renamed `uq_billing_once_per_type`), and `_handle_visit_booked` returns early when the event is a duplicate — same pattern as the hot-lead path. On a *transient* write failure it proceeds with the broker alert (missing metric beats a lead nobody meets).
2. **MEDIUM** `parse_slot_to_datetime` booked a week late when the named weekday was today — including explicit "aaj Sunday 10 baje". Rewritten hour-first: today/tomorrow words take priority over weekday names; a bare weekday equal to today books same-day only when the hour is still ahead, otherwise refuses to guess.
3. **LOW** Ordinal/bare confirmations ("option 2", "haan pakka") produced an unusable `booked_slot` ("Requested time: haan pakka" in the broker alert). New `_resolve_slot_pick` resolves numbered picks against the slots actually offered in the conversation, and bare agreements when exactly one slot was offered.
4. **NOTE** `create_site_visit`'s blocking Google client was now in the live message path — split into a sync implementation dispatched via `asyncio.to_thread`.

## Round 4 — product-truth fixes (same day)

1. **The booking loop now closes.** Previously, a lead confirming "Sunday 10 baje" got a confident confirmation — and then *nothing happened*: no broker alert, no calendar event, no `site_visit_booked` record (the daily digest's "Appointments Booked" was permanently zero). Now, on the first transition into `scheduled`: the scheduler surfaces `booked_slot` through state → router writes the `site_visit_booked` billing event, creates a Google Calendar event when the slot parses to an unambiguous datetime (`parse_slot_to_datetime` is deliberately conservative — requires both a day reference and an explicit hour; a wrong-time event is worse than none), and sends every broker a "Site Visit CONFIRMED" WhatsApp alert (`notify_visit_booked`) with the lead's details and calendar link. CRITICAL-level logs fire if no broker can be reached. Transition-guarded so repeat confirmations can't double-book or double-notify.
2. **Seller handoff fixed.** `intent_detector` set `handoff_reason` to a prose sentence while the handoff node compared against the key `"seller"` — every seller lead received the generic cold-lead brush-off instead of "our specialists will call you about selling." Reason is now the machine-readable key.

### Remaining for best-in-sector (unchanged priority)
Opt-out/STOP handling + consent revocation (DPDP / Meta policy), template messages for out-of-window cron sends, per-conversation human-takeover switch, greeter's wasted Sonnet call on first message, test suite rewrite, metrics.

## Round 3 — independent re-review of rounds 1–2 (same day)

A fresh subagent review of all modified files confirmed the lock, idempotency constraint, intent classifier, and auth overhaul are correctly wired, and surfaced 6 contained issues — all fixed:

1. **MEDIUM** Brochure-ingest success toast showed `undefined` — frontend expected `chunks_created`/`project_name`, backend returns `chunks_ingested`. Contract aligned (`lib/api.ts`, `projects/page.tsx`).
2. **MEDIUM** A *transient* billing-write failure (not a duplicate) would suppress the broker notification forever, since the hot tier was already persisted and the scorer never re-fires. Now: duplicate → no notify (correct); transient failure → notify anyway + CRITICAL "bill manually" log. Losing revenue beats losing the lead.
3. **LOW** `_brochure_unavailable_ack` was dead code — when a brochure was requested but undeliverable, the LLM reply went out (the exact hallucination this flow exists to prevent). Now wired in.
4. **LOW** Migration 0005's dedupe kept both rows on `created_at` ties (then the unique index aborted the migration). Tie-break on `id` added.
5. **LOW** Embedder docstring/table comment claimed `e5-small`, code uses `paraphrase-multilingual-MiniLM-L12-v2` — comments fixed + re-ingestion warning added (model swaps silently break vector comparability).
6. **LOW** Lead-lock wait (60 s) exceeded Meta's 20 s webhook timeout in sync mode — wait is now mode-aware (10 s sync / 60 s async workers).

## Round 2 — production-hardening pass (same day)

1. **Cross-tenant address removed** (`engine/nodes/scheduler.py`) — booking confirmations no longer default to a hardcoded "Shreeji Greens, Vadodara" address. Missing `prompt_overrides.site_address` → "we'll share the exact location shortly" + ops warning log.
2. **Per-lead processing lock** (`core/lead_lock.py`, wired in `channels/router.py`) — Redis token lock with Lua compare-and-delete release serializes all processing per (client, lead). Eliminates concurrent graph runs, lost lead-field updates, and double replies. Fail-open on Redis outage.
3. **Billing idempotency at the DB level** (migration `0005`, `db/tables.py`, `db/queries.py`) — partial unique index: one `qualified_lead` billing event per lead, ever. `write_billing_event` returns `None` on duplicate; broker notification now keys off the actual write, so duplicates can neither double-bill nor double-ping brokers. Migration also dedupes historical rows.
4. **LLM turn-intent classifier** (`engine/intent.py`) — one Haiku tool-use call per turn classifies `wants_brochure` / `confirming_slot` / `slot_text` / `asking_question`, replacing ~250 lines of regex/keyword heuristics in the scheduler and router. Runs **concurrently** with the RAG search (zero added latency); regex retained solely as the no-LLM fallback. This is the robustness fix for Hinglish ("Sunday dekhta hu, but pehle price batao").
5. **Latency/cost cuts** — scorer's Haiku reasoning now generated only on tier *transitions* (was: every message, read by no one); language detector gets a deterministic fast path (established English speakers with zero Hindi signal skip the LLM). Typical turn drops from 4–5 LLM calls to 2–3.
6. **Ops hardening** — `/health` no longer leaks exception strings; optional Sentry via `SENTRY_DSN`; **seeded default admin (`admin@getpramaan.com`/`pramaan2026` from migration 0004) is auto-disabled at production boot if the password was never changed** — that was a known-credential backdoor in every deployment.

### Still open for "9+ across the board" (not completable in one session)
- Rewrite `test_admin_api`/`test_dashboard_api` against JWT auth; add a webhook→reply integration test with a mocked LLM; make the eval suite a hard CI gate with thresholds per node.
- Real calendar booking: scheduler confirms visits but never creates the Google Calendar event ("future turn" never lands).
- `DateTime(timezone=True)` migration across all tables.
- Prometheus metrics (queue depth, LLM latency/cost per turn, reply SLA) + alerting.
- Key-rotation story for the Fernet token encryption (key versioning, re-encrypt job).
- Delete the ~20 one-off `scripts/fix_*` / `reset_*` scripts; replace with admin API operations.
- Outbound voice agent (`voice/`) needs its own audit before enabling.

---

Critical-fix pass across backend (`src/`) and dashboard (`dashboard/`). No restructuring; behavior-preserving except where the behavior was the bug.

## Critical (pipeline-breaking)

1. **Async mode dropped every message** — `src/api/webhooks.py`
   `is_duplicate()` is a check-AND-mark Redis SETNX. The webhook marked the message before enqueuing; the worker then saw it as a duplicate and skipped it. With `WEBHOOK_MODE=async` (the default), no lead ever got a reply. **Fix:** dedup now happens exactly once, inside `MessageRouter.route_inbound()`.

2. **No webhook signature verification** — `src/api/webhooks.py`
   `WhatsAppChannel.verify_signature()` existed but was never called: anyone could POST forged lead messages, burn LLM spend, and pollute CRM data. **Fix:** `X-Hub-Signature-256` verified against new `META_APP_SECRET` setting (403 on mismatch); warning logged if unset in production.

3. **Encrypted WABA tokens sent raw to Meta** — `src/channels/whatsapp.py`, `src/core/tenant.py`, `src/crons/jobs.py`
   Tokens are stored encrypted (`enc::…`). The tenant-resolver cache-hit path decrypted them, but the DB cache-miss path and all 5 cron jobs passed the encrypted string as the Bearer token → sends failed. **Fix:** decryption centralized at point of use in `WhatsAppChannel` (`_resolve_token`, idempotent for plaintext).

## Critical (security)

4. **Broken authorization: any JWT = full admin** — `src/api/admin.py`, `dashboard.py`, `voice.py`
   `_verify_admin_key` only decoded the JWT — no role check, no tenant check, no DB lookup. Any client-role user could read/modify every tenant's leads, conversations, billing, and client configs. **Fix:** all 33 endpoints now use DB-backed auth (`get_current_user`) plus `_admin_only` (client CRUD, queue stats, SIP trunk) or `_tenant_access` (client-scoped routes: admin = any tenant, client = own tenant only). `GET /admin/clients` returns only the caller's own client for client-role users.

5. **Credential leakage in API responses** — `src/api/admin.py`
   `_to_str_id()` serialized every ORM column, including `waba_token` / `crm_token`, into client responses. **Fix:** `waba_token`, `crm_token`, `password_hash` always redacted.

6. **Admin key compiled into the public JS bundle** — `dashboard/src/lib/auth.ts`
   Fallback read `NEXT_PUBLIC_ADMIN_KEY` (anything `NEXT_PUBLIC_` ships to every browser). Backend doesn't accept that header anyway. **Fix:** removed; JWT only.

7. **Production boot guard** — `src/main.py`
   App would happily run production with `SECRET_KEY=change_me_in_production` (forgeable JWTs + derivable Fernet key). **Fix:** refuses to start; warns on missing `META_APP_SECRET` / `CORS_ORIGINS`.

## High

8. **Event-loop blocking** — bcrypt verify/hash in login & user creation (`api/auth.py`), fastembed model load + inference (`rag/embedder.py`), and the Haiku insight call (`insights/lead_insight.py`) all ran synchronously inside async handlers, stalling every concurrent request/worker. **Fix:** moved to `asyncio.to_thread`. Login also now verifies against a dummy hash when the email doesn't exist (timing-based user enumeration).

9. **`generate_lead_insight` cache/return + duplicate sync `invalidate_insight_cache`** — `insights/lead_insight.py` — consolidated to a single async `invalidate_insight_cache()` awaited by the router (the old version relied on `asyncio.get_event_loop().create_task` side effects).

10. **Voice notes saved twice** — `src/channels/router.py` saved `[voice note]` then a second row with the transcript for the same `channel_message_id`, polluting conversation history fed to the LLM. **Fix:** exactly one inbound row per voice note (transcript on success, placeholder on failure).

## Dashboard bugs

11. `listProjects()` ignored the backend's `{projects: [...]}` envelope → Projects page always rendered empty. Fixed.
12. `deleteProjectChunks()` called `DELETE /admin/chunks?project_name=` — a route that doesn't exist (backend is `DELETE /admin/projects/{project_id}/chunks`). Fixed, and the page now passes `project_id`.

## Minor

13. `worker.py`: `asyncio.get_event_loop()` → `get_running_loop()`.
14. `.env.example`: documented `META_APP_SECRET`.

## Known debt (not addressed in this pass — flagged)

- `tests/test_admin_api.py` / `test_dashboard_api.py` still authenticate with the legacy `x-admin-key` header the API no longer accepts — they were failing before this audit and need rewriting against JWT auth.
- `scorer` forces `stage="qualified"` on every turn regardless of data collected.
- Admin rate limiter fails open when Redis is down and keys on spoofable client IP.
- `docker-compose.yml` carries hardcoded dev credentials (fine for local, never deploy as-is).
- One-shot scripts in `scripts/` (fix_*, reset_*, update_token*) should be deleted from the repo.
