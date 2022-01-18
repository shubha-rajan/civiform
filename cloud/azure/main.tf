# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "azurerm"
      version = ">=2.65"
    }
  }

  required_version = ">= 0.14.9"
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "myTFResourceGroup"
  location = var.location_name
}

resource "azurerm_virtual_network" "civiform_vnet" {
  name                = "civiform-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = var.vnet_address_space
}

resource "azurerm_subnet" "server_subnet" {
  name                 = "server-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.civiform_vnet.name
  address_prefixes     = var.subnet_address_prefixes

  delegation {
    name = "app-service-delegation"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_app_service_plan" "plan" {
  name                = "${azurerm_resource_group.rg.name}-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Define Linux as Host OS
  kind     = "Linux"
  reserved = true # Mandatory for Linux plans

  # Choose size
  sku {
    tier     = var.app_sku["tier"]
    size     = var.app_sku["size"]
    capacity = var.app_sku["capacity"]
  }
}

resource "azurerm_app_service" "civiform_app" {
  name                = var.application_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.plan.id
  app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = false
    PORT                                = 9000

    DOCKER_REGISTRY_SERVER_URL = "https://index.docker.io"

    DB_USERNAME    = "${azurerm_postgresql_server.civiform.administrator_login}@${azurerm_postgresql_server.civiform.name}"
    DB_PASSWORD    = azurerm_postgresql_server.civiform.administrator_login_password
    DB_JDBC_STRING = "jdbc:postgresql://${local.postgres_private_link}:5432/postgres?ssl=true&sslmode=require"

    STORAGE_SERVICE_NAME            = "azure-blob"
    AZURE_STORAGE_ACCOUNT_NAME      = azurerm_storage_account.storage.name
    AZURE_STORAGE_ACCOUNT_CONTAINER = azurerm_storage_container.storage_container.name

    SECRET_KEY = var.app_secret_key
  }
  # Configure Docker Image to load on start
  site_config {
    linux_fx_version                     = "DOCKER|${var.docker_username}/${var.docker_repository_name}:${var.image_tag_name}"
    always_on                            = true
    acr_use_managed_identity_credentials = true
    vnet_route_all_enabled               = true
  }

  identity {
    type = "SystemAssigned"
  }

}

resource "azurerm_role_assignment" "storage_blob_delegator" {
  scope                = azurerm_storage_container.storage_container.resource_manager_id
  role_definition_name = "Storage Blob Delegator"
  principal_id         = azurerm_app_service.civiform_app.identity.0.principal_id
}

resource "azurerm_role_assignment" "storage_blob_data_contributor" {
  scope                = azurerm_storage_container.storage_container.resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_app_service.civiform_app.identity.0.principal_id
}

resource "azurerm_app_service_virtual_network_swift_connection" "appservice_vnet_connection" {
  app_service_id = azurerm_app_service.civiform_app.id
  subnet_id      = azurerm_subnet.server_subnet.id
}

resource "azurerm_log_analytics_workspace" "civiform_logs" {
  name                = "civiform-server-logs"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = var.log_sku
  retention_in_days   = var.log_retention
}

resource "azurerm_monitor_diagnostic_setting" "app_service_log_analytics" {
  name                       = "${var.application_name}_log_analytics"
  target_resource_id         = azurerm_app_service.civiform_app.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.civiform_logs.id

  log {
    category = "AppServiceAppLogs"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "AppServiceConsoleLogs"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "AppServiceHTTPLogs"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "AppServiceAuditLogs"

    retention_policy {
      enabled = false
    }
  }
  metric {
    category = "AllMetrics"

    retention_policy {
      enabled = false
    }
  }
}

resource "azurerm_postgresql_server" "civiform" {
  name                = "civiform-db"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  administrator_login          = var.postgres_admin_login
  administrator_login_password = var.postgres_admin_password

  // fqdn civiform-db.postgres.database.azure.com

  sku_name   = var.postgres_sku_name
  version    = "11"
  storage_mb = var.postgres_storage_mb

  backup_retention_days        = var.postgres_backup_retention_days
  geo_redundant_backup_enabled = false
  auto_grow_enabled            = true

  public_network_access_enabled = false

  ssl_enforcement_enabled          = true
  ssl_minimal_tls_version_enforced = "TLS1_2"
}

resource "azurerm_postgresql_database" "civiform" {
  name                = "civiform"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_postgresql_server.civiform.name
  charset             = "utf8"
  collation           = "English_United States.1252"
}

# Configure private link
resource "azurerm_subnet" "postgres_subnet" {
  name                 = "postgres_subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.civiform_vnet.name
  address_prefixes     = var.postgres_subnet_address_prefixes

  enforce_private_link_endpoint_network_policies = true
}

resource "azurerm_private_dns_zone" "postgres_private_link" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres_vnet_link" {
  name                  = "postgres-vnet-link-private-dns"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres_private_link.name
  virtual_network_id    = azurerm_virtual_network.civiform_vnet.id
}

resource "azurerm_private_endpoint" "postgres_endpoint" {
  name                = "${azurerm_postgresql_server.civiform.name}-endpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.postgres_subnet.id

  private_dns_zone_group {
    name                 = "postgres-private-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.postgres_private_link.id]
  }

  private_service_connection {
    name                           = "${azurerm_postgresql_server.civiform.name}-privateserviceconnection"
    private_connection_resource_id = azurerm_postgresql_server.civiform.id
    subresource_names              = ["postgresqlServer"]
    is_manual_connection           = false
  }
}


resource "azurerm_storage_account" "storage" {
  name                      = var.storage_account_name
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  account_kind              = "StorageV2"
  account_tier              = var.storage_account_tier
  account_replication_type  = var.storage_account_replication_type
  enable_https_traffic_only = true
}

resource "azurerm_storage_container" "storage_container" {
  name                  = var.storage_container_name
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

resource "azurerm_subnet" "storage_subnet" {
  name                 = "storage_subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.civiform_vnet.name
  address_prefixes     = var.storage_subnet_address_prefixes

  enforce_private_link_endpoint_network_policies = true
}

resource "azurerm_private_dns_zone" "storage_private_link" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_vnet_link" {
  name                  = "storage-vnet-link-private-dns"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_private_link.name
  virtual_network_id    = azurerm_virtual_network.civiform_vnet.id
}

resource "azurerm_private_endpoint" "storage_endpoint" {
  name                = "${azurerm_storage_account.storage.name}-endpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.storage_subnet.id

  private_dns_zone_group {
    name                 = "storage-private-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_private_link.id]
  }
  private_service_connection {
    name                           = "${azurerm_storage_account.storage.name}-privateserviceconnection"
    private_connection_resource_id = azurerm_storage_account.storage.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

}

resource "azurerm_storage_account_network_rules" "storage_network_rules" {
  storage_account_id = azurerm_storage_account.storage.id
  default_action     = "Deny"
  private_link_access {
    endpoint_resource_id = azurerm_private_endpoint.storage_endpoint.id
  }
}
