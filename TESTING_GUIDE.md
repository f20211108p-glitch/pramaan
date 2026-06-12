# LeadEngine — Manual Testing Guide

> Step-by-step curls to test every feature we built (Chunks 1–7B).
> Run these in order — later steps depend on IDs from earlier ones.

---

## Prerequisites

### 1. Start infrastructure
```bash
docker compose up -d
```
Wait 10 seconds for Postgres + Redis to be healthy:
```bash
docker compose ps
```

### 2. Start the app
```bash
cd C:\Users\Hp\Desktop\Pramaan\leadengine
.venv\Scripts\python.exe -m uvicorn src.main:app --reload --port 8000
# Generate one
python -c "import secrets; print(secrets.token_hex(32))"
```

### 3. Set your shell variables
**PowerShell:**
```powershell
$ADMIN_KEY = "84b434bb52fde359e40e7ec60218a80a829b2f4e9f5b2218be5481cacab2daac"
$BASE = "http://localhost:8000"
```

**Bash / Git Bash:**
```bash
export ADMIN_KEY="change_me_in_production_32chars_min"
export BASE="http://localhost:8000"
```

> Replace the ADMIN_KEY with whatever is in your `.env` under `SECRET_KEY`.

---

## Phase 1: Health Check

```bash
curl http://localhost:8000/health
```
**Expected:**
```json
{"status":"ok","env":"dev","version":"0.1.0"}
```

---

## Phase 2: Create a Client (Tenant)

This creates your test real estate builder account.

```bash
curl -X POST http://localhost:8000/admin/clients \
  -H "Content-Type: application/json" \
  -H "x-admin-key: change_me_in_production_32chars_min" \
  -d '{
    "client_name": "Prestige Group Demo",
    "waba_number": "919820099001",
    "waba_phone_number_id": "WABA_DEMO_001",
    "waba_token": "EAAxxxxxxx_YOUR_REAL_WABA_TOKEN_HERE",
    "broker_wa_numbers": ["+919820099002", "+919820099003"],
    "crm_type": "webhook",
    "crm_token": "https://webhook.site/YOUR-UUID",
    "language_config": {
      "primary_language": "english",
      "regional_languages": ["hindi", "hinglish"],
      "formality_level": "semi_formal",
      "hindi_pronoun": "aap"
    },
    "prompt_overrides": {
      "builder_name": "Prestige Group",
      "greeting_style": "warm"
    }
  }'
```

**Save the `id` from the response — that's your `CLIENT_ID`.**

```bash
# Set it:
export CLIENT_ID="paste-uuid-here"
```

### 2b. Verify it shows in the list
```bash
curl http://localhost:8000/admin/clients \
  -H "x-admin-key: change_me_in_production_32chars_min"
```

### 2c. Get a single client
```bash
curl http://localhost:8000/admin/clients/$CLIENT_ID \
  -H "x-admin-key: change_me_in_production_32chars_min"
```

### 2d. Update client config
```bash
curl -X PATCH http://localhost:8000/admin/clients/$CLIENT_ID \
  -H "Content-Type: application/json" \
  -H "x-admin-key: change_me_in_production_32chars_min" \
  -d '{
    "client_name": "Prestige Group (Updated)",
    "google_calendar_id": "prestige-demo@group.calendar.google.com"
  }'
```

---

## Phase 3: Auth Tests (Negative Cases)

### 3a. Missing admin key → 422
```bash
curl http://localhost:8000/admin/clients
```

### 3b. Wrong admin key → 403
```bash
curl http://localhost:8000/admin/clients \
  -H "x-admin-key: wrong_key_here"
```

---

## Phase 4: Upload a Brochure (RAG Ingestion)

Grab any real estate PDF brochure (or use a test one).

```bash
curl -X POST http://localhost:8000/admin/ingest \
  -H "x-admin-key: change_me_in_production_32chars_min" \
  -F "file=@C:/path/to/your/brochure.pdf" \
  -F "client_id=$CLIENT_ID" \
  -F "project_name=Prestige Lakeside Habitat"
```

**Save the `project_id` from the response.**

```bash
export PROJECT_ID="paste-project-uuid-here"
```

### 4b. List projects with chunk counts
```bash
curl "http://localhost:8000/admin/projects?client_id=$CLIENT_ID" \
  -H "x-admin-key: change_me_in_production_32chars_min"
```

