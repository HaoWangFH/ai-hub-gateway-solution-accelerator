# AI Hub Gateway: Load Balancing Architecture

This document officially outlines the load balancing and traffic routing architecture for the Citadel v1 AI Hub Gateway. It details how the Bicep configuration translates into Azure API Management (APIM) native Backend Pools.

---

## 1. Core Concepts

### Priority (Active vs. Passive Failover)
* **Definition:** Priority dictates the "tier" of the backend. Lower numbers mean higher priority (Priority 1 is the primary tier).
* **Behavior:** APIM will **only** send traffic to Priority 1 backends. If (and only if) all Priority 1 backends fail or timeout, APIM will automatically fail over to Priority 2 backends.

### Weight (Traffic Distribution)
* **Definition:** Weight is used to proportionally distribute traffic across multiple backends that share the *same* priority level.
* **Behavior:** If two Priority 1 backends exist with weights of `100` and `200`, the APIM gateway calculates their total pool weight (300). The first backend receives 33% (100/300) of traffic, and the second receives 67% (200/300).
* **Scope:** The weight is applied at the **Backend Server / Endpoint** level, not the individual model level.

---

## 2. The Bicep Generation Logic (`llm-backend-pools.bicep`)

The Citadel framework completely automates the creation of APIM Backend Pools. You do not configure pools manually. Instead, you define individual endpoints in the `llmBackendConfig` array in your `.bicepparam` file.

The `llm-backend-pools.bicep` module processes this array using the following logic:

### Step A: Model Extraction
The module parses the `supportedModels` array for every endpoint. It extracts the model `name` (e.g., `gpt-4o`).

### Step B: The Grouping Matrix
The module creates a composite key for every model and backend type combination: `[ModelName]||[BackendType]`. 

If it detects that **multiple** backend endpoints host the exact same `ModelName` and `BackendType` (for example, two different Azure OpenAI instances both hosting `gpt-4o`), it triggers the creation of an APIM Backend Pool.

### Step C: Pool Generation
A new Azure API Management Backend resource is provisioned with `type: 'Pool'`. The name is automatically generated based on the model (e.g., `gpt-4o-azure-openai-backend-pool`).

### Step D: Attaching Weights
The `priority` and `weight` properties that you defined for the individual endpoints are injected into the `services` array of the new Pool.

```bicep
// Example generated APIM Pool definition
pool: {
  services: [
    {
      id: '/backends/internal-aoai-01'
      priority: 1
      weight: 100
    }
    {
      id: '/backends/external-team-01'
      priority: 1
      weight: 200
    }
  ]
}
```

---

## 3. Policy Execution (`frag-set-target-backend-pool.xml`)

When an end-user sends a request to the gateway (e.g., asking for `gpt-4o`), the Gateway's inbound XML policies execute the following steps:

1. **Model Resolution:** The policy reads the requested model from the JSON body (`"model": "gpt-4o"`).
2. **Backend Lookup:** It looks up the associated backend pool for that model (`gpt-4o-azure-openai-backend-pool`).
3. **Set Backend Service:** The policy executes the `<set-backend-service backend-id="gpt-4o-azure-openai-backend-pool" />` command.
4. **Native Routing:** Once the backend ID is set to a Pool, the Azure API Management native load balancer takes over. It assesses the health of the endpoints, looks at the Priority 1 tier, and rolls the dice according to the Weights (100 vs 200) to select the final destination for the HTTP request.

---

## 4. Design Considerations for External Teams

Because **Weight** is scoped to the endpoint server:
* If an external team provides an endpoint hosting multiple models (e.g., `gpt-4o` and `claude-3`), the single `weight` parameter assigned to their endpoint will dictate their traffic share for *both* models.
* If an external team explicitly wants to absorb 80% of `gpt-4o` traffic but only 20% of `claude-3` traffic, they must provide **two separate URLs/endpoints**, or the internal APIM team must duplicate their backend configuration block in the `.bicepparam` file under two different `backendId`s so they can assign different weights to each model group.

---

## 5. Model Aliases (A/B Testing & Virtual Pools)

In addition to Endpoint-Level routing, the Citadel framework supports **Model-Level Routing** via "Model Aliases" (e.g., `ab-test-gpt`). This is a completely separate layer of load balancing implemented entirely within the Gateway's XML/C# policies (`frag-set-target-backend-pool.xml`).

When a client requests an alias (e.g., `ab-test-gpt`), the Gateway executes the following logic:

### Step A: The Virtual Pool
The Gateway detects that `ab-test-gpt` is an alias, not a real model. It looks up the members of this alias (e.g., `gpt-5` and `gpt-4`).

### Step B: The C# Random Draw
If the alias is configured with a `weighted` strategy (e.g., `weights: [80, 20]`), the C# policy inside APIM draws a random number between 1 and the total weight (100).
* 80% of the time, the policy "picks" `gpt-5`.
* 20% of the time, the policy "picks" `gpt-4`.

### Step C: Body Rewrite
The Gateway dynamically rewrites the client's HTTP request body, replacing `"model": "ab-test-gpt"` with the winning model (e.g., `"model": "gpt-5"`).

### Step D: Handoff to Endpoint Routing
Once the model is rewritten, the request is handed off to the standard **Endpoint-Level Native Routing** (described in Section 3) to find the best backend server that hosts the winning model!
