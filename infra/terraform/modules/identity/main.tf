# ---------------------------------------------------------------------------
# Identity module – Entra ID app registrations for the chargeback system
# ---------------------------------------------------------------------------

data "azuread_client_config" "current" {}

# Random UUID for the OAuth2 permission scope
resource "random_uuid" "oauth2_scope_id" {}

# Random UUIDs for app role IDs
resource "random_uuid" "role_export" {}
resource "random_uuid" "role_admin" {}
resource "random_uuid" "role_apim" {}

# =============================================================================
# API App Registration (multi-tenant)
# =============================================================================

resource "azuread_application" "api" {
  display_name     = "Chargeback API"
  sign_in_audience = "AzureADMultipleOrgs"

  api {
    oauth2_permission_scope {
      id                         = random_uuid.oauth2_scope_id.result
      admin_consent_display_name = "Access Chargeback API"
      admin_consent_description  = "Allows the app to access the Chargeback API"
      type                       = "Admin"
      value                      = "access_as_user"
      enabled                    = true
    }
  }

  app_role {
    id                   = random_uuid.role_export.result
    display_name         = "Chargeback Export"
    description          = "Can export chargeback data"
    value                = "Chargeback.Export"
    allowed_member_types = ["Application", "User"]
    enabled              = true
  }

  app_role {
    id                   = random_uuid.role_admin.result
    display_name         = "Chargeback Admin"
    description          = "Full administrative access to the chargeback system"
    value                = "Chargeback.Admin"
    allowed_member_types = ["Application", "User"]
    enabled              = true
  }

  app_role {
    id                   = random_uuid.role_apim.result
    display_name         = "Chargeback APIM"
    description          = "API Management service access"
    value                = "Chargeback.Apim"
    allowed_member_types = ["Application"]
    enabled              = true
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "37f7f235-527c-4136-accd-4a02d197296e" # openid
      type = "Scope"
    }
  }
}

resource "azuread_application_identifier_uri" "api" {
  application_id = azuread_application.api.id
  identifier_uri = "api://${azuread_application.api.client_id}"
}

resource "azuread_service_principal" "api" {
  client_id = azuread_application.api.client_id
}

# =============================================================================
# Client App 1 – single-tenant sample client
# =============================================================================

resource "azuread_application" "client1" {
  display_name     = "Chargeback Sample Client"
  sign_in_audience = "AzureADMyOrg"

  required_resource_access {
    resource_app_id = azuread_application.api.client_id

    resource_access {
      id   = random_uuid.oauth2_scope_id.result
      type = "Scope"
    }
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "37f7f235-527c-4136-accd-4a02d197296e" # openid
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "client1" {
  client_id = azuread_application.client1.client_id
}

resource "azuread_application_password" "client1" {
  application_id    = azuread_application.client1.id
  display_name      = "terraform"
  end_date          = timeadd(timestamp(), "8760h")

  lifecycle {
    ignore_changes = [end_date]
  }
}

resource "azuread_app_role_assignment" "client1_admin" {
  app_role_id         = random_uuid.role_admin.result
  principal_object_id = azuread_service_principal.client1.object_id
  resource_object_id  = azuread_service_principal.api.object_id
}

# =============================================================================
# Client App 2 – multi-tenant demo client
# =============================================================================

resource "azuread_application" "client2" {
  display_name     = "Chargeback Demo Client 2"
  sign_in_audience = "AzureADMultipleOrgs"

  required_resource_access {
    resource_app_id = azuread_application.api.client_id

    resource_access {
      id   = random_uuid.oauth2_scope_id.result
      type = "Scope"
    }
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "37f7f235-527c-4136-accd-4a02d197296e" # openid
      type = "Scope"
    }
  }

  public_client {
    redirect_uris = ["http://localhost:29783"]
  }
}

resource "azuread_service_principal" "client2" {
  client_id = azuread_application.client2.client_id
}

resource "azuread_application_password" "client2" {
  application_id    = azuread_application.client2.id
  display_name      = "terraform"
  end_date          = timeadd(timestamp(), "8760h")

  lifecycle {
    ignore_changes = [end_date]
  }
}

# =============================================================================
# Admin consent grants – delegated permission grants
# =============================================================================

resource "azuread_service_principal_delegated_permission_grant" "client1" {
  service_principal_object_id          = azuread_service_principal.client1.object_id
  resource_service_principal_object_id = azuread_service_principal.api.object_id
  claim_values                         = ["access_as_user"]
}

resource "azuread_service_principal_delegated_permission_grant" "client2" {
  service_principal_object_id          = azuread_service_principal.client2.object_id
  resource_service_principal_object_id = azuread_service_principal.api.object_id
  claim_values                         = ["access_as_user"]
}