### 4c. Re-ingest (delete old chunks first, then re-upload)
```bash
# Delete old chunks
curl -X DELETE "http://localhost:8000/admin/projects/$PROJECT_ID/chunks?client_id=$CLIENT_ID" \
  -H "x-admin-key: change_me_in_production_32chars_min"

# Then re-upload with the same curl from 4a
```

---

## Phase 5: Simulate WhatsApp Conversations

The webhook endpoint expects the exact Meta WhatsApp Cloud API payload format.
We simulate 4 turns of a HOT lead in Hinglish.

> **Note:** The engine will call Claude API for real LLM responses.
> Make sure `ANTHROPIC_API_KEY` is set in `.env`.
> WhatsApp send will fail (fake WABA token) — that's fine, the pipeline still runs
> and saves everything to DB.

### Turn 1: First message (greeting + location)
```bash
curl -X POST http://localhost:8000/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "BIZ_ACCOUNT_ID",
      "changes": [{
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {
            "display_phone_number": "919820099001",
            "phone_number_id": "WABA_DEMO_001"
          },
          "contacts": [{
            "profile": {"name": "Raj Sharma"},
            "wa_id": "919876500001"
          }],
          "messages": [{
            "from": "919876500001",
            "id": "wamid_turn1_001",
            "timestamp": "1716700000",
            "type": "text",
            "text": {"body": "Hi, mujhe Whitefield mein 2BHK chahiye. Kya options hain?"}
          }]
        },
        "field": "messages"
      }]
    }]
  }'
```

### Turn 2: Budget info
```bash
curl -X POST http://localhost:8000/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "BIZ_ACCOUNT_ID",
      "changes": [{
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {
            "display_phone_number": "919820099001",
            "phone_number_id": "WABA_DEMO_001"
          },
          "contacts": [{
            "profile": {"name": "Raj Sharma"},
            "wa_id": "919876500001"
          }],
          "messages": [{
            "from": "919876500001",
            "id": "wamid_turn2_002",
            "timestamp": "1716700060",
            "type": "text",
            "text": {"body": "Budget 80 lakh ke aaspaas hai, apartment chahiye family of 4 ke liye"}
          }]
        },
        "field": "messages"
      }]
    }]
  }'
```

### Turn 3: Timeline + urgency
```bash
curl -X POST http://localhost:8000/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "BIZ_ACCOUNT_ID",
      "changes": [{
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {
            "display_phone_number": "919820099001",
            "phone_number_id": "WABA_DEMO_001"
          },
          "contacts": [{
            "profile": {"name": "Raj Sharma"},
            "wa_id": "919876500001"
          }],
          "messages": [{
            "from": "919876500001",
            "id": "wamid_turn3_003",
            "timestamp": "1716700120",
            "type": "text",
            "text": {"body": "2 mahine mein shift karna hai, jaldi dhundhna hai"}
          }]
        },
        "field": "messages"
      }]
    }]
  }'
```

### Turn 4: Financing info (makes lead HOT)
```bash
curl -X POST http://localhost:8000/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "BIZ_ACCOUNT_ID",
      "changes": [{
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {
            "display_phone_number": "919820099001",
            "phone_number_id": "WABA_DEMO_001"
          },
          "contacts": [{
            "profile": {"name": "Raj Sharma"},
            "wa_id": "919876500001"
          }],
          "messages": [{
            "from": "919876500001",
            "id": "wamid_turn4_004",
            "timestamp": "1716700180",
            "type": "text",
            "text": {"body": "SBI se pre-approval mil gaya hai 85 lakh ka, Sarjapur Road bhi chalega"}
          }]
        },
        "field": "messages"
      }]
    }]
  }'
```

### 5b. Send a COLD lead (just browsing)
```bash
curl -X POST http://localhost:8000/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "BIZ_ACCOUNT_ID",
      "changes": [{
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {
            "display_phone_number": "919820099001",
            "phone_number_id": "WABA_DEMO_001"
          },
          "contacts": [{
            "profile": {"name": "Just Browsing"},
            "wa_id": "919888800000"
          }],
          "messages": [{
            "from": "919888800000",
            "id": "wamid_cold_001",
            "timestamp": "1716700300",
            "type": "text",
            "text": {"body": "just looking around, no plans to buy right now"}
          }]
        },
        "field": "messages"
      }]
    }]
  }'
```

