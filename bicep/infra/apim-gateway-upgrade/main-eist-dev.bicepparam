using './main.bicep'

// =====================================================================
//    CORE — EIST DEV environment
//    APIM:  apim-eist-dev  (RG-EIST-APIM-dev)
//    UAMI:  mi-EIST-apim-dev
//    VNet:  Internal mode — backends must be reachable from within VNet
// =====================================================================

param apimServiceName     = 'apim-eist-dev'
param managedIdentityName = 'mi-EIST-apim-dev'

// =====================================================================
//    POLICY FRAGMENTS
// =====================================================================

param updatePolicyFragments  = true
param enableAIModelInference = true

// PII enabled to allow creation of dependent policy fragments
param enablePIIAnonymization = true

// =====================================================================
//    NAMED VALUES (PII, Content Safety)
//
//    updateNamedValues = true creates:
//      - uami-client-id        (always — needed by pii-anonymization fragment)
//      - contentSafetyServiceUrl (empty placeholder until endpoint is confirmed)
//
//    piiServiceUrl is NOT created here (needs enablePIIAnonymization = true).
//    Pre-create it as an empty placeholder via CLI before running this deployment:
//      az rest --method put \
//        --url ".../namedValues/piiServiceUrl?api-version=2022-08-01" \
//        --body '{"properties":{"displayName":"piiServiceUrl","secret":false,"value":""}}'
//    (See eist-dev-upgrade-tracker.md Step 1a for full commands.)
// =====================================================================

param updateNamedValues       = true
param aiLanguageServiceUrl    = 'https://placeholder.com' // Must be valid URL format
param contentSafetyServiceUrl = 'https://placeholder.com' // Must be valid URL format

// =====================================================================
//    JWT AUTHENTICATION NAMED VALUES
// =====================================================================

param updateJwtNamedValues    = true
param enableJwtAuth           = false
param jwtTenantId             = ''
param jwtAppRegistrationId    = ''

// =====================================================================
//    LLM BACKENDS, POOLS & DYNAMIC POLICY FRAGMENTS
//    Disabled for first run — verify VNet connectivity to LLM endpoints
//    before onboarding backends. Uncomment llmBackendConfig and flip
//    flags to true once backends are confirmed reachable.
// =====================================================================

param updateLLMBackends        = true
param updateLLMBackendPools    = true
param updateLLMPolicyFragments = true
param anthropicVersion         = '2023-06-01'

param llmBackendConfig = [
  // TODO: add backends once VNet connectivity to LLM endpoints is confirmed
  // Example:
  // {
  //   backendId: 'aif-eist-dev-0'
  //   backendType: 'ai-foundry'
  //   endpoint: 'https://<your-foundry>.cognitiveservices.azure.com/'
  //   authType: 'managed-identity'
  //   priority: 1
  //   weight: 100
  //   supportedModels: [
  //     { name: 'gpt-4o', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '2024-11-20', retirementDate: '2026-09-30' }
  //   ]
  // }
]

// =====================================================================
//    INFERENCE APIs — Universal LLM & Azure OpenAI
// =====================================================================

param updateUniversalLLMApi = true
param updateAzureOpenAIApi  = true

// =====================================================================
//    UNIFIED AI WILDCARD API
// =====================================================================

param updateUnifiedAiApi  = true
param enableUnifiedAiApi  = true

// =====================================================================
//    OPENAI REALTIME WEBSOCKET API
// =====================================================================

param updateOpenAIRealtimeApi = false

// =====================================================================
//    REDIS CACHE & EMBEDDINGS BACKEND
// =====================================================================

param updateRedisCache          = false
param enableRedisCache          = false
param redisCacheConnectionString = ''

param updateEmbeddingsBackend   = false
param enableEmbeddingsBackend   = false
param embeddingsBackendUrl      = ''

// =====================================================================
//    LOGGING / DIAGNOSTICS
//    App Insights diagnostics disabled — existing logger is named
//    'appi-eist-apim-dev', not 'appinsights-logger' as the upgrade
//    expects. Enabling this would cause a hard failure.
// =====================================================================

param updateAppInsightsDiagnostics = false

param azureMonitorLogSettings = {
  frontend: {
    request:  { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  backend: {
    request:  { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  largeLanguageModel: {
    logs: 'enabled'
    requests:  { messages: 'all', maxSizeInBytes: 262144 }
    responses: { messages: 'all', maxSizeInBytes: 262144 }
  }
}

param appInsightsLogSettings = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: { bytes: 0 }
}
