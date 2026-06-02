# AI Chatbot for Salesforce — Setup Guide

## Prerequisites

- Salesforce CLI (`sf` or `sfdx`) installed
- A Salesforce org with API version 62.0 support (Winter '25 or later)
- An OpenAI API key — obtain from https://platform.openai.com/api-keys
- Chart.js v4 UMD bundle (download instructions below)
- Remote Site Settings configured for `https://api.openai.com`

---

## Step 1 — Download Chart.js Static Resource

Chart.js must be uploaded as a Static Resource named `chartjs`.

```bash
# Download the UMD bundle
curl -L "https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js" \
  -o force-app/main/default/staticresources/chartjs.js
```

Then update the resource meta file to match:

```
force-app/main/default/staticresources/chartjs.resource-meta.xml  (already created)
force-app/main/default/staticresources/chartjs.js                  (downloaded above)
```

> **Note:** The static resource name in the file system must be `chartjs.js` with
> a matching `chartjs.resource-meta.xml`. Remove the `chartjs/` subdirectory if
> you placed the JS file directly.

---

## Step 2 — Configure Remote Site Settings

Remote Site Settings are deployed automatically via metadata (`OpenAI_API.remoteSite-meta.xml`).
If the deploy fails or you need to add them manually:

1. Go to **Setup → Security → Remote Site Settings**
2. Click **New Remote Site**
3. Name: `OpenAI_API`
4. URL: `https://api.openai.com`
5. Active: ✓ checked
6. **Save**

Repeat for your external ERP and BI system URLs if they differ from the Named Credential placeholders.

---

## Step 3 — Deploy All Metadata

```bash
# Authenticate to your org (if not already)
sf org login web --alias my-org

# Deploy everything
sf project deploy start \
  --source-dir force-app/main/default \
  --target-org my-org \
  --wait 15

# Verify deployment
sf project deploy report --target-org my-org
```

### Run Apex tests after deploy

```bash
sf apex run test \
  --class-names LNChatControllerTest LNChatRecordActionServiceTest \
  --target-org my-org \
  --result-format human \
  --wait 10
```

Expected: all tests pass. If tests fail with "OpenAI API key not configured" — that is expected on a fresh org. Complete Step 5 first, then re-run.

---

## Step 4 — Configure Named Credentials in Setup UI

### 4a. OpenAI GPT (Required)

1. Go to **Setup → Security → Named Credentials**
2. Find **OpenAI GPT** (deployed from XML)
3. Click **Edit** — verify URL is `https://api.openai.com`
4. Authentication Protocol: **No Authentication** (API key is passed in the Authorization header by Apex)
5. **Save**

> The API key is stored in Custom Metadata (`AI_Config__mdt`), not the Named Credential itself.

### 4b. External ERP (Optional — configure for your system)

1. Find **External ERP** in Named Credentials
2. Click **Edit**
3. Replace URL `https://your-erp-system.com/api` with your real ERP endpoint
4. Configure authentication per your ERP provider
5. **Save**

### 4c. External BI (Optional — configure for your system)

1. Find **External BI** in Named Credentials
2. Click **Edit**
3. Replace URL `https://your-bi-system.com/api` with your real BI endpoint
4. Configure authentication per your BI provider
5. **Save**

### 4d. Web Search (Optional — internet-sourced company overview in Account summaries)

Asking the chat to **summarize / review / prep** an **Account** adds a grounded
_Company Overview_ section (text + source links). `LNChatWebService` uses OpenAI's
**web-search-capable chat model** (`gpt-4o-search-preview`) via the existing
`OpenAI_GPT` Named Credential and the same `AI_Config__mdt` `ApiKey__c` — **no separate
search vendor, endpoint, or key**. It fires **only** on those intents, and only on
Account pages — never on other turns/objects.

Requirements:

1. The OpenAI key in `AI_Config__mdt` `Default` → `ApiKey__c` (already set in Step 5) must have access to a search-capable model.
2. Verify the current search model id and per-search pricing on OpenAI; update `SEARCH_MODEL` in `LNChatWebService.cls` if it changes.

> **Cost:** the search-preview models add a per-call web-search fee on top of token
> usage. The intent gate keeps this to summary turns only. To disable entirely, comment
> out the web block in `LNChatContextBuilderService.buildContext` (or it simply yields no
> overview if the model/key is unavailable — no errors either way).
>
> **Data governance:** when enabled, the account name (and city/state) are sent to OpenAI
> on summary turns — the same vendor already used for every chat response.

---

## Step 5 — Store the OpenAI API Key in AI_Config\_\_mdt

The API key must be stored in the **AI Config** Custom Metadata Type.

> **CRITICAL:** Set `MaxTokens__c` to **4096** or higher. Values ≤ 2000 cause
> empty responses (`finish_reason: length`) for large record contexts like
> Account summaries with many related records.

### Via Salesforce Setup UI (recommended)

1. Go to **Setup → Custom Metadata Types**
2. Find **AI Config** → click **Manage Records**
3. Click **New** (or edit the **Default** record if it exists)
4. Set **Developer Name** to `Default`
5. Set **Api Key** to your OpenAI API key (starts with `sk-...`)
6. Set **Model Name** to `gpt-4o`
7. Set **Max Tokens** to `4096`
8. **Save**

> The same `ApiKey__c` also powers the optional Account-summary Company Overview
> (Step 4d) — no extra key needed, as long as the key's account can use a
> search-capable model.

### Via Metadata Deploy (for scratch orgs / CI — never commit real keys)

Edit `force-app/main/default/customMetadata/AI_Config.Default.md-meta.xml`:

```xml
<values>
    <field>ApiKey__c</field>
    <value xsi:type="xsd:string">sk-YOUR-REAL-KEY-HERE</value>
</values>
<values>
    <field>ModelName__c</field>
    <value xsi:type="xsd:string">gpt-4o</value>
</values>
<values>
    <field>MaxTokens__c</field>
    <value xsi:type="xsd:double">4096</value>
</values>
```

Then re-deploy. **Never commit real API keys to source control.**

---

## Step 6 — Add the Component to Lightning Pages

### Activity Timeline (Account pages)

`lnchatActivityTimeline` is a standalone component that renders a horizontal,
clustered activity timeline (Tasks + Events) at the top of an Account page, with a
TODAY marker, an engagement-coverage bar, and click-to-open popovers listing each
activity and its source.

1. Open any **Account** record → gear ⚙ → **Edit Page**
2. Drag **lnchat Activity Timeline** to the **top** region of the page
3. **Save** → **Activate** for Account pages

> Source labels (Gong / SalesLoft) appear only in orgs that have those managed
> packages; elsewhere every activity reads "Salesforce". No configuration needed —
> it reads Tasks/Events related to the account automatically.

### Method A — lnchatDrawer via App Builder (Recommended)

`lnchatDrawer` is a floating action button (FAB) component that slides open a full-height drawer panel. It can be placed on any Lightning page without utility bar configuration.

1. Navigate to any **Account** record → click the gear ⚙ → **Edit Page**
2. In Lightning App Builder, drag **lnchat Drawer** from the component list to any page region (it renders as a fixed FAB — placement on the canvas doesn't affect visual position)
3. **Save** → **Activate** → assign as org default for Account pages
4. Repeat for **Opportunity**, **Contact**, **Case**, and **Lead** record pages

### Method B — lnchatShell in the Utility Bar (Alternative)

> Note: The FlexiPage XML (`AI_Assistant_UtilityBar.flexipage-meta.xml`) is in
> `.forceignore` and cannot be deployed via CLI due to a Salesforce platform
> limitation. The utility bar item must be configured via App Manager UI.

1. Go to **Setup → App Manager**
2. Find your Lightning App (e.g., **Sales** or **AI Assistant**) → **Edit**
3. Click **Utility Items (Desktop Only)** in the left nav
4. Click **Add Utility Item**
5. Search for and select **lnchatShell** (label: AI Assistant)
6. Configure:
   - **Label**: `AI Assistant`
   - **Icon**: `einstein`
   - **Panel Width**: `420`
   - **Panel Height**: `580`
   - **Start Opened**: `false`
7. **Save**

---

## Step 7 — Assign Required Permissions

Users need:

- Read/Write access to **LNChatSession\_\_c** and **LNChatMessage\_\_c**
- Read access to the target objects (Account, Opportunity, etc.)
- Access to the **LNChatController** Apex class

Create a Permission Set:

1. **Setup → Permission Sets → New**
2. Name: `AI Chatbot User`
3. Add:
   - **Apex Class Access**: `LNChatController`
   - **Object Settings**: `LNChatSession__c` (Read, Create, Edit), `LNChatMessage__c` (Read, Create, Edit, Delete)
4. Assign to target users

---

## Step 8 — Customize LNChatERPService for Your API

The ERP service is a template. Adapt `LNChatERPService.cls`:

```apex
public Map<String, Object> getRecordData(String externalId) {
    HttpRequest req = new HttpRequest();
    // Change endpoint path to match your ERP's API
    req.setEndpoint(NAMED_CREDENTIAL + '/api/v2/accounts/' + externalId);
    req.setMethod('GET');
    // Add custom headers if needed:
    req.setHeader('X-Tenant-ID', 'your-tenant');
    // ...rest of method unchanged
}
```

The method must return a `Map<String, Object>`. The LLM receives the raw map
serialized as JSON, so include any fields relevant to your business context.

---

## Step 9 — Customize LNChatBIService for Your API

Similarly adapt `LNChatBIService.cls`:

```apex
req.setEndpoint(NAMED_CREDENTIAL + '/v1/metrics/' + externalId + '?period=YTD');
```

---

## Architecture Notes

### Data Flow

```
User types message (optionally attaches file)
  → lnchatInput fires 'messagesend' event with { message, attachment }
  → lnchatShell.handleMessageSend()
  → LNChatController.sendMessage() [Apex — 5 params incl. attachmentJson]
    → LNChatContextBuilderService.buildContext()
        → SOQL: dynamic query on current object + related records
          (open opps, non-closed cases, incomplete tasks — LIMIT 5 each)
        → LNChatERPService.getRecordData() [HTTP callout]
        → LNChatBIService.getMetrics() [HTTP callout]
    → LNChatLLMService.chat() [HTTP callout to OpenAI]
      → POST /v1/chat/completions with system prompt + context + history + attachment
    → LNChatResponseDTO.fromJson(response)
    → Save LNChatMessage__c records (DML — AFTER all callouts)
  → Returns structured JSON to LWC
  → lnchatHistory renders via lnchatResponseRenderer
  → lnchatResponseRenderer picks correct visual component by responseType
```

### Callout Limits

Each message send makes **3 HTTP callouts** (ERP + BI + OpenAI). Salesforce
allows 100 callouts per transaction. If you add more external services, ensure
you stay within limits.

### Callout-Before-DML (Critical)

All HTTP callouts (ERP, BI, OpenAI) must complete **before** any DML
(session create/update, message save). Salesforce forbids callouts after DML
in the same transaction.

### Governor Limits

- SOQL queries: The dynamic field query in `LNChatContextBuilderService` may return
  many fields. For objects with 500+ fields, consider adding a field whitelist.
- Heap size: Large context payloads (ERP + BI) are serialized to JSON and passed
  to the LLM. Monitor heap usage if payloads exceed ~50KB.

---

## API Version Dependencies

| Component                              | Minimum API Version |
| -------------------------------------- | ------------------- |
| All Apex classes                       | 62.0                |
| All LWC components                     | 62.0                |
| `lightning/navigation` NavigationMixin | 44.0+               |
| `lightning/platformResourceLoader`     | 40.0+               |
| `@wire(CurrentPageReference)`          | 47.0+               |
| Custom Metadata Type                   | 40.0+               |

Target API: **62.0** (Winter '25)

---

## Troubleshooting

### "OpenAI API key not configured in AI_Config\_\_mdt"

→ Ensure the `AI_Config__mdt` `Default` record exists and has `ApiKey__c` populated.
This record is **not deployed** (excluded via `.forceignore`) — create it manually
via Setup → Custom Metadata Types → AI Config → Manage Records.

### Empty AI response / blank response box

→ `MaxTokens__c` is set too low. Set it to **4096** in AI_Config\_\_mdt.
Values ≤ 2000 cause `finish_reason: length` for large record contexts.

### Chat panel appears completely blank (no chips, no messages)

→ Deploy may have succeeded but the component was previously renamed.
All `querySelector` string literals in `lnchatShell.js` must use `'c-lnchat-history'`
(not `'c-chatbot-history'`). Verify the deployed JS matches the source.

### Chart does not render

→ Verify the `chartjs` static resource is deployed and contains valid JS.
In browser DevTools, check the Network tab for the resource load.
You may need to add `cdn.jsdelivr.net` to CSP Trusted Sites if using a CDN copy.

### External system returns empty data

→ Check Named Credential URLs and auth config.
The chatbot degrades gracefully — it will still respond using Salesforce data only.

### "Too many callouts" error

→ If you added additional external services, you may exceed the 100-callout limit.
Consider combining ERP and BI into a single aggregator service.

### 503 error on file upload / PDF analysis

→ OpenAI 503 errors are usually transient. Retry the request.
For large PDFs with broad prompts ("extract all content"), the payload may be
very large — use more specific prompts to reduce response size.

### History not loading on page navigation

→ Ensure `LNChatController.getConversationHistory` is accessible (Apex class access
in the assigned Permission Set).

---

## Security Checklist

- [ ] API key stored in Custom Metadata, not in code or Named Credential
- [ ] Named Credentials used for all external callouts — no hardcoded URLs
- [ ] `with sharing` on all Apex classes — respects record-level security
- [ ] Input sanitized server-side (Apex auto-escapes SOQL bind variables)
- [ ] LWC renders AI response as structured data, not as raw HTML — no XSS risk
- [ ] Conversation messages stored with standard Salesforce sharing model
- [ ] `AI_Config.Default.md-meta.xml` in `.forceignore` — API key never committed to source control
