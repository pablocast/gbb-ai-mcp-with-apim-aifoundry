// ------------------
//    PARAMETERS
// ------------------

param aiServicesConfig array = []
param modelsConfig array = []
param apimSku string
param apimSubscriptionsConfig array = []
param inferenceAPIType string = 'AzureOpenAI'
param inferenceAPIPath string = 'inference' // Path to the inference API in the APIM service
param foundryProjectName string = 'default'
param apicLocation string = resourceGroup().location
param apicServiceNamePrefix string = 'apic' // API Center does not currently support instance purge, so we use a prefix to ensure uniqueness
param inferenceAPIVersion string
param deployerPrincipalId string

// ------------------
//    VARIABLES
// ------------------
param deploymentTimestamp string = utcNow('yyyyMMddHHmmss')
var resourceSuffix = uniqueString(subscription().id, resourceGroup().id, deploymentTimestamp)

// ------------------
//    RESOURCES
// ------------------

// 1. Log Analytics Workspace
module lawModule './modules/workspaces.bicep' = {
  name: 'lawModule'
}

// 2. Application Insights
module appInsightsModule './modules/appinsights.bicep' = {
  name: 'appInsightsModule'
  params: {
    lawId: lawModule.outputs.id
    customMetricsOptedInType: 'WithDimensions'
  }
}

// 3. API Management
module apimModule './modules/apim.bicep' = {
  name: 'apimModule'
  params: {
    apimSku: apimSku
    apimSubscriptionsConfig: apimSubscriptionsConfig
    lawId: lawModule.outputs.id
    appInsightsId: appInsightsModule.outputs.id
    appInsightsInstrumentationKey: appInsightsModule.outputs.instrumentationKey
  }
}

// 4. AI Foundry
module foundryModule './modules/foundry.bicep' = {
    name: 'foundryModule'
    params: {
      aiServicesConfig: aiServicesConfig
      modelsConfig: modelsConfig
      apimPrincipalId: apimModule.outputs.principalId
      foundryProjectName: foundryProjectName
      deployerPrincipalId: deployerPrincipalId
    }
  }

// 5. APIM Inference API
module inferenceAPIModule './modules/inference-api.bicep' = {
  name: 'inferenceAPIModule'
  params: {
    policyXml: loadTextContent('./policy.xml')
    apimLoggerId: apimModule.outputs.loggerId
    aiServicesConfig: foundryModule.outputs.extendedAIServicesConfig
    inferenceAPIType: inferenceAPIType
    inferenceAPIPath: inferenceAPIPath
  }
}

// 6. API Center
module apicModule './modules/apic.bicep' = {
  name: 'apicModule'
  params: {
    apicServiceName: '${apicServiceNamePrefix}-${resourceSuffix}'
    location: apicLocation
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: 'workspace-${resourceSuffix}'
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: 'insights-${resourceSuffix}'
}

module weatherAPIModule 'src/weather/api/api.bicep' = {
  name: 'weatherAPIModule'
  params: {
    apimServiceName: apimModule.outputs.name
    apicServiceName: apicModule.outputs.name
    environmentName: apicModule.outputs.apiEnvironmentName
  }
  dependsOn: [
    apicModule
    inferenceAPIModule
  ]
}

module weatherMCPModule 'src/weather/mcp-server/mcp.bicep' = {
  name: 'weatherMCPModule'
  params: {
    apimServiceName: apimModule.outputs.name
    apicServiceName: apicModule.outputs.name
    environmentName: apicModule.outputs.mcpEnvironmentName
    apiName: weatherAPIModule.outputs.name
  }
  dependsOn: [
    apicModule
    inferenceAPIModule
    weatherAPIModule
  ]
}

module productCatalogAPIModule 'src/product-catalog/api/api.bicep' = {
  name: 'productCatalogAPIModule'
  params: {
    apimServiceName: apimModule.outputs.name
    apicServiceName: apicModule.outputs.name
    environmentName: apicModule.outputs.apiEnvironmentName
  }
  dependsOn: [
    apicModule
    inferenceAPIModule
  ]
}

module productCatalogMCPModule 'src/product-catalog/mcp-server/mcp.bicep' = {
  name: 'productCatalogMCPModule'
  params: {
    apimServiceName: apimModule.outputs.name
    apicServiceName: apicModule.outputs.name
    environmentName: apicModule.outputs.mcpEnvironmentName
    apiName: productCatalogAPIModule.outputs.name
  }
  dependsOn: [
    apicModule
    inferenceAPIModule
    productCatalogAPIModule
  ]
}

module placeOrderAPIModule 'src/place-order/api/api.bicep' = {
  name: 'placeOrderAPIModule'
  params: {
    apimServiceName: apimModule.outputs.name
    apicServiceName: apicModule.outputs.name
    environmentName: apicModule.outputs.apiEnvironmentName
  }
  dependsOn: [
    apicModule
    inferenceAPIModule
  ]
}


module placeOrderMCPModule 'src/place-order/mcp-server/mcp.bicep' = {
  name: 'placeOrderMCPModule'
  params: {
    apimServiceName: apimModule.outputs.name
    apicServiceName: apicModule.outputs.name
    environmentName: apicModule.outputs.mcpEnvironmentName
    apiName: placeOrderAPIModule.outputs.name
  }
  dependsOn: [
    apicModule
    inferenceAPIModule
    placeOrderAPIModule
  ]
}


module microsoftLearnMCPModule 'src/ms-learn/mcp-server/pass-trought.bicep' = {
  name: 'microsoftLearnMCPModule'
  params: {
    apimServiceName: apimModule.outputs.name
    backendName: 'ms-learn-mcp-backend'
    backendDescription: 'Microsoft Learn MCP Backend'
    backendURL: 'https://learn.microsoft.com/api/mcp'
  }
  dependsOn: [
    inferenceAPIModule
    weatherAPIModule
  ]
}

resource mcpInsightsWorkbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, resourceSuffix, 'mcpInsightsWorkbook')
  location: resourceGroup().location
  kind: 'shared'
  properties: {
    displayName: 'MCP Insights Workbook'
    serializedData: replace(loadTextContent('src/mcp-insights/workbook.json'), '{appinsights-id}', applicationInsights.id)
    sourceId: applicationInsights.id
    category: 'workbook'
  }
}

module mcpDashboardModule 'src/mcp-insights/dashboard.bicep' = {
  name: 'mcpDashboardModule'
  params: {
      resourceSuffix: resourceSuffix
      workspaceName: logAnalytics.name
      workspaceId: logAnalytics.id
      appInsightsId: applicationInsights.id
      appInsightsName: applicationInsights.name
      workbookId: mcpInsightsWorkbook.id
    }
}

// ------------------
//    OUTPUTS
// ------------------

output logAnalyticsWorkspaceId string = lawModule.outputs.customerId
output apimServiceId string = apimModule.outputs.id
output apimResourceGatewayURL string = apimModule.outputs.gatewayUrl

output apimSubscriptionsName string = apimModule.outputs.apimSubscriptions[0].name
output apimSubscriptionsKey string = apimModule.outputs.apimSubscriptions[0].key

output foundryProjectEndpoint string = foundryModule.outputs.extendedAIServicesConfig[0].foundryProjectEndpoint
output inferenceAPIVersion string = inferenceAPIVersion

output modelDeploymentName string = modelsConfig[0].name