### 5c. Send a voice note (should get "send text" reply)
```bash
curl -X POST http://localhost:8000/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "BIZ_ACCOUNT_ID",
      "changes": [{
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {
            "display_phone_number": "919820099001",
            "phone_number_id": "WABA_DEMO_001"
          },
          "contacts": [{
            "profile": {"name": "Voice User"},
            "wa_id": "919877700000"
          }],
          "messages": [{
            "from": "919877700000",
            "id": "wamid_voice_001",
            "timestamp": "1716700400",
            "type": "audio",
            "audio": {"id": "audio_media_id_123", "mime_type": "audio/ogg"}
          }]
        },
        "field": "messages"
      }]
    }]
  }'
```

### 5d. Send a Hindi message (different language)
```bash
curl -X POST http://localhost:8000/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "BIZ_ACCOUNT_ID",
      "changes": [{
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {
            "display_phone_number": "919820099001",
            "phone_number_id": "WABA_DEMO_001"
          },
          "contacts": [{
            "profile": {"name": "Hindi User"},
            "wa_id": "919866600000"
          }],
          "messages": [{
            "from": "919866600000",
            "id": "wamid_hindi_001",
            "timestamp": "1716700500",
            "type": "text",
            "text": {"body": "namaste, mujhe ghar kharidna hai Mumbai mein, budget 1 crore hai"}
          }]
        },
        "field": "messages"
      }]
    }]
  }'
```

### 5e. Test unknown WABA (wrong phone_number_id)
```bash
curl -X POST http://localhost:8000/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "BIZ_ACCOUNT_ID",
      "changes": [{
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {
            "display_phone_number": "919999999999",
            "phone_number_id": "UNKNOWN_WABA_999"
          },
          "messages": [{
            "from": "919000000001",
            "id": "wamid_unknown_001",
            "timestamp": "1716700600",
            "type": "text",
            "text": {"body": "Hello?"}
          }]
        },
        "field": "messages"
      }]
    }]
  }'
```
**Expected:** `{"status":"ok"}` but check server logs — should see "Unknown WABA number".

---

## Phase 6: Inspect Everything via Admin API

### 6a. List all leads for your client
```bash
curl "http://localhost:8000/admin/clients/$CLIENT_ID/leads" \
  -H "x-admin-key: change_me_in_production_32chars_min"
```

### 6b. Filter leads by tier
```bash
# Hot leads only
curl "http://localhost:8000/admin/clients/$CLIENT_ID/leads?tier=hot" \
  -H "x-admin-key: change_me_in_production_32chars_min"

# Warm leads
curl "http://localhost:8000/admin/clients/$CLIENT_ID/leads?tier=warm" \
  -H "x-admin-key: change_me_in_production_32chars_min"

# Cold leads
curl "http://localhost:8000/admin/clients/$CLIENT_ID/leads?tier=cold" \
  -H "x-admin-key: change_me_in_production_32chars_min"
```

### 6c. Search leads by phone
```bash
curl "http://localhost:8000/admin/clients/$CLIENT_ID/leads?search=919876500001" \
  -H "x-admin-key: change_me_in_production_32chars_min"
```

### 6d. Get lead detail (use a lead ID from 6a)
```bash
export LEAD_ID="paste-lead-uuid-here"

curl "http://localhost:8000/admin/clients/$CLIENT_ID/leads/$LEAD_ID" \
  -H "x-admin-key: change_me_in_production_32chars_min"
```

**Check these fields in the response:**
- `score` — should be 0–100
- `tier` — hot/warm/cold
- `stage` — qualifying/qualified/scheduling/nurturing/handed_off
- `intent` — buyer/seller/unknown
- `budget_min`, `budget_max` — in INR (e.g. 8000000 = 80L)
- `location_preferences` — array of locations
- `financing_status` — pre_approved/exploring/cash/unknown
- `language_pref` — english/hindi/hinglish

### 6e. Manually update a lead (broker override)
```bash
curl -X PATCH "http://localhost:8000/admin/clients/$CLIENT_ID/leads/$LEAD_ID" \
  -H "Content-Type: application/json" \
  -H "x-admin-key: change_me_in_production_32chars_min" \
  -d '{
    "stage": "handed_off",
    "score": 95,
    "tier": "hot"
  }'
```

### 6f. List conversations for a lead
```bash
curl "http://localhost:8000/admin/clients/$CLIENT_ID/leads/$LEAD_ID/conversations" \
  -H "x-admin-key: change_me_in_production_32chars_min"
```

**Save a `CONVERSATION_ID` from the response.**

### 6g. Read conversation messages (the full chat!)
```bash
export CONV_ID="paste-conversation-uuid-here"

curl "http://localhost:8000/admin/clients/$CLIENT_ID/conversations/$CONV_ID/messages" \
  -H "x-admin-key: change_me_in_production_32chars_min"
```

