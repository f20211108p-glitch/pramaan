# LeadEngine — DECISIONS.md (Chunk 0)

> **This file is the output of Chunk 0 — the alignment call.**
> Locked before writing any code. Both devs must follow these exactly.
> Changes require explicit discussion — do not silently deviate.

---

## 1. Repo & Tooling

- **Monorepo:** `https://github.com/pramaan2026-cloud/Lead-Qualification-Agent`
- **Branching:** `feat/chunk-1a-db`, `feat/chunk-1b-models`, `feat/chunk-2a-webhook`, etc.
- **Python:** 3.12
- **Package manager:** `uv`
- **Merge to main:** only after both devs confirm the chunk handoff works end-to-end

---

## 2. Environment Variables

Names are locked. Populate values in your local `.env` (never commit `.env`).

| Variable | Value / Notes |
|---|---|
| `DATABASE_URL` | `postgresql+asyncpg://lead:leadpass@localhost:5432/leadengine` |
| `REDIS_URL` | `redis://localhost:6379/0` |
| `ANTHROPIC_API_KEY` | `sk-ant-...` |
| `OPENAI_API_KEY` | `sk-...` — embeddings + Whisper **only**, not for chat |
| `WHATSAPP_VERIFY_TOKEN` | `leadengine_verify_2026` |
| `LANGFUSE_PUBLIC_KEY` | `pk-lf-...` |
| `LANGFUSE_SECRET_KEY` | `sk-lf-...` |
| `LANGFUSE_HOST` | `http://localhost:3001` |
| `APP_ENV` | `dev` |
| `LOG_LEVEL` | `INFO` |

---

## 3. Interface Contracts

Both devs must agree on these exact signatures. Changing a signature = coordination required.

```python
# DEV-A provides to DEV-B (Chunk 1A → 1B):
# Delivered at: end of Day 1
async def resolve_client(waba_number: str) -> ClientConfig | None
# Looks up client_config by waba_number WHERE active = true.
# Returns None (not an exception) if unknown — caller handles gracefully.

# DEV-B provides to DEV-A (Chunk 1B → 2A):
# Delivered at: end of Day 1
class LeadProfile(BaseModel):
    # exact field names locked in Section 4 below

# DEV-A provides to DEV-B (Chunk 2A → 2B):
# Delivered at: end of Day 2 (Handoff H1)
async def handle_message(
    client_id: str,
    lead_phone: str,
    text: str,
    language: str | None,
    media_type: str | None,   # "text" | "audio" | "image" | "document"
    media_id: str | None,     # WhatsApp media ID for voice/image
) -> str                      # returns bot reply text

# DEV-A provides to DEV-B (Chunk 4A → 3B):
# Delivered at: end of Day 4 (Handoff H2)
async def rag_search(
    query: str,
    client_id: str,
    project_ids: list[str],
    chunk_type: str | None = None,  # "pricing_table" | "amenities" | "location" | None
) -> list[str]                      # returns top 3 matching text chunks
```

---

## 4. LeadProfile Field Names

Locked here so DEV-A tags DB columns to match and DEV-B extracts to match.
No aliases. No renames. These exact strings everywhere.

| Field | Type | Default |
|---|---|---|
| `phone` | `str` | required |
| `client_id` | `str` | required |
| `name` | `str \| None` | `None` |
| `email` | `str \| None` | `None` |
| `language_pref` | `Literal["english", "hindi", "hinglish", "regional"]` | `"english"` |
| `intent` | `Literal["buyer", "seller", "investor", "renter", "unknown"]` | `"unknown"` |
| `budget_min` | `int \| None` — in INR, e.g. `7000000` = ₹70 lakh | `None` |
| `budget_max` | `int \| None` — in INR | `None` |
| `timeline_months` | `int \| None` | `None` |
| `urgency` | `Literal["immediate", "1_3_months", "3_6_months", "6_plus", "unknown"]` | `"unknown"` |
| `financing_status` | `Literal["pre_approved", "exploring", "cash", "unknown"]` | `"unknown"` |
| `location_preferences` | `list[str]` — e.g. `["Andheri", "Thane"]` | `[]` |
| `property_type` | `Literal["apartment", "villa", "plot", "commercial", "any"]` | `"any"` |
| `family_size` | `int \| None` | `None` |
| `score` | `int \| None` — 0 to 100 | `None` |
| `tier` | `Literal["hot", "warm", "cold"] \| None` | `None` |
| `stage` | `Literal["new", "qualifying", "qualified", "scheduling", "nurturing", "handed_off", "converted", "lost"]` | `"new"` |

