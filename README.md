# LeadEngine v2

Multi-tenant real estate lead qualification SaaS.

WhatsApp message comes in, LangGraph qualifies the lead across multiple turns,
scores them hot/warm/cold, notifies brokers, syncs to CRM, and tracks billing.

## Architecture

```
WhatsApp Cloud API
        │
        ▼
   ┌──────────┐     ┌────────────┐     ┌──────────────┐
   │ Webhook   │────▶│ Tenant     │────▶│ LangGraph    │
   │ (FastAPI) │     │ Resolver   │     │ Engine       │
   └──────────┘     └────────────┘     └──────────────┘
        │                                    │
        │           ┌────────────┐           │
        │           │ RAG Search │◀──────────┘
        │           │ (pgvector) │
        │           └────────────┘
        │                                    │
        ▼                                    ▼
   ┌──────────┐     ┌────────────┐     ┌──────────────┐
   │ WhatsApp  │     │ Broker     │     │ CRM Sync     │
   │ Reply     │     │ Notify     │     │ (HubSpot)    │
   └──────────┘     └────────────┘     └──────────────┘
```

**Key design decisions:**

- **Multi-tenant**: Every DB query filters by `client_id`. Tenant resolved from `waba_phone_number_id`.
- **Multilingual**: Supports English, Hindi, Hinglish. Language detected per conversation, replies match.
- **RAG**: Brochure PDFs chunked + embedded (text-embedding-3-small), stored in pgvector, searched on property queries.
- **Billing**: Per-client billing model (direct/per_visit/per_lead). Events written on qualification.
- **Observability**: Langfuse tracing on every node + LLM call. Eval judges for quality gating.

## Stack

| Layer | Tech |
|---|---|
| API | FastAPI + Uvicorn |
| Conversation engine | LangGraph (state machine) |
| LLM | Claude (Anthropic) |
| Embeddings | OpenAI text-embedding-3-small |
| Database | PostgreSQL 16 + pgvector |
| Cache / Queue | Redis 7 (dedup, rate limiting, streams) |
| Observability | Langfuse |
| Cron jobs | APScheduler (daily digest, re-engagement, warm lead summary) |
| CI/CD | GitHub Actions → Railway |

## Quick Start

```bash
# 1. Clone and enter
git clone <repo-url> && cd leadengine

# 2. Start Postgres, Redis, Langfuse
docker-compose up -d

# 3. Create virtualenv and install
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -e ".[dev]"

# 4. Configure environment
cp .env.example .env
# Fill in: ANTHROPIC_API_KEY, OPENAI_API_KEY, SECRET_KEY

# 5. Run migrations
alembic upgrade head

# 6. Seed a test client
python scripts/seed_client.py

# 7. Start the server
make dev
# → http://localhost:8000/health
```

## Running Tests

```bash
# All unit tests (no API keys needed — everything mocked)
make test

# E2E tests only (needs test Postgres running)
make test-e2e

# With coverage
make test-cov

# Run eval judges (quality gate)
python -m src.evals.runner --dataset src/evals/datasets/qualification_v1.json
```

## Docker

```bash
# Build
docker build -t leadengine .

# Run (pass env vars)
docker run -p 8000:8000 --env-file .env leadengine
```

## Onboarding a New Client

Use the admin API (requires `SECRET_KEY` in the `x-admin-key` header):

```bash
# 1. Create client
curl -X POST http://localhost:8000/admin/clients \
  -H "x-admin-key: $SECRET_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "client_name": "Acme Realty",
    "waba_number": "+919876543210",
    "waba_phone_number_id": "FROM_META_BUSINESS_MANAGER",
    "waba_token": "FROM_META",
    "broker_wa_numbers": ["+919820099999"],
    "language_config": {
      "primary_language": "hinglish",
      "formality_level": "formal",
      "hindi_pronoun": "aap"
    }
  }'

# 2. Upload brochure PDFs (creates embeddings for RAG)
curl -X POST http://localhost:8000/admin/clients/{client_id}/projects \
  -H "x-admin-key: $SECRET_KEY" \
  -F "file=@brochure.pdf" \
  -F "project_name=Prestige Sunrise Park"

# 3. Set WABA webhook URL in Meta Business Manager:
#    https://yourdomain.com/webhook/whatsapp
```

## Adding a New CRM Adapter

1. Create `src/crm/your_crm.py` implementing the sync interface
2. Add a case to `src/crm/sync.py` → `sync_lead_to_crm()`
3. Set `crm_type` on the client config to your adapter name

## Adding a New Language

1. Add detection patterns in `src/engine/nodes/language_detector.py`
2. Add reply templates in the qualifier/scorer prompt overrides
3. Set `language_config.primary_language` on the client config

## Project Structure

```
src/
  api/          # FastAPI routes (webhooks, admin, dashboard)
  channels/     # WhatsApp channel + message router
  core/         # Tenant resolver, dedup, rate limiter, tracing, LLM client
  crons/        # APScheduler jobs (digest, re-engagement)
  crm/          # CRM sync adapters (HubSpot)
  db/           # SQLAlchemy models, engine, queries
  engine/       # LangGraph state machine + nodes
  evals/        # LLM-as-judge evaluators + runner
  models/       # Pydantic models
  notifications/# Broker notification
  rag/          # Brochure ingestion + pgvector search
tests/          # Unit + E2E tests (all LLM calls mocked)
scripts/        # Seeding, simulation, onboarding
```

## Environment Variables

See `.env.example` for the full list. Key ones:

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `REDIS_URL` | Yes | Redis connection string |
| `ANTHROPIC_API_KEY` | Yes | Claude API key for LLM |
| `OPENAI_API_KEY` | Yes | For embeddings + Whisper |
| `SECRET_KEY` | Yes | Admin API auth key |
| `WHATSAPP_VERIFY_TOKEN` | Yes | Meta webhook verification |
| `LANGFUSE_PUBLIC_KEY` | No | Langfuse observability |
| `LANGFUSE_SECRET_KEY` | No | Langfuse observability |
| `APP_ENV` | No | `dev` (default) or `production` |
| `WEBHOOK_MODE` | No | `sync` (default) or `async` (Redis stream worker) |