**This is the gold — you'll see every inbound + outbound message with timestamps.**
Check:
- `direction` = "inbound" for user messages, "outbound" for bot replies
- `content` = the actual message text
- Messages are in chronological order

### 6h. List billing events
```bash
curl "http://localhost:8000/admin/clients/$CLIENT_ID/billing" \
  -H "x-admin-key: change_me_in_production_32chars_min"
```

**Hot leads should have a `qualified_lead` billing event with score/tier in metadata.**

### 6i. Pipeline stats (dashboard overview)
```bash
curl "http://localhost:8000/admin/clients/$CLIENT_ID/stats" \
  -H "x-admin-key: change_me_in_production_32chars_min"
```

**Expected structure:**
```json
{
  "client_id": "...",
  "total_leads": 4,
  "by_tier": {"hot": 1, "warm": 1, "cold": 1, "unscored": 1},
  "by_stage": {"qualifying": 2, "qualified": 1, "nurturing": 1},
  "total_conversations": 4,
  "total_messages": 10,
  "total_billing_events": 1
}
```

---

## Phase 7: CRM Integration Check

### 7a. List available CRM adapters
```bash
curl http://localhost:8000/admin/crm/adapters \
  -H "x-admin-key: change_me_in_production_32chars_min"
```

**Expected:**
```json
{"adapters": ["selldo", "webhook"]}
```

### 7b. CRM health check (for your client)
```bash
curl "http://localhost:8000/admin/clients/$CLIENT_ID/crm/health" \
  -H "x-admin-key: change_me_in_production_32chars_min"
```

If you set `crm_type` to `"webhook"` and `crm_token` to a real webhook.site URL,
the health check will actually hit it.

### 7c. Test with webhook.site (live CRM sync)
1. Go to https://webhook.site — copy your unique URL
2. Update your client's CRM token:
```bash
curl -X PATCH "http://localhost:8000/admin/clients/$CLIENT_ID" \
  -H "Content-Type: application/json" \
  -H "x-admin-key: change_me_in_production_32chars_min" \
  -d '{
    "crm_type": "webhook",
    "crm_token": "https://webhook.site/YOUR-UNIQUE-UUID"
  }'
```
3. Send another WhatsApp message (Phase 5, any turn)
4. Check webhook.site — you should see the lead data POSTed there!

---

## Phase 8: Webhook Verification (Meta setup)

```bash
curl "http://localhost:8000/webhook/whatsapp?hub.mode=subscribe&hub.verify_token=leadengine_verify_2026&hub.challenge=test_challenge_123"
```

**Expected:** Plain text response: `test_challenge_123`

### Wrong verify token:
```bash
curl "http://localhost:8000/webhook/whatsapp?hub.mode=subscribe&hub.verify_token=wrong_token&hub.challenge=test123"
```
**Expected:** 403

---

## Phase 9: Multi-Tenant Isolation Test

### 9a. Create a second client
```bash
curl -X POST http://localhost:8000/admin/clients \
  -H "Content-Type: application/json" \
  -H "x-admin-key: change_me_in_production_32chars_min" \
  -d '{
    "client_name": "Godrej Properties Demo",
    "waba_number": "919820088001",
    "waba_phone_number_id": "WABA_DEMO_002",
    "waba_token": "EAAxxxxxxx_GODREJ_TOKEN",
    "broker_wa_numbers": ["+919820088002"]
  }'
```

**Save this second `CLIENT_ID_2`.**

### 9b. Send a message to client 2's WABA
```bash
curl -X POST http://localhost:8000/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "BIZ_2",
      "changes": [{
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {
            "display_phone_number": "919820088001",
            "phone_number_id": "WABA_DEMO_002"
          },
          "contacts": [{"profile": {"name": "Godrej Lead"}, "wa_id": "919555500001"}],
          "messages": [{
            "from": "919555500001",
            "id": "wamid_godrej_001",
            "timestamp": "1716701000",
            "type": "text",
            "text": {"body": "Interested in 3BHK in Bandra, budget 2 crore"}
          }]
        },
        "field": "messages"
      }]
    }]
  }'
```

### 9c. Verify isolation — Client 1 should NOT see Client 2's leads
```bash
# Client 1's leads
curl "http://localhost:8000/admin/clients/$CLIENT_ID/leads" \
  -H "x-admin-key: change_me_in_production_32chars_min"

# Client 2's leads
curl "http://localhost:8000/admin/clients/$CLIENT_ID_2/leads" \
  -H "x-admin-key: change_me_in_production_32chars_min"
```

