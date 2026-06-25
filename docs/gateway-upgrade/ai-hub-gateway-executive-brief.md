# AI Hub Gateway: Executive Brief & High-Level Guidance

## 1. Overview & Current State (MVP)
The **AI Hub Gateway (Citadel v1)** has been successfully deployed to the existing `apim-eist-dev` API Management instance as a Minimum Viable Product (MVP). 

The gateway acts as a centralized, highly-available entry point for all enterprise AI traffic. By decoupling the client applications from the underlying AI providers, the gateway allows the organization to seamlessly switch, upgrade, and load-balance AI models behind the scenes without breaking client code. 

**Deployment Background (The Two Major Scripts):**
The architecture is deployed via two primary Bicep scripts that separate the gateway configuration from its surrounding ecosystem:
1. **`bicep/infra/apim-gateway-upgrade/supporting-services.bicep`**: Provisions the surrounding governance ecosystem (e.g., Cosmos DB for dashboards, Logic Apps, Key Vault, and AI Content Safety endpoints).
2. **`bicep/infra/apim-gateway-upgrade/main.bicep`**: Configures the actual API Management instance itself (e.g., APIs, routing policies, backend pools, and named values). This script assumes the supporting services already exist.

**Current MVP Scope:** Core API routing, advanced load-balancing, and usage telemetry are fully active via the `bicep/infra/apim-gateway-upgrade/main.bicep` deployment. The `bicep/infra/apim-gateway-upgrade/supporting-services.bicep` ecosystem (PII anonymization, Cosmos DB dashboards) and Entra ID (OAuth) authentication have been intentionally deferred to future phases to accelerate initial MVP adoption.

---

## 2. Supported Features
* **Universal API Interface:** Exposes the `Unified AI API`, a 100% drop-in replacement for standard OpenAI SDKs (`/v1/chat/completions`). Clients do not need to learn new SDKs to access Claude, Gemini, or Azure OpenAI.
* **Intelligent Load Balancing:** Distributes traffic across multiple AI servers using proportional "Weights" to prevent any single server from being overwhelmed.
* **Active/Passive Failover:** Uses priority tiers to automatically failover to backup servers (or alternate regions) if the primary AI endpoint goes down or hits rate limits.
* **A/B Testing (Model Aliasing):** Supports "Virtual Models" (e.g., `corporate-gpt`). The gateway can dynamically split traffic (e.g., 80% to GPT-4, 20% to GPT-4o) to test new models safely.
* **Cross-Provider Translation:** Automatically intercepts client requests and translates them into native Anthropic, Google Gemini, or Azure AI Foundry formats on the fly.
* **Centralized Telemetry:** Captures comprehensive token usage and latency metrics via Event Hubs for chargeback and monitoring.

---

## 3. Available API Surfaces (How Clients Connect)
The Gateway exposes three distinct API surfaces simultaneously. You do not have to pick just one; they exist side-by-side to serve different use cases:

1. **Unified AI API (Recommended):** Perfect mimic of the standard OpenAI `v1` REST API. Clients can use standard off-the-shelf OpenAI Python/Node SDKs. The Gateway automatically translates these requests to Anthropic, Gemini, or Azure formats behind the scenes.
2. **Azure OpenAI API (Legacy Compatibility):** Perfect mimic of the proprietary Azure OpenAI REST API. This ensures internal legacy applications that are strictly hardcoded to the Azure SDK can switch to the Gateway with zero code rewrites or downtime.
3. **Universal LLM API (Explicit Control):** An older translation pattern that requires the client to explicitly name the backend in the URL. Useful for power-users who want to completely bypass the load balancer and manually select their own backend server.

---

## 4. High-Level Architecture & Components
1. **Azure API Management (APIM):** The core engine. It executes XML/C# policies to intercept payloads, resolve model names, rewrite bodies, and route traffic. 
2. **Virtual Network (VNet):** The gateway is injected into an internal VNet, ensuring all traffic remains private and secure from the public internet.
3. **Backend Pools (Native APIM):** Dynamic groups of AI servers (e.g., `gpt-4o-pool`) that handle the load balancing math.
4. **Azure Event Hubs & App Insights:** Used asynchronously by the gateway to stream usage data (tokens used, models requested) without adding latency to the client's request. *(Note: While the core gateway deployment only emits to Event Hubs, the Citadel framework provides a pre-built **Azure Logic App** in the `supporting-services.bicep` deployment that automatically pulls this data from Event Hubs into Cosmos DB for dashboarding.)*
5. **Managed Identity (UAMI):** Allows the gateway to securely authenticate to internal Azure AI services without hardcoding API keys.

---

## 5. Policy Fragments (The Core Logic)
The absolute heart of the APIM gateway's intelligence relies on **Policy Fragments**. These are reusable snippets of XML and C# code that act like centralized functions. Instead of copying and pasting the same logic into every API, the Gateway defines them once, ensuring universal consistency:
* **The Router (`frag-set-target-backend-pool`):** This fragment executes on every request. It reads the requested model, resolves any Virtual Aliases (executing A/B testing math if needed), and instructs APIM which backend pool to route the traffic to.
* **The Authenticator (`frag-set-backend-authorization`):** Once routed, this fragment determines how to unlock the target backend. It either generates an Entra ID token via Managed Identity (for Azure endpoints) or injects a secure API Key from APIM's Named Values (for Anthropic/Gemini).

---

## 6. The Business Workflow (End-to-End)

The lifecycle of operating the AI Hub Gateway is divided into two distinct onboarding motions:

