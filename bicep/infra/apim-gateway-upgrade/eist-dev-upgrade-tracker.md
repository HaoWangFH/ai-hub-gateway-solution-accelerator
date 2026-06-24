# EIST DEV — APIM Gateway Upgrade Tracker

**Target APIM:** `apim-eist-dev`  
**Resource Group:** `RG-EIST-APIM-dev`  
**Subscription:** `8ec4d8c8-09af-4f21-8d34-2caa6384fe4e`  
**Tenant:** `healthbc.onmicrosoft.com`  
**Started:** 2026-06-22  

---

## Environment Assessment (Completed)

| Check | Value | Status |
|---|---|---|
| APIM provisioning state | Succeeded | ✅ |
| SKU | Developer | ✅ |
| Location | Canada Central | ✅ |
| `azuremonitor` logger | Exists | ✅ |
| App Insights logger | `appi-eist-apim-dev` (name mismatch) | ⚠️ |
| UAMI | `mi-EIST-apim-dev` | ✅ |
| VNet type | Internal | ⚠️ Backends must be VNet-reachable |

**Key constraints identified:**
- App Insights logger named `appi-eist-apim-dev` (not `appinsights-logger`) → `updateAppInsightsDiagnostics = false`
- VNet Internal mode → all LLM backend endpoints must be accessible from within the VNet

---

## Step 1 — First Deployment: APIs + Policy Framework

**Param file:** `main-eist-dev.bicepparam`  
**Status:** ❌ Failed — see Step 1a for required pre-flight fixes

### Failure Analysis

| Fragment | Error | Root Cause |
|---|---|---|
| `policyFragments/ai-usage` | `Logger not found: usage-eventhub-logger` | Fragment XML unconditionally references this logger; upgrade path never creates it (only full `apim.bicep` does); `apim-eist-dev` has no Event Hub logger |
| `policyFragments/pii-anonymization` | `Cannot find property 'uami-client-id'` and `'piiServiceUrl'` | Fragment is deployed unconditionally even when `enablePIIAnonymization = false`; named values missing because `updateNamedValues = false`; `piiServiceUrl` only gets created when BOTH `updateNamedValues = true` AND `enablePIIAnonymization = true` |

**Both errors block all policy fragment and API deployments.**

---

## Step 1a — Pre-flight: Create Missing Prerequisites (Run Once)

These steps must complete before re-running Step 1.

### Part A — Pre-create Named Values (fixes `pii-anonymization` fragment)

```powershell
az account set --subscription "8ec4d8c8-09af-4f21-8d34-2caa6384fe4e"

# 1. Get UAMI client ID
$uamiClientId = az identity show `
  --name mi-EIST-apim-dev `
  --resource-group RG-EIST-APIM-dev `
  --query clientId -o tsv
Write-Host "UAMI client ID: $uamiClientId"

# 2. Create uami-client-id named value
$uamiBody = @"
{
  "properties": {
    "displayName": "uami-client-id",
    "secret": true,
    "value": "$uamiClientId"
  }
}
"@
az rest --method put `
  --url "https://management.azure.com/subscriptions/8ec4d8c8-09af-4f21-8d34-2caa6384fe4e/resourceGroups/RG-EIST-APIM-dev/providers/Microsoft.ApiManagement/service/apim-eist-dev/namedValues/uami-client-id?api-version=2022-08-01" `
  --body $uamiBody

# 3. Create piiServiceUrl named value (empty placeholder — PII not configured yet)
az rest --method put `
  --url "https://management.azure.com/subscriptions/8ec4d8c8-09af-4f21-8d34-2caa6384fe4e/resourceGroups/RG-EIST-APIM-dev/providers/Microsoft.ApiManagement/service/apim-eist-dev/namedValues/piiServiceUrl?api-version=2022-08-01" `
  --body '{"properties":{"displayName":"piiServiceUrl","secret":false,"value":""}}'
```

### Part B — Provision Event Hub (fixes `ai-usage` fragment)

```powershell
# 1. Create Event Hub namespace
az eventhubs namespace create `
  --name evhns-eist-apim-dev `
  --resource-group RG-EIST-APIM-dev `
  --location canadacentral `
  --sku Standard

# 2. Create the ai-usage event hub inside it
az eventhubs eventhub create `
  --name ai-usage `
  --namespace-name evhns-eist-apim-dev `
  --resource-group RG-EIST-APIM-dev `
  --message-retention 7 `
  --partition-count 4

# 3. Get namespace resource ID for RBAC
$ehNamespaceId = az eventhubs namespace show `
  --name evhns-eist-apim-dev `
  --resource-group RG-EIST-APIM-dev `
  --query id -o tsv

# 4. Get UAMI principal ID for RBAC
$uamiPrincipalId = az identity show `
  --name mi-EIST-apim-dev `
  --resource-group RG-EIST-APIM-dev `
  --query principalId -o tsv

# 5. Assign Event Hubs Data Sender role to UAMI
az role assignment create `
  --role "Azure Event Hubs Data Sender" `
  --assignee-object-id $uamiPrincipalId `
  --assignee-principal-type ServicePrincipal `
  --scope $ehNamespaceId
```