The phone `919555500001` should ONLY appear in Client 2's response.

---

## Phase 10: Edge Cases

### 10a. Duplicate message (same message_id)
```bash
# Send the same payload twice — second should be deduped
curl -X POST http://localhost:8000/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "BIZ_ACCOUNT_ID",
      "changes": [{
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {"phone_number_id": "WABA_DEMO_001"},
          "messages": [{
            "from": "919876500001",
            "id": "wamid_dedup_test_001",
            "timestamp": "1716702000",
            "type": "text",
            "text": {"body": "This is a dedup test"}
          }]
        },
        "field": "messages"
      }]
    }]
  }'

# Send exact same payload again (same wamid_dedup_test_001)
curl -X POST http://localhost:8000/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "BIZ_ACCOUNT_ID",
      "changes": [{
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {"phone_number_id": "WABA_DEMO_001"},
          "messages": [{
            "from": "919876500001",
            "id": "wamid_dedup_test_001",
            "timestamp": "1716702000",
            "type": "text",
            "text": {"body": "This is a dedup test"}
          }]
        },
        "field": "messages"
      }]
    }]
  }'
```
Check logs — second call should show "duplicate" and NOT create a new message.

### 10b. Status update (should be ignored gracefully)
```bash
curl -X POST http://localhost:8000/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "changes": [{
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {"phone_number_id": "WABA_DEMO_001"},
          "statuses": [{"id": "wamid_xxx", "status": "delivered"}]
        },
        "field": "messages"
      }]
    }]
  }'
```
**Expected:** `{"status":"ok"}` — no errors in logs.

### 10c. Empty/malformed payload
```bash
curl -X POST http://localhost:8000/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{}'
```
**Expected:** `{"status":"ok"}` — graceful handling, no 500.

---

## Phase 11: Database Direct Check (Optional)

If you want to peek at the raw DB:

```bash
docker exec -it leadengine_postgres psql -U lead -d leadengine
```

Then:
```sql
-- See all clients
SELECT id, client_name, crm_type, active FROM client_config;

-- See all leads with scores
SELECT id, phone, name, score, tier, stage, intent,
       budget_min, budget_max, language_pref
FROM leads ORDER BY updated_at DESC;

-- See conversation messages
SELECT m.direction, m.content, m.timestamp
FROM messages m
JOIN conversations c ON m.conversation_id = c.id
WHERE c.client_id = 'YOUR_CLIENT_ID'
ORDER BY m.timestamp;

-- See billing events
SELECT * FROM billing_events ORDER BY created_at DESC;

-- See consent log
SELECT * FROM consent_log;

-- See brochure chunks
SELECT project_name, chunk_type, COUNT(*) as chunks,
       pg_size_pretty(SUM(LENGTH(text))::bigint) as text_size
FROM brochure_chunks
GROUP BY project_name, chunk_type;

-- Check multi-tenant isolation
SELECT client_id, COUNT(*) as lead_count
FROM leads GROUP BY client_id;
```

---

## What to Validate at Each Phase

| Phase | What to Check |
|-------|---------------|
| 1 | Server starts, health returns OK |
| 2 | Client created with UUID, shows in list, updates work |
| 3 | Auth rejects missing/wrong keys |
| 4 | PDF ingested, chunks created with embeddings |
| 5 | Messages processed, leads created, scores assigned, Claude replies make sense |
| 6 | All admin queries return correct data, filters work, pagination works |
| 7 | CRM adapters listed, health check runs, webhook.site receives data |
| 8 | Meta webhook verification handshake works |
| 9 | Two clients' data is completely isolated |
| 10 | Dedup works, status updates ignored, bad payloads handled gracefully |
| 11 | DB has all the right data with correct client_id on every row |

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Connection refused` on curl | Is `uvicorn` running? Check port 8000 |
| `403 Invalid admin key` | Check `SECRET_KEY` in `.env` matches your curl header |
| `Engine error` in logs | Check `ANTHROPIC_API_KEY` in `.env` — Claude API needed |
| `Unknown WABA number` | The `phone_number_id` in webhook must match a client's `waba_phone_number_id` |
| WhatsApp send fails | Expected with fake WABA token — pipeline still works, just can't send reply to real WhatsApp |
| `Connection refused` on port 5432 | Run `docker compose up -d` |
| Brochure ingest fails | Make sure the file is a real PDF (`.pdf` extension required) |
| Dedup not working | Check Redis is running: `docker exec leadengine_redis redis-cli ping` |
