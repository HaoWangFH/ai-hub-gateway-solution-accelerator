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
4. **Azure Event Hubs & App Insights:** Used asynchronously by the gateway to stream usage data (tokens used, models requested) without adding latency to the client's request. *(Note Gap: While the gateway successfully emits all telemetry to the Event Hub, a downstream consumer—such as an Azure Function or Stream Analytics—is required to pull this data from Event Hubs into Cosmos DB for the final dashboard. This consumer is outside the scope of the core gateway deployment.)*
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
