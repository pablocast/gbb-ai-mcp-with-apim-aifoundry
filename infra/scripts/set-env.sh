#!/bin/bash
# Bash script to set environment variables for local development based on Bicep outputs
# Usage: ./scripts/set-env.sh

echo "Getting environment variables from azd..."

# Get outputs from azd env get-values
azd_env_values=$(azd env get-values)

# Parse function to extract value from azd output
get_azd_value() {
    local env_values="$1"
    local key="$2"
    local line=$(echo "$env_values" | grep "^$key=")
    if [ -n "$line" ]; then
        echo "$line" | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//'
    else
        echo ""
    fi
}

# Create .env file content
cat > .env << EOF
# Environment variables
# Generated from Bicep deployment outputs

# ---- Log Analytics Variables ----
LOG_ANALYTICS_WORKSPACE_ID=$(get_azd_value "$azd_env_values" "logAnalyticsWorkspaceId")

# ---- APIM Variables ----
APIM_SERVICE_ID=$(get_azd_value "$azd_env_values" "apimServiceId")
APIM_RESOURCE_GATEWAY_URL=$(get_azd_value "$azd_env_values" "apimResourceGatewayURL")
APIM_SUBSCRIPTIONS_NAME=$(get_azd_value "$azd_env_values" "apimSubscriptionsName")
APIM_SUBSCRIPTIONS_KEY=$(get_azd_value "$azd_env_values" "apimSubscriptionsKey")

# ---- AI Foundry Variables ----
FOUNDRY_PROJECT_ENDPOINT=$(get_azd_value "$azd_env_values" "foundryProjectEndpoint")
INFERENCE_API_VERSION=$(get_azd_value "$azd_env_values" "inferenceAPIVersion")
MODEL_DEPLOYMENT_NAME=$(get_azd_value "$azd_env_values" "modelDeploymentName")
EOF

echo ".env file created successfully with deployment outputs!"
echo "You can now use 'docker-compose up' to test your container locally."
