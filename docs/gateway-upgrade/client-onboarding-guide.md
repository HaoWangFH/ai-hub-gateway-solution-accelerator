# API Client Onboarding Guide

This document provides the standard operating procedure (SOP) for onboarding a new Client (end-user, application, or external system) to consume AI services through the AI Hub Gateway.

---

## Part 1: Client Implementation Guide (Send to the Client)

*Send this guide to the developers or consumers who will be calling your gateway. It tells them how to configure their SDKs and make requests.*

> **To:** [Client Team / Developer]  
> **Subject:** Welcome to the AI Hub Gateway — Connection Guide  
> 
> Welcome! Your application has been granted access to the AI Hub Gateway. The Gateway acts as a single, unified endpoint that gives you access to a variety of AI models (GPT-4, Claude, Gemini, etc.) using the standard OpenAI SDKs.
> 
> ### Your Connection Details
> Please configure your AI SDKs or HTTP clients with the following credentials:
> 
> * **Base URL:** `https://apim-eist-dev.azure-api.net`
> * **API Key (Ocp-Apim-Subscription-Key):** `[Provide the APIM Subscription Key securely]`
> 
> ### How to Connect (Examples)
> 
> You do not need to learn a new SDK. The Gateway is 100% compatible with standard OpenAI SDKs. You simply point the OpenAI SDK to our Gateway URL.
> 
> **Python (OpenAI SDK):**
> ```python
> from openai import OpenAI
> 
> client = OpenAI(
>     base_url="https://apim-eist-dev.azure-api.net/v1", # Use the Unified AI API endpoint
>     api_key="YOUR_SUBSCRIPTION_KEY",
>     default_headers={"Ocp-Apim-Subscription-Key": "YOUR_SUBSCRIPTION_KEY"}
> )
> 
> response = client.chat.completions.create(
>     model="gpt-4o", # The gateway will route this to the best available backend!
>     messages=[{"role": "user", "content": "Hello, AI!"}]
> )
> print(response.choices[0].message.content)
> ```
> 
> **cURL / HTTP Request:**
> ```bash
> curl -X POST https://apim-eist-dev.azure-api.net/v1/chat/completions \
>   -H "Ocp-Apim-Subscription-Key: YOUR_SUBSCRIPTION_KEY" \
>   -H "Content-Type: application/json" \
>   -d '{
>     "model": "gpt-4o",
>     "messages": [{"role": "user", "content": "Hello!"}]
>   }'
> ```
> 
> *Note: Do not send the API Key in the URL query string. Always pass it via the `Ocp-Apim-Subscription-Key` (or standard `api-key`) HTTP header.*

---

## Part 2: Gateway Configuration Guide (For Your Internal Team)

*Follow these steps to generate the credentials required by the client above.*

### Step 1: Create an APIM Product
Products in APIM allow you to group APIs and apply usage quotas/rate limits to specific groups of clients.
1. Open the Azure Portal -> **API Management service** (`apim-eist-dev`).
2. Go to **Products** and click **+ Add**.
3. Name it according to the client or tier (e.g., `Client-App-Alpha-Tier`).
4. Select the APIs to include (e.g., `Unified AI API`, `Universal LLM API`).
5. (Optional) Apply a Policy to the Product to limit Tokens Per Minute (TPM) or Requests Per Minute (RPM) to protect your backends from this specific client.
6. Click **Publish**.

### Step 2: Create a Subscription Key
1. Go to **Subscriptions** in the left menu.
2. Click **+ Add subscription**.
3. **Name**: (e.g., `App-Alpha-Sub`).
4. **Scope**: Select **Product** and choose the Product you just created in Step 1.
5. Click **Save**.

### Step 3: Securely Share the Key
1. In the Subscriptions list, click the eye icon next to your new subscription to reveal the **Primary Key**.
2. Copy this key and provide it to the client using a secure channel (e.g., Azure KeyVault, 1Password, or a secure internal messaging tool). 
3. Send them the **Part 1 Client Implementation Guide** so they know how to use it!
