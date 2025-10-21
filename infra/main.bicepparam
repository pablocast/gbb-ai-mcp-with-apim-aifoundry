using 'main.bicep'

param apimSku = 'Basicv2'

param aiServicesConfig = [
  {
    name: 'foundry1'
    location: 'eastus2'
  }
]

param modelsConfig = [
  {
    name: 'gpt-4.1-mini'
    publisher: 'OpenAI'
    version: '2025-04-14'
    sku: 'GlobalStandard'
    capacity: 20
  }
]

param apimSubscriptionsConfig = [
  {
    name: 'subscription1'
    displayName: 'Subscription 1'
  }
]

param inferenceAPIPath = 'inference'
param inferenceAPIType = 'AzureOpenAI'
param inferenceAPIVersion = '2025-03-01-preview'
param foundryProjectName = 'gbb-ai-mcp-apim-aifoundry'
param apicLocation = 'eastus'
param apicServiceNamePrefix = 'apic6'
param deployerPrincipalId = readEnvironmentVariable('AZURE_PRINCIPAL_ID', 'principalId')