### Part C — Create APIM Event Hub Logger (fixes `ai-usage` fragment)

```powershell
# Get UAMI client ID (if not already set from Part A)
$uamiClientId = az identity show `
  --name mi-EIST-apim-dev `
  --resource-group RG-EIST-APIM-dev `
  --query clientId -o tsv

# Create usage-eventhub-logger on apim-eist-dev
$loggerBody = @"
{
  "properties": {
    "loggerType": "azureEventHub",
    "description": "Event Hub logger for OpenAI usage metrics",
    "credentials": {
      "name": "ai-usage",
      "endpointAddress": "evhns-eist-apim-dev.servicebus.windows.net:443/",
      "identityClientId": "$uamiClientId"
    }
  }
}
"@
az rest --method put `
  --url "https://management.azure.com/subscriptions/8ec4d8c8-09af-4f21-8d34-2caa6384fe4e/resourceGroups/RG-EIST-APIM-dev/providers/Microsoft.ApiManagement/service/apim-eist-dev/loggers/usage-eventhub-logger?api-version=2022-08-01" `
  --body $loggerBody

# Verify logger was created
az rest --method get `
  --url "https://management.azure.com/subscriptions/8ec4d8c8-09af-4f21-8d34-2caa6384fe4e/resourceGroups/RG-EIST-APIM-dev/providers/Microsoft.ApiManagement/service/apim-eist-dev/loggers/usage-eventhub-logger?api-version=2022-08-01" `
  --query "properties.loggerType" -o tsv
```

> **Expected output:** `azureEventHub`

### Part D — Re-run Step 1 Deployment

After Parts A–C are complete:

```powershell
az account set --subscription "8ec4d8c8-09af-4f21-8d34-2caa6384fe4e"

az deployment group create `
  --name gateway-upgrade-eist-dev-$(Get-Date -Format "yyyyMMddHHmm") `
  --resource-group RG-EIST-APIM-dev `
  --template-file bicep/infra/apim-gateway-upgrade/main.bicep `
  --parameters bicep/infra/apim-gateway-upgrade/main-eist-dev.bicepparam
```

**What this deploys (updated param file):**
- [x] Named values: `uami-client-id`, `contentSafetyServiceUrl` (empty placeholder), JWT slots
- [x] Static policy fragments (all — including `ai-usage`, `pii-anonymization`, `security-handler`, etc.)
- [x] `universal-llm-api` + OpenAPI spec + policies
- [x] `azure-openai-api` + OpenAPI spec + policies
- [x] `unified-ai-wildcard-api` + product + policies
- [ ] ~~LLM backends~~ — skipped, VNet connectivity not verified
- [ ] ~~App Insights diagnostics~~ — skipped, logger name mismatch
- [ ] ~~PII named values~~ — piiServiceUrl pre-created as placeholder; actual URL configured in Step 4

**Verify deployment:**
```powershell
# Check deployment status
az deployment group show `
  --resource-group RG-EIST-APIM-dev `
  --name <deployment-name-from-above> `
  --query "{Status:properties.provisioningState, Duration:properties.duration}" -o table

# Verify APIs were created
az rest --method get `
  --url "https://management.azure.com/subscriptions/8ec4d8c8-09af-4f21-8d34-2caa6384fe4e/resourceGroups/RG-EIST-APIM-dev/providers/Microsoft.ApiManagement/service/apim-eist-dev/apis?api-version=2022-08-01" `
  --query "value[].name" -o table

# Verify policy fragments were created
az rest --method get `
  --url "https://management.azure.com/subscriptions/8ec4d8c8-09af-4f21-8d34-2caa6384fe4e/resourceGroups/RG-EIST-APIM-dev/providers/Microsoft.ApiManagement/service/apim-eist-dev/policyFragments?api-version=2022-08-01" `
  --query "value[].name" -o table
```

**Expected APIs after successful deployment:**
- `universal-llm-api`
- `azure-openai-api`
- `unified-ai-wildcard-api`

**Expected policy fragments (minimum):**
- `ai-usage`, `pii-anonymization`, `pii-deanonymization`, `raise-throttling-events`
- `security-handler`, `resolve-model-alias`, `strip-backend-headers`
- `central-cache-manager`, `request-processor`, `path-builder`, `set-response-headers`

---

## Step 2 — Verify VNet Connectivity to LLM Endpoints

**Status:** ⏳ Pending

Before onboarding any backends, confirm that your target LLM endpoints
are reachable from within the `apim-eist-dev` Internal VNet.

**Questions to answer:**
- [ ] What LLM endpoints do you want to route to? (AI Foundry, Azure OpenAI, external?)
- [ ] Are those endpoints exposed via private endpoint into the same VNet?
- [ ] Or does the VNet have outbound internet access to reach public endpoints?

**Test connectivity (from a VM inside the VNet):**
```bash
curl -I https://<your-foundry-or-aoai-endpoint>.cognitiveservices.azure.com/
```

---

## Step 3 — Onboard LLM Backends

**Status:** ⏳ Pending — depends on Step 2

