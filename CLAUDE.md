# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Salesforce DX project implementing an AI-powered chatbot using Lightning Web Components (LWC) and Apex. The chatbot integrates with OpenAI (via Named Credential) to provide context-aware assistance over Salesforce records, pulling additional context from external ERP and BI systems. Users can query data, get rich visual summaries, upload files for analysis, and create/update records directly from the chat panel.

- **API Version:** 62.0
- **Source directory:** `force-app/main/default/`
- **No namespace** (unmanaged package)
- **Original dev org alias:** `gprlmth5@gmail.com`
- **Team dev org alias:** `GPRLM1` (`gprlm1@gmail.com`) — primary deploy target for dev team handoff

## Commands

```bash
# Linting
npm run lint                    # ESLint on all LWC/Aura JS files
npm run prettier                # Auto-format all files
npm run prettier:verify         # Check formatting without writing

# LWC unit tests (Jest)
npm test                        # Run all unit tests
npm run test:unit               # Same as above
npm run test:unit:watch         # Watch mode
npm run test:unit:debug         # Debug mode
npm run test:unit:coverage      # With coverage report

# Apex tests (requires authenticated org)
sf apex run test \
  --class-names LNChatControllerTest LNChatRecordActionServiceTest \
  --target-org GPRLM1 \
  --result-format human --wait 10

# Deploy
sf project deploy start --source-dir force-app/main/default --target-org GPRLM1 --wait 15
sf project retrieve start --source-dir force-app/main/default --target-org GPRLM1

# Auth
sf org login web --alias GPRLM1 --instance-url https://login.salesforce.com
```

Pre-commit hooks (husky + lint-staged) automatically run prettier, ESLint, and LWC tests on staged files.

## Architecture

### Read (Query) Flow

```
User types in lnchatInput (LWC) — optionally attaches a file
  → fires 'messagesend' event with { message, attachment }
  → lnchatShell.handleMessageSend()
  → LNChatController.sendMessage(userMessage, recordId, objectApiName, conversationHistoryJson, attachmentJson)
      → LNChatContextBuilderService.buildContext()
          → SOQL: query current record + all related objects (see Context Coverage below)
          → LNChatERPService.getRecordData() [HTTP callout]
          → LNChatBIService.getMetrics() [HTTP callout]
      → LNChatLLMService.chat(conversationHistory, userMessage, contextData, attachmentJson)
          → builds multimodal messages (text + image/file block if attachment present)
          → HTTP callout → OpenAI /v1/chat/completions
      → DML: upsert LNChatSession__c, insert LNChatMessage__c
  → Response returned to lnchatShell
  → lnchatResponseRenderer picks child component by responseType
```

**Callout ordering is critical:** all HTTP callouts (ERP, BI, OpenAI) must precede all DML to comply with Salesforce's mixed-DML/callout restriction.

### Write (Create/Update) Flow

```
LLM returns responseType "record_action"
  → lnchatResponseRenderer renders lnchatRecordActionCard (confirm/cancel UI)
  → User clicks Confirm
  → lnchatShell.handleRecordActionConfirm()
  → LNChatController.executeRecordAction() [Apex @AuraEnabled]
      → LNChatRecordActionService.executeAction()
          → findAmbiguousTargets() — blocks if multiple records share the same name
            (skipped when updating the current page's own record)
          → findDuplicates() — blocks if new field values collide with existing records
          → DML: insert or update SObject
  → Success/duplicate/ambiguous alert rendered in chat
```

### LWC Component Hierarchy

All components use the `lnchat` prefix (LNChat naming convention).

- **lnchatDrawer** — standalone fixed-position FAB (floating action button) that slides open a full-height drawer panel; hosts `lnchatShell` in `displayMode="drawer"`; can be placed on any Lightning page
- **lnchatShell** — top-level container; owns conversation state, loads/clears history, dispatches to Apex for read and write; adapts layout via `@api displayMode` (`utility` | `sidebar` | `drawer`)
- **lnchatInput** — textarea with suggestion chips + `+` attach button; fires `messagesend` with `{ message, attachment }` and `attacherror` on bad file. Chips: *Summarize this record / Open Opportunities / Open Cases / Open Tasks / What are the risks?*
- **lnchatHistory** — renders message list with timestamps and attachment pills; bubbles `recordactionconfirm` / `recordactioncancel` / `recordnavigate` / `alertproceed` / `alertcancel` events up to lnchatShell
- **lnchatResponseRenderer** — routes to one of 8 display components based on `responseType`
  - `lnchatKpiCardGrid` — metrics with trends and SLDS icon aliases
  - `lnchatChartWidget` — bar/line/donut charts (Chart.js static resource; arrays cloned with `Array.from()` to avoid LWC proxy mutation errors)
  - `lnchatComparisonTable` — Salesforce vs external data side-by-side
  - `lnchatTimelineView` — event sequences with status badges
  - `lnchatAlertBanner` — severity-based alerts (critical/warning/info/success)
  - `lnchatRecordActionCard` — create/update confirmation card with field table and Confirm/Cancel buttons
  - `lnchatRecordSummary` — rich record overview with header, KPI bar (colour-coded), and related-record sections
  - *(summary)* — inline sections + badges (fallback)

