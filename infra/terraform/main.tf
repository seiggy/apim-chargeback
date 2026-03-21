# =============================================================================
# Root orchestration – wires all modules and handles cross-module dependencies
# =============================================================================

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  workload_token = lower(replace(var.workload_name, "/[^a-z0-9]/", ""))
  name_prefix    = var.workload_name
  tags = {
    workload   = var.workload_name
    managed_by = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# =============================================================================
# Modules – ordered by dependency graph
# =============================================================================

# ---------------------------------------------------------------------------
# 1. Monitoring (depends on: resource group)
# ---------------------------------------------------------------------------

module "monitoring" {
  source = "./modules/monitoring"

  name_prefix         = local.name_prefix
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# 2. Data (depends on: resource group)
#    NOTE: container_app_principal_id is "" here to break the circular
#    dependency with compute. The Redis access policy is created as a
#    standalone resource below once both modules exist.
# ---------------------------------------------------------------------------

module "data" {
  source = "./modules/data"

  name_prefix                = local.name_prefix
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  container_app_principal_id = ""
  tags                       = local.tags
}

# ---------------------------------------------------------------------------
# 3. AI Services (depends on: resource group)
# ---------------------------------------------------------------------------

module "ai_services" {
  source = "./modules/ai_services"

  name                = "${local.name_prefix}-ai"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  deployments         = var.ai_deployments
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# 4. Identity (no Azure resource dependencies)
# ---------------------------------------------------------------------------

module "identity" {
  source = "./modules/identity"

  tags = local.tags
}

# ---------------------------------------------------------------------------
# 5. Compute (depends on: monitoring, data, ai_services, identity)
# ---------------------------------------------------------------------------

module "compute" {
  source = "./modules/compute"

  name_prefix                = local.name_prefix
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  subscription_id            = var.subscription_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  redis_hostname             = module.data.redis_hostname
  redis_port                 = module.data.redis_port
  cosmos_endpoint            = module.data.cosmos_endpoint
  ai_service_endpoint        = module.ai_services.endpoint
  app_insights_connection_string = module.monitoring.app_insights_connection_string
  purview_client_app_id      = var.purview_client_app_id
  entra_tenant_id            = module.identity.tenant_id
  api_app_id                 = module.identity.api_app_id
  container_image            = var.container_image
  tags                       = local.tags
}

# ---------------------------------------------------------------------------
# 6. Gateway (depends on: ai_services, compute, identity)
# ---------------------------------------------------------------------------

module "gateway" {
  source = "./modules/gateway"

  name_prefix         = local.name_prefix
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = var.apim_sku
  publisher_email     = var.apim_publisher_email
  publisher_name      = var.apim_publisher_name
  api_spec_url        = var.openai_api_spec_url
  ai_service_endpoint = module.ai_services.endpoint
  ai_service_id       = module.ai_services.id
  container_app_fqdn  = module.compute.container_app_fqdn
  container_app_id    = module.compute.container_app_id
  api_app_id          = module.identity.api_app_id
  tenant_id           = module.identity.tenant_id
  key_vault_id        = module.compute.key_vault_id
  policy_xml_path     = "${path.module}/../../policies/entra-jwt-policy.xml"
  tags                = local.tags
}

# =============================================================================
# Cross-module resources
# =============================================================================

# ---------------------------------------------------------------------------
# Redis access policy for Container App managed identity
# (breaks circular dependency between data ↔ compute)
# ---------------------------------------------------------------------------

resource "azapi_resource" "redis_container_app_access" {
  type      = "Microsoft.Cache/redisEnterprise/databases/accessPolicyAssignments@2025-04-01"
  name      = "containerappDataOwner"
  parent_id = module.data.redis_database_id

  body = {
    properties = {
      accessPolicyName = "default"
      user = {
        objectId = module.compute.container_app_principal_id
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Container App identity → Cosmos DB Data Contributor
# ---------------------------------------------------------------------------

resource "azurerm_cosmosdb_sql_role_assignment" "container_app_cosmos" {
  resource_group_name = azurerm_resource_group.this.name
  account_name        = module.data.cosmos_account_name
  role_definition_id  = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.DocumentDB/databaseAccounts/${module.data.cosmos_account_name}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = module.compute.container_app_principal_id
  scope               = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.this.name}/providers/Microsoft.DocumentDB/databaseAccounts/${module.data.cosmos_account_name}"
}

# ---------------------------------------------------------------------------
# Container App identity → Cognitive Services OpenAI User on AI Services
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "container_app_ai_services" {
  scope                = module.ai_services.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.compute.container_app_principal_id
}

# ---------------------------------------------------------------------------
# Data source for subscription (used in Cosmos role assignment scope)
# ---------------------------------------------------------------------------

data "azurerm_subscription" "current" {}

# =============================================================================
# Demo environment file
# =============================================================================

resource "local_file" "demo_env" {
  filename = "${path.module}/../../demo/.env.local"
  content  = <<-EOT
# Auto-generated by Terraform
DemoClient__TenantId=${module.identity.tenant_id}
DemoClient__SecondaryTenantId=${var.secondary_tenant_id}
DemoClient__ApiScope=api://${module.identity.api_app_id}/.default
DemoClient__ApimBase=${module.gateway.apim_gateway_url}
DemoClient__ApiVersion=2024-02-01
DemoClient__ChargebackBase=https://${module.compute.container_app_fqdn}
DemoClient__Clients__0__Name=Chargeback Sample Client
DemoClient__Clients__0__AppId=${module.identity.client1_app_id}
DemoClient__Clients__0__Secret=${module.identity.client1_secret}
DemoClient__Clients__0__Plan=Enterprise
DemoClient__Clients__0__DeploymentId=gpt-4o
DemoClient__Clients__0__TenantId=${module.identity.tenant_id}
DemoClient__Clients__1__Name=Chargeback Demo Client 2
DemoClient__Clients__1__AppId=${module.identity.client2_app_id}
DemoClient__Clients__1__Secret=${module.identity.client2_secret}
DemoClient__Clients__1__Plan=Starter
DemoClient__Clients__1__DeploymentId=gpt-4o-mini
DemoClient__Clients__1__TenantId=${module.identity.tenant_id}
  EOT
}
