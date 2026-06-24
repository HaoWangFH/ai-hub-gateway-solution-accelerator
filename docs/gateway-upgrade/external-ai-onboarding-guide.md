# External AI Service Onboarding Guide

This document provides the standard operating procedure (SOP) for onboarding a new AI Service (provided by an external or 3rd-party team) into the AI Hub Gateway. 

It is divided into two parts:
1. **Information Request Form**: What to send to the external team.
2. **Implementation Guide**: How your team will configure the Bicep templates once the information is received.

---

## Part 1: Information Request Form (For the External Team)

*Send this template to the external team providing the AI service so they can supply the exact parameters needed for the gateway to route traffic to them.*

> **To:** [External Team Contact]  
> **Subject:** AI Hub Gateway Onboarding Requirements for [Service Name]  
> 
> Hello team,  
> 
> We are preparing to integrate your AI endpoints into our AI Hub API Gateway. To configure the routing, load balancing, and authentication, please provide the following details regarding your endpoints:
> 
> **1. Connection Details**
> * **Base Endpoint URL:** (e.g., `https://<your-service>.openai.azure.com/` or `https://api.anthropic.com/`)
> * **Backend Type:** (e.g., Azure OpenAI, Standard OpenAI, Anthropic, Gemini, AI Foundry)
> 
> **2. Authentication Mechanism**
> *How should our gateway authenticate with your service?*
> * [ ] **API Key**: Please provide the key securely (via Azure KeyVault link or secure password sharing tool).
> * [ ] **Entra ID (Managed Identity)**: If you prefer this, please whitelist our Gateway's Managed Identity Client ID: `[Insert your mi-EIST-apim-dev Client ID here]`.
> * [ ] **Other**: Please specify (e.g., AWS SigV4, OAuth).
> 
> **3. Model Information**
> *Please list the exact models exposed on this endpoint so we can configure our routing tables.*
> * **Model 1 Name:** (e.g., `gpt-4o`)
>   * **Version:** (e.g., `2024-05-13`)
>   * **Format:** (e.g., `OpenAI`)
>   * **Allocated Capacity:** (e.g., `100`k TPM)
> * **Model 2 Name:** ...
> 
> **4. Network Security (Firewall Whitelisting)**
> *If your service restricts inbound traffic via a firewall, please whitelist our Gateway's outbound IP addresses:*
> * **Primary Gateway IP:** `[Insert APIM Public VIP here]`
> * **VNet Subnet Range:** `[Insert APIM VNet Address Space if peering internally]`
> 
> Thank you!

---

## Part 2: Implementation Guide (For Your Team)

Once the external team replies with the details, follow these steps to wire their service into the APIM Gateway.

### Step 1: Network & VNet Verification
Before touching the code, ensure your gateway can actually reach their endpoint. 
* If they provided a public URL, verify your VNet's Network Security Group (NSG) allows outbound internet access to their domain.
* If they provided an internal/private endpoint, ensure your VNet is peered to their VNet and that DNS resolution works.

### Step 2: Update the Bicep Configuration
Open your environment's parameter file (e.g., `bicep/infra/apim-gateway-upgrade/main-eist-dev.bicepparam`) and locate the `llmBackendConfig` array.

Add a new object to the array mapping the information they provided:

```bicep
param llmBackendConfig = [
  // ... existing backends ...

  {
    backendId: 'ext-team-ai-01'                    // Create a unique, descriptive ID
    backendType: 'azure-openai'                    // Map from their response (azure-openai, openai, anthropic, etc.)
    endpoint: 'https://ext-team.openai.azure.com/' // Map from their response
    priority: 2                                    // 1 is highest priority. Use 2 if this is a fallback backend.
    weight: 100                                    // Traffic distribution weight (e.g. 100)
    
    // AUTHENTICATION CONFIGURATION
    // If they gave you an API Key:
    authType: 'api-key-header'                   
    authConfig: {
      namedValueKey: 'ext-team-ai-01-key'          // Bicep will create this Named Value securely in APIM
      secretValue: 'paste-their-api-key-here'      // (In production, replace this with a keyVaultSecretUri reference)
    }

    // If they whitelisted your Managed Identity instead:
    // authType: 'managed-identity'
    // (authConfig block is not needed)

    // ROUTING CONFIGURATION
    supportedModels: [
      { 
        name: 'gpt-4o'                             // Must match the exact model requested by end users
        sku: 'Standard' 
        capacity: 100 
        modelFormat: 'OpenAI' 
        modelVersion: '2024-05-13' 
      }
    ]
  }
]
```

### Step 3: Run the Deployment
Execute the Bicep deployment to push the new backend pool and policy fragments to Azure APIM.

```powershell
az deployment group create `
  --name "onboard-ext-backend-$(Get-Date -Format 'yyyyMMddHHmm')" `
  --resource-group RG-EIST-APIM-dev `
  --template-file bicep/infra/apim-gateway-upgrade/main.bicep `
  --parameters bicep/infra/apim-gateway-upgrade/main-eist-dev.bicepparam
```

### Step 4: End-to-End Test
Open the Azure Portal, go to your APIM instance, select the **Universal LLM API** (or Azure OpenAI API), and use the **Test** tab to send a request for `gpt-4o`. Verify that the gateway routes the request to the external team's endpoint successfully.

---

## Appendix: Provider-Specific Configurations

The `backendType` and `authType` values must change depending on who is providing the LLM service. Here is how to configure the Gateway for different external/internal AI providers:

### 1. Azure OpenAI / AI Foundry / Azure ML (Microsoft)
* **`backendType`**: `'azure-openai'` (for `*.openai.azure.com`) or `'ai-foundry'` (for `*.inference.ml.azure.com` and `*.models.ai.azure.com`)
* **`authType`**: `'managed-identity'` (Recommended if inside your tenant) OR `'api-key-header'` (If external tenant).
* **Notes**: Fully native. The `ai-foundry` type is specifically designed to handle Azure Machine Learning (AML) Managed Online Endpoints and AI Foundry Serverless APIs.

### 2. Standard OpenAI (OpenAI.com)
* **`backendType`**: `'openai'`
* **`authType`**: `'api-key-bearer'`
* **Notes**: APIM will automatically translate the incoming Azure API formats into standard OpenAI Bearer token formats.

### 3. Anthropic (Claude)
* **`backendType`**: `'anthropic'`
* **`authType`**: `'api-key-header'` (or `'aws-sigv4'` if hosted on AWS Bedrock)
* **Notes**: APIM intercepts the OpenAI-formatted request from the client and translates the JSON payload entirely into Anthropic's Messages API format on the fly.

### 4. Google Gemini
* **`backendType`**: `'gemini'`
* **`authType`**: `'api-key-gemini'`
* **Notes**: APIM translates the OpenAI-formatted request into Gemini's format on the fly.

### 5. On-Premises / Local Models (vLLM, Ollama)
* **`backendType`**: `'openai'`
* **`authType`**: `'none'` (If internal VNet without auth) or `'api-key-bearer'`
* **Notes**: Because tools like vLLM and Ollama natively expose an OpenAI-compatible API, you simply treat them as a standard OpenAI endpoint.