---

## 5. Scoring Thresholds

```
hot   → score >= 70   (trigger broker notification + calendar booking)
warm  → 40 <= score < 70   (enter nurture flow)
cold  → score < 40    (low-touch or discard)
```

---

## 6. Multi-tenancy Rule

> **Every DB query MUST include `client_id` in the WHERE clause. No exceptions.**

This is enforced in `src/db/queries.py`. If you write a raw query anywhere else, add `client_id` filter. A query without `client_id` is a data leak.

---

## 7. Handoff Points

These are the exact moments where DEV-A passes something to DEV-B so parallel work can continue.

| Handoff | When | DEV-A delivers | DEV-B does |
|---|---|---|---|
| **H1** | End of Day 2 | `handle_message()` function signature + stub | Wires the LangGraph to it |
| **H2** | End of Day 4 | `rag_search()` function (real implementation) | Calls it from qualifier node |

---

## 8. Week Map (2-Dev Parallel)

```
                    DEV-A                              DEV-B
         ┌──────────────────────┐           ┌──────────────────────┐
Day 0    │      CHUNK 0 (TOGETHER — this alignment, DECISIONS.md)  │
         └──────────────────────┘           └──────────────────────┘
Day 1    │ CHUNK 1A: DB + tenant │           │ CHUNK 1B: Models + graph skeleton │
Day 2    │ CHUNK 2A: WA webhook  │  ──H1──► │ CHUNK 2B: lang detector + greeter │
Day 3    │ CHUNK 3A: RAG ingest  │           │ CHUNK 3B: qualifier node           │
Day 4    │ CHUNK 4A: RAG search  │  ──H2──► │ CHUNK 4B: scorer + prompt caching  │
         │       + voice notes   │           │                                    │
Day 5    │      CHUNK 5 (TOGETHER — integration test, seed, demo)               │
         └──────────────────────┘           └──────────────────────┘

Week 2:
Day 6    │ CHUNK 6A: Broker notif│           │ CHUNK 6B: scheduler node          │
Day 7    │ CHUNK 7A: Admin API   │           │ CHUNK 7B: CRM adapters            │
Day 8    │       CHUNK 8 (TOGETHER — API endpoints for dashboard)               │
Day 9-10 │       CHUNK 9 (DEV-B leads — Next.js dashboard)                     │
Day 9-10 │ CHUNK 10A: msg queue  │                                              │
         │ + dedup + rate limit  │                                              │

Week 3:
Day 11   │       CHUNK 11: APScheduler crons                                    │
Day 12   │       CHUNK 12: Evals + observability                                │
Day 13   │       CHUNK 13: E2E test + deployment                                │
Day 14   │       CHUNK 14: Client onboarding flow                               │
```

---

## 9. Stack Summary

| Layer | Choice | Why |
|---|---|---|
| API | FastAPI + Uvicorn | Async-native, fast |
| Conversation engine | LangGraph | Stateful graph with checkpointing |
| LLM | Claude only | No multi-LLM routing — simpler, one billing |
| Embeddings | OpenAI `text-embedding-3-small` | Cost-effective, 1536-dim |
| Voice | Whisper (OpenAI) | Best accuracy for Indian accents |
| DB | PostgreSQL 16 + pgvector | Vector search without Pinecone |
| Cache | Redis 7 | Message dedup + tenant cache + LangGraph checkpointer |
| Observability | Langfuse | LLM tracing + prompt versioning |
| Cron | APScheduler | Replaces n8n — no external dependency |
| Dashboard | Next.js | Broker-facing lead feed |

---

## 10. What Changed from v1

- Multi-tenant architecture with `client_id` everywhere, WABA-based routing
- RAG pipeline for brochure ingestion (pgvector, not Pinecone)
- Multilingual support: Hindi / Hinglish / English with Claude-based detection
- Voice note transcription via Whisper
- n8n removed — replaced with APScheduler inside FastAPI
- Multi-LLM routing removed — Claude only
- Broker WhatsApp notification + Google Calendar with LeadProfile context
- Prompt caching from Week 2
- `consent_log` + `billing_events` tables from Day 1
