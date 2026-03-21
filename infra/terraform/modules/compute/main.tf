# ---------------------------------------------------------------------------
# Compute module – ACR, Storage, Key Vault, Container App Environment & App
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

# =============================================================================
# Container Registry
# =============================================================================

resource "azurerm_container_registry" "this" {
  name                = replace("${var.name_prefix}acr", "-", "")
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  admin_enabled       = true
  tags                = var.tags
}

# =============================================================================
# Storage Account
# =============================================================================

resource "azurerm_storage_account" "this" {
  name                     = replace("${var.name_prefix}sa", "-", "")
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# =============================================================================
# Key Vault
# =============================================================================

resource "azurerm_key_vault" "this" {
  name                       = "${var.name_prefix}-kv"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  tags                       = var.tags
}

# =============================================================================
# Container App Environment
# =============================================================================

resource "azurerm_container_app_environment" "this" {
  name                       = "${var.name_prefix}-cae"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = var.log_analytics_workspace_id
  tags                       = var.tags
}

# =============================================================================
# Container App
# =============================================================================

locals {
  acr_login_server   = coalesce(var.acr_login_server, azurerm_container_registry.this.login_server)
  acr_admin_username = coalesce(var.acr_admin_username, azurerm_container_registry.this.admin_username)
  acr_admin_password = coalesce(var.acr_admin_password, azurerm_container_registry.this.admin_password)
}

resource "azurerm_container_app" "this" {
  name                         = "${var.name_prefix}-ca"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type = "SystemAssigned"
  }

  registry {
    server               = local.acr_login_server
    username             = local.acr_admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = local.acr_admin_password
  }

  template {
    min_replicas = 1
    max_replicas = 10

    container {
      name   = "chargeback-api"
      image  = var.container_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "AZURE_SUBSCRIPTION_ID"
        value = var.subscription_id
      }

      env {
        name  = "AZURE_RESOURCE_GROUP"
        value = var.resource_group_name
      }

      env {
        name  = "REDIS_NAME"
        value = "${var.name_prefix}-redis"
      }

      env {
        name  = "ConnectionStrings__redis"
        value = "${var.redis_hostname}:${var.redis_port},ssl=True,abortConnect=False"
      }

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = var.app_insights_connection_string
      }

      env {
        name  = "PURVIEW_CLIENT_APP_ID"
        value = var.purview_client_app_id
      }

      env {
        name  = "AzureAd__TenantId"
        value = var.entra_tenant_id
      }

      env {
        name  = "AzureAd__ClientId"
        value = var.api_app_id
      }

      env {
        name  = "AzureAd__Audience"
        value = "api://${var.api_app_id}"
      }

      env {
        name  = "ConnectionStrings__chargeback"
        value = var.cosmos_endpoint
      }

      env {
        name  = "AZURE_AI_ENDPOINT"
        value = var.ai_service_endpoint
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

# =============================================================================
# Key Vault Access Policy – for the Container App managed identity
# =============================================================================

resource "azurerm_key_vault_access_policy" "container_app" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_container_app.this.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Recover",
    "Backup",
    "Restore",
  ]
}
