# AI Hub Gateway: Executive Brief & High-Level Guidance

## 1. Overview & Current State (MVP)
The **AI Hub Gateway (Citadel v1)** has been successfully deployed to the existing `apim-eist-dev` API Management instance as a Minimum Viable Product (MVP). 

The gateway acts as a centralized, highly-available entry point for all enterprise AI traffic. By decoupling the client applications from the underlying AI providers, the gateway allows the organization to seamlessly switch, upgrade, and load-balance AI models behind the scenes without breaking client code. 

**Current MVP Scope:** Core API routing, advanced load-balancing, and usage telemetry are fully active. Advanced compliance features (PII anonymization) and Entra ID (OAuth) authentication have been intentionally deferred to future phases to accelerate initial adoption.

---

## 2. Supported Features
* **Universal API Interface:** Exposes the `Unified AI API`, a 100% drop-in replacement for standard OpenAI SDKs (`/v1/chat/completions`). Clients do not need to learn new SDKs to access Claude, Gemini, or Azure OpenAI.
* **Intelligent Load Balancing:** Distributes traffic across multiple AI servers using proportional "Weights" to prevent any single server from being overwhelmed.
* **Active/Passive Failover:** Uses priority tiers to automatically failover to backup servers (or alternate regions) if the primary AI endpoint goes down or hits rate limits.
* **A/B Testing (Model Aliasing):** Supports "Virtual Models" (e.g., `corporate-gpt`). The gateway can dynamically split traffic (e.g., 80% to GPT-4, 20% to GPT-4o) to test new models safely.
* **Cross-Provider Translation:** Automatically intercepts client requests and translates them into native Anthropic, Google Gemini, or Azure AI Foundry formats on the fly.
* **Centralized Telemetry:** Captures comprehensive token usage and latency metrics via Event Hubs for chargeback and monitoring.

---

## 3. High-Level Architecture & Components
1. **Azure API Management (APIM):** The core engine. It executes XML/C# policies to intercept payloads, resolve model names, rewrite bodies, and route traffic. 
2. **Virtual Network (VNet):** The gateway is injected into an internal VNet, ensuring all traffic remains private and secure from the public internet.
3. **Backend Pools (Native APIM):** Dynamic groups of AI servers (e.g., `gpt-4o-pool`) that handle the load balancing math.
4. **Azure Event Hubs & App Insights:** Used asynchronously by the gateway to stream usage data (tokens used, models requested) without adding latency to the client's request. *(Note: While the core gateway deployment only emits to Event Hubs, the Citadel framework provides a pre-built **Azure Logic App** in the `supporting-services.bicep` deployment that automatically pulls this data from Event Hubs into Cosmos DB for dashboarding.)*
5. **Managed Identity (UAMI):** Allows the gateway to securely authenticate to internal Azure AI services without hardcoding API keys.

---

## 4. The Business Workflow (End-to-End)

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

## 5. Feature Status (MVP vs Full Framework)
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
