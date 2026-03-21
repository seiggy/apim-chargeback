# ---------------------------------------------------------------------------
# Gateway module – API Management instance, OpenAI API, policy, and roles
# ---------------------------------------------------------------------------

# =============================================================================
# API Management
# =============================================================================

resource "azurerm_api_management" "this" {
  name                = "${var.name_prefix}-apim"
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_email     = var.publisher_email
  publisher_name      = var.publisher_name
  sku_name            = var.sku
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# =============================================================================
# Named Values
# =============================================================================

resource "azurerm_api_management_named_value" "entra_tenant_id" {
  name                = "EntraTenantId"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = "EntraTenantId"
  value               = var.tenant_id
}

resource "azurerm_api_management_named_value" "expected_audience" {
  name                = "ExpectedAudience"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = "ExpectedAudience"
  value               = "api://${var.api_app_id}"
}

resource "azurerm_api_management_named_value" "container_app_url" {
  name                = "ContainerAppUrl"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = "ContainerAppUrl"
  value               = "https://${var.container_app_fqdn}"
}

resource "azurerm_api_management_named_value" "container_app_audience" {
  name                = "ContainerAppAudience"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = "ContainerAppAudience"
  value               = "api://${var.api_app_id}"
}

# =============================================================================
# OpenAI API Import
# =============================================================================

resource "azurerm_api_management_api" "openai" {
  name                  = "azure-openai-service-api"
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = var.resource_group_name
  display_name          = "Azure OpenAI Service API"
  path                  = "openai"
  protocols             = ["https"]
  subscription_required = false
  service_url           = "${var.ai_service_endpoint}openai"
  revision              = "1"

  import {
    content_format = "openapi+json-link"
    content_value  = var.api_spec_url
  }
}

# =============================================================================
# API Policy – Entra JWT validation, precheck, logging
# =============================================================================

resource "azurerm_api_management_api_policy" "openai" {
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  xml_content         = file(var.policy_xml_path)
}

# =============================================================================
# Role Assignments
# =============================================================================

# APIM identity → Cognitive Services User on AI Services
resource "azurerm_role_assignment" "apim_cognitive_services_user" {
  scope                = var.ai_service_id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
}

# APIM identity → Key Vault Secrets User on Key Vault
resource "azurerm_role_assignment" "apim_key_vault_secrets_user" {
  count                = var.key_vault_id != "" ? 1 : 0
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
}

# APIM identity → Contributor on Container App
resource "azurerm_role_assignment" "apim_container_app_contributor" {
  count                = var.container_app_id != "" ? 1 : 0
  scope                = var.container_app_id
  role_definition_name = "Contributor"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
}