### Apex Layer

| Class | Role |
|---|---|
| `LNChatController` | `@AuraEnabled` entry point: `sendMessage()` (5 params including `attachmentJson`), `getConversationHistory()`, `clearConversationHistory()`, `executeRecordAction()` |
| `LNChatLLMService` | Builds system prompt (8 response schemas + 13 rules), constructs multimodal OpenAI messages, calls `/v1/chat/completions`, handles retries and token-limit errors |
| `LNChatContextBuilderService` | Assembles full Salesforce context + external data before calling LLM (see Context Coverage) |
| `LNChatRecordActionService` | Performs CREATE/UPDATE DML for Account/Contact/Task/Case/Opportunity/Quote with duplicate and ambiguity checks |
| `LNChatERPService` | HTTP POST template for ERP integration |
| `LNChatBIService` | HTTP POST template for BI integration |
| `LNChatResponseDTO` | Deserializes structured JSON from LLM response |

All Apex uses `with sharing` (respects record-level security).

### File Attachment Flow

`lnchatInput` uses the browser `FileReader` API to read the selected file client-side. The result is serialised as JSON and passed through the `messagesend` event → `lnchatShell` → `LNChatController.sendMessage(attachmentJson)` → `LNChatLLMService.chat(attachmentJson)`.

| File type | Client-side handling | OpenAI message format |
|---|---|---|
| Images (jpg/png/gif/webp, ≤ 3 MB) | `readAsDataURL` → base64 data URL | `content` array with `image_url` block |
| CSV / TXT / JSON (≤ 500 KB) | `readAsText` → plain string | Appended as `[Attached file: name]\n...` in user text |
| PDF (≤ 3 MB) | `readAsDataURL` → base64 data URL | `content` array with `file` block (`filename` + `file_data`) |
| DOCX / DOC | — | Rejected client-side with friendly toast error |

Attachment JSON structure sent to Apex:
```json
// Image / PDF
{ "type": "image|pdf", "name": "file.png", "mimeType": "image/png", "base64Data": "data:image/png;base64,..." }
// Text
{ "type": "text", "name": "data.csv", "content": "col1,col2\n..." }
```

Conversation history stores only the text portion of each turn; attachments are one-shot context for the current call and are not persisted.

### Context Coverage (LNChatContextBuilderService)

Full record fields are always queried via dynamic SOQL. Related data is filtered to **open/active records only** and capped at **5 items per section** to keep context concise.

| Page | Related data included | Filter applied |
|---|---|---|
| **Account** | Contacts (10), open Opportunities (5), open Cases (5), open Tasks (5), Orders (5), Contracts (5), Quotes (5) | Opps: `IsClosed = false`; Cases: `Status NOT IN ('Closed','Resolved')`; Tasks: `Status NOT IN ('Completed','Cancelled')` |
| **Contact** | open Opportunities via ContactRole (5), open Cases (5), open Tasks (5), parent Account details | Same open-record filters as above |
| **Opportunity** | Contacts via OpportunityContactRole (10), open Tasks (5), Quotes (5), parent Account, related Orders | Tasks: `Status NOT IN ('Completed','Cancelled')` |
| **Case** | open Tasks (5) | Tasks: `Status NOT IN ('Completed','Cancelled')` |
| **Lead** | open Tasks (5) | Tasks: `Status NOT IN ('Completed','Cancelled')` |

Each related query is individually try-caught so missing/disabled objects (e.g. Quotes not enabled) silently skip.

The LLM is also instructed (Rule 13) to show at most 5 items per section and add a `+ N more open [object]...` placeholder when context contains more records. KPI counts reflect totals, not the 5 shown.

### LLM Response Schemas (8 types)

| `responseType` | Used for |
|---|---|
| `kpi_cards` | Metrics, numbers, performance summaries |
| `chart` | Trends over time, distributions (bar/line/donut via Chart.js) |
| `comparison` | Salesforce vs external data side-by-side |
| `timeline` | Activity history, project phases, event sequences |
| `alert` | Risks, anomalies, urgent issues, success/error feedback |
| `summary` | General narrative answers with sections and badges |
| `record_summary` | Rich record overview — header, KPI bar, related-record sections |
| `record_action` | CREATE or UPDATE a record — renders confirmation card |

### Record Actions (Create / Update)

**Supported objects:** Account, Contact, Task, Case, Opportunity, Quote

**Duplicate detection — two independent checks:**

1. **Ambiguous target** (UPDATE only, skipped when updating the current page record):
   - Queries the target record's key identity fields (Name for Account/Opportunity, LastName+FirstName for Contact, etc.)
   - If other records share the same key fields → blocked with list of candidates + their Record IDs
   - Message: *"Multiple [Object] records found — specify the Record ID of the one you want to update"*

2. **New-value collision** (CREATE and UPDATE):
   - Contact: checks Email (primary), then FirstName+LastName
   - Account: checks Name
   - Opportunity: checks Name+AccountId
   - Case: checks Subject+AccountId
   - Lead: checks Email (primary), then LastName+Company
   - Message: *"Duplicate [Object] record(s) found — action blocked"*