**Option A: Via upgrade param file** (update `main-eist-dev.bicepparam`)
```bicep
param updateLLMBackends        = true
param updateLLMBackendPools    = true
param updateLLMPolicyFragments = true

param llmBackendConfig = [
  {
    backendId: 'aif-eist-dev-0'
    backendType: 'ai-foundry'                          // or 'azure-openai'
    endpoint: 'https://<your-endpoint>.cognitiveservices.azure.com/'
    authType: 'managed-identity'
    priority: 1
    weight: 100
    supportedModels: [
      { name: 'gpt-4o', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '2024-11-20', retirementDate: '2026-09-30' }
    ]
  }
]
```

**Option B: Via llm-backend-onboarding package** (recommended for ongoing adds)
```powershell
az deployment sub create `
  --name llm-backend-eist-dev `
  --location canadacentral `
  --template-file bicep/infra/llm-backend-onboarding/main.bicep `
  --parameters bicep/infra/llm-backend-onboarding/<your-param-file>.bicepparam
```

**RBAC required on LLM endpoints:**
- AI Foundry: `Cognitive Services User` on the Foundry resource for `mi-EIST-apim-dev`
- Azure OpenAI: `Cognitive Services OpenAI User` for `mi-EIST-apim-dev`

---

## Step 4 — Configure PII & Content Safety

**Status:** ⏳ Pending — requires AI Foundry / Language Service endpoint

Update `main-eist-dev.bicepparam`:
```bicep
param updateNamedValues       = true
param enablePIIAnonymization  = true
param aiLanguageServiceUrl    = 'https://<your-foundry>.cognitiveservices.azure.com/'
param contentSafetyServiceUrl = 'https://<your-foundry>.cognitiveservices.azure.com/'
```

Re-run the deployment:
```powershell
az deployment group create `
  --name gateway-upgrade-eist-dev-namedvalues-$(Get-Date -Format "yyyyMMddHHmm") `
  --resource-group RG-EIST-APIM-dev `
  --template-file bicep/infra/apim-gateway-upgrade/main.bicep `
  --parameters bicep/infra/apim-gateway-upgrade/main-eist-dev.bicepparam
```

---

## Step 5 — Configure JWT / Entra ID Authentication (Optional)

**Status:** ⏳ Pending — optional, enable per access contract

Run the setup script (after Key Vault is available):
```powershell
cd bicep/infra/entra-id-setup
pwsh ./setup.ps1 `
  -KeyVaultName "<your-kv>" `
  -ApimResourceGroup "RG-EIST-APIM-dev" `
  -ApimName "apim-eist-dev"
```

Then in `main-eist-dev.bicepparam`:
```bicep
param enableJwtAuth          = true
param jwtTenantId            = '<tenant-id>'
param jwtAppRegistrationId   = '<app-reg-client-id>'
```

---

## Step 6 — Create Access Contracts (Use Case Onboarding)

**Status:** ⏳ Pending — depends on Steps 3 + 4

One deployment per use case / team. Template:
```powershell
az deployment sub create `
  --name <usecase>-dev-contract `
  --location canadacentral `
  --template-file bicep/infra/citadel-access-contracts/main.bicep `
  --parameters bicep/infra/citadel-access-contracts/contracts/<bu-usecase>/dev/main.bicepparam
```

Creates per use case:
- APIM Product (`<ServiceCode>-<BU>-<UseCase>-DEV`)
- APIM Subscription + API key
- Key Vault secrets (optional)
- Microsoft Foundry connection (optional)

---

## Step 7 — Validate End-to-End

**Status:** ⏳ Pending — after Steps 3–6

```powershell
# Confirm APIs exist
az apim api list -n apim-eist-dev -g RG-EIST-APIM-dev --query "[].name" -o table

# Confirm backends exist
az rest --method get \
  --url "https://management.azure.com/subscriptions/8ec4d8c8-09af-4f21-8d34-2caa6384fe4e/resourceGroups/RG-EIST-APIM-dev/providers/Microsoft.ApiManagement/service/apim-eist-dev/backends?api-version=2022-08-01" \
  --query "value[].{Name:name, Url:properties.url}" -o table

# Test a request via subscription key
curl -X POST https://apim-eist-dev.azure-api.net/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-15-preview \
  -H "api-key: <subscription-key>" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"hello"}]}'
```

Use the validation notebooks:
- `validation/citadel-unified-ai-api-tests.ipynb`
- `validation/citadel-agent-frameworks-tests.ipynb`

---

## Progress Summary

| Step | Description | Status |
|---|---|---|
| 0 | Environment assessment | ✅ Done |
| 1a | Pre-flight: Create Event Hub logger + named value placeholders | ⏳ Pending |
| 1 | APIs + policy framework deployment | ❌ Failed — re-run after Step 1a |
| 2 | Verify VNet connectivity to LLM endpoints | ⏳ Pending |
| 3 | Onboard LLM backends | ⏳ Pending |
| 4 | Configure PII & Content Safety named values | ⏳ Pending |
| 5 | JWT / Entra ID authentication (optional) | ⏳ Pending |
| 6 | Create access contracts | ⏳ Pending |
| 7 | End-to-end validation | ⏳ Pending |