### Phase A: Onboarding AI Providers (Bringing "Brains" to the Hub)
1. **Gather Intelligence:** An external or internal team provisions an AI endpoint (e.g., Azure AI Foundry, AWS Bedrock, or vLLM). They provide their Base URL, Authentication Method, and Allocated Capacity to the Gateway Operators.
2. **Configure Routing:** The Gateway Operators add this endpoint to the Bicep template (`main-eist-dev.bicepparam`), assigning it a mathematical **Weight** based on its capacity.
3. **Deploy:** The Bicep template is deployed via Azure CLI. APIM automatically creates Backend Pools and wires the new AI server into the load balancer.

### Phase B: Onboarding Clients (Granting Access to Applications)
1. **Create APIM Product:** The Gateway Operators group the APIs into a "Product" (e.g., `Alpha-Tier-Product`) and attach rate limits (e.g., 10,000 Tokens Per Minute).
2. **Generate Credentials:** An APIM Subscription Key is generated and securely handed to the client application developers.
3. **Client Integration:** The client developers point their standard Python/Node `OpenAI` SDK to the Gateway's URL and pass in the Subscription Key. The gateway immediately begins routing their traffic to the best available AI backend!

---

## 7. Feature Status (MVP vs Full Framework)
The following table outlines the capabilities of the full Citadel framework compared to the current MVP deployment (verified in Azure on `apim-eist-dev`):

| Feature Category | Full Citadel Framework | Your Bare MVP Deployment | Notes on MVP State |
| :--- | :--- | :--- | :--- |
| **Universal API Routing** | ✅ Yes | ✅ **Yes** | Fully active. |
| **Smart Load Balancing** | ✅ Yes | ✅ **Yes** | Fully active (Native APIM Backend Pools). |
| **Model Aliasing (A/B Testing)** | ✅ Yes | ✅ **Yes** | Fully active (C# Virtual Pools). |
| **Backend Authentication** | ✅ Yes | ✅ **Yes** | Active via `mi-EIST-apim-dev` Managed Identity. |
| **Telemetry Emission** | ✅ Yes | ⚠️ **Partial** | Emitting to `evhns-eist-apim-dev` Event Hubs namespace. |
| **Usage Dashboards (Cosmos DB)**| ✅ Yes | ❌ **No** | Cosmos DB resource does not exist in Azure. Requires `supporting-services.bicep`. |
| **Client Authentication** | ✅ Entra ID (OAuth) | ⚠️ **Sub Key Only** | JWT named values are set to `not-configured`. |
| **PII Anonymization** | ✅ Yes | ❌ **No** | Policy named values set to `https://placeholder.com`. |
| **Content Safety Filtering** | ✅ Yes | ❌ **No** | Policy named values set to `https://placeholder.com`. |
| **Semantic Caching** | ✅ Yes | ❌ **No** | Redis Cache resource does not exist in Azure. |

---

## 8. Component/Resource Status (MVP vs Full Framework)
The following table compares the high-level Azure infrastructure components required for the full Citadel framework against what is currently provisioned for this bare MVP deployment.

| High-Level Azure Component | Full Citadel Framework | Your Bare MVP Deployment | Purpose |
| :--- | :--- | :--- | :--- |
| **Azure API Management (APIM)** | ✅ Yes | ✅ **Yes** | Core gateway routing engine and load balancer. |
| **User-Assigned Managed Identity** | ✅ Yes | ✅ **Yes** | Secures access to backend AI services. |
| **Azure Event Hubs** | ✅ Yes | ✅ **Yes** | High-throughput streaming of raw usage telemetry. |
| **App Insights & Log Analytics** | ✅ Yes | ✅ **Yes** | Monitoring, logs, and gateway health metrics. |
| **Azure Cosmos DB** | ✅ Yes | ❌ **No** | Permanent storage for chargeback metrics and PowerBI dashboards. |
| **Azure Logic App** | ✅ Yes | ❌ **No** | Data processor that moves telemetry from Event Hubs to Cosmos DB. |
| **Azure AI Services (Foundry)** | ✅ Yes | ❌ **No** | Provides Language (PII) and Content Safety (Abuse) endpoints. |
| **Azure Managed Redis** | ✅ Yes | ❌ **No** | High-performance semantic caching for repeated prompts. |
| **Azure Key Vault** | ✅ Yes | ❌ **No** | Secure storage for external provider API keys (currently stored in APIM Named Values). |

---

## 9. Future Enterprise Scaling Strategy
While the current manual Standard Operating Procedure (SOP) is effective for the MVP, scaling across a large enterprise requires tracking, governance, and self-service. The following architectural processes are recommended for the next phase:

### 1. Shift to "GitOps" via Pull Requests (For Onboarding Providers)
* **The Process:** When an external team wants to onboard a new AI server, they submit a **Pull Request (PR)** modifying the `bicep/infra/apim-gateway-upgrade/main-eist-dev.bicepparam` file to add their endpoint and requested Weight.
* **The Benefit:** Provides a perfect audit trail and requires a mandatory code review (Approval) from a Gateway Operator. Once approved, a CI/CD pipeline (e.g., GitHub Actions or Azure DevOps) automatically deploys the script.

### 2. Enable the APIM Developer Portal (For Onboarding Clients)
* **The Process:** Direct client developers to the built-in APIM Developer Portal instead of manually emailing them Subscription Keys.
* **The Benefit:** Clients log in using their corporate Entra ID, interactively read the API documentation, and click to "Subscribe" to the AI Product. Upon approval, they instantly get their keys on a secure dashboard.

### 3. Implement an ITSM Front-Door (ServiceNow / Jira)
* **The Process:** External teams fill out a standardized request form in an IT Service Management tool to either "Provide a Model" or "Consume a Model".
* **The Benefit:** Routes through standard corporate approval workflows. It can also be integrated with Azure Logic Apps to automatically trigger the APIM subscription creation once approved by a manager.