**Auto parent associations** (applied by LLM automatically):
- On Account page → Contact/Opportunity/Case/Task get `AccountId`/`WhatId` = current Account
- On Contact page → Task gets `WhoId` = Contact + `WhatId` = Contact's Account; Opportunity/Case get parent AccountId
- On Opportunity page → Task gets `WhatId` = Opportunity; Contact/Case get parent AccountId
- On Case page → Task gets `WhatId` = Case

**Current record rule:** When user says "update account/contact/this record", LLM uses `salesforceRecord.Id` from context directly — no name search, no ambiguity check.

### Custom Data Model

- **`LNChatSession__c`** — one per conversation (fields: `RecordId__c`, `ObjectApiName__c`, `LastActivityDate__c`)
- **`LNChatMessage__c`** — individual messages (fields: `Session__c` lookup → `LNChatSession__c`, `Role__c`, `Content__c`, `ResponseType__c`)
- **`AI_Config__mdt`** — Custom Metadata storing the OpenAI API key (`ApiKey__c`), model name (`ModelName__c`), and max tokens (`MaxTokens__c`). Record: `Default`. **Must be configured via Setup UI — the source file is excluded from CLI deploy (`.forceignore`) to prevent overwriting the real key.**

### External Integrations

Named Credentials are used for all external endpoints (OpenAI, ERP, BI) — no hardcoded URLs. Remote Site Settings are required for callouts. See `SETUP_GUIDE.md` for full configuration steps.

Named Credentials deployed to GPRLM1: `OpenAI_GPT` (endpoint: `https://api.openai.com`), `External_ERP`, `External_BI`, `Anthropic_Claude`.

## Key Constraints

- **Governor limits:** 3 callouts per `sendMessage()` transaction (ERP + BI + OpenAI). All callouts must precede DML.
- **API key location:** `AI_Config__mdt` record `Default` — set `ApiKey__c` via Setup UI only, never commit to source.
- **MaxTokens:** Set `MaxTokens__c` to **4096** (or higher) in `AI_Config__mdt`. Values ≤ 2000 cause empty responses (`finish_reason: length`) for large contexts like record summaries. `LNChatLLMService` default fallback is 4096.
- **LWC rendering:** AI responses are rendered as structured data objects, not raw HTML.
- **Chart.js proxy fix:** Chart.js mutates data arrays by adding a `_chartjs` property; LWC reactive proxies are read-only and will throw. Always clone with `Array.from()` before passing to Chart.js.
- **Chart.js loading:** Loaded as a UMD static resource (`staticresources/chartjs.js`), referenced in `lnchatChartWidget` via `@salesforce/resourceUrl`.
- **LWC reserved names:** `@api` properties named `data` cause LWC compiler errors — use `cardData`, `tableData`, `chartSeries`, etc. instead.
- **querySelector tag names must match component folder names:** `lnchatShell.js` uses `this.template.querySelector('c-lnchat-history')` — if you rename an LWC component folder you must also update all `querySelector` string literals in parent JS files (sed on `.html` files alone is not enough).
- **Utility bar deployment:** Custom LWC components cannot be added to the utility bar via metadata/CLI — must be done via Setup → App Manager → Edit app → Utility Items in the UI. Both `AI_Assistant_UtilityBar.flexipage-meta.xml` and `AI_Assistant.app-meta.xml` are in `.forceignore`.
- **Callout-before-DML:** `LNChatContextBuilderService` and `LNChatLLMService` callouts run before `getOrCreateSession()` and `saveChatMessage()` DML in `LNChatController.sendMessage()`.
- **Conversation history:** `lnchatShell` pops the user message from `conversationHistory` on API failure so failed attempts do not accumulate and inflate the context on retry.
- **File attachment limits:** Images and PDFs are capped at 3 MB before base64 encoding (~4 MB encoded). Text files are capped at 500 KB. These stay within Salesforce's `@AuraEnabled` request-body limits.
- **displayMode property:** `lnchatShell` accepts `@api displayMode` = `"utility"` (default, utility bar), `"sidebar"` (App Builder column), or `"drawer"` (used by `lnchatDrawer`). The minimize button is hidden in sidebar and drawer modes.
- **Open-records-only context:** `LNChatContextBuilderService` filters related records to open/active only (open opps, non-closed cases, incomplete tasks) with LIMIT 5 per section. This prevents oversized summaries on accounts with many historical records.

## Post-Deploy Manual Steps (new org)

1. **API key** — Setup → Custom Metadata Types → AI Config → Manage Records → New → Developer Name: `Default`, set `ApiKey__c`, `ModelName__c`, `MaxTokens__c = 4096`
2. **Named Credential** — already deployed via CLI; verify `OpenAI_GPT` endpoint matches your target (`https://api.openai.com`)
3. **Utility bar** — Setup → App Manager → your app → Edit → Utility Items → Add `lnchatDrawer`

## Setup Reference

Full deployment steps, Named Credentials configuration, permission sets, and troubleshooting are in `SETUP_GUIDE.md`.
