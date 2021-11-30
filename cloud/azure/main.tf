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
  location = "eastus"
}

resource "azurerm_virtual_network" "civiform_vnet" {
  name                = "civiform-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "server_subnet" {
  name                 = "server-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.civiform_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
  service_endpoints    = ["Microsoft.Sql"]

  delegation {
    name = "app-service-delegation"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}



locals {
  backend_address_pool_name      = "${azurerm_virtual_network.civiform_vnet.name}-beap"
  frontend_port_name             = "${azurerm_virtual_network.civiform_vnet.name}-feport"
  frontend_ip_configuration_name = "${azurerm_virtual_network.civiform_vnet.name}-feip"
  http_setting_name              = "${azurerm_virtual_network.civiform_vnet.name}-be-htst"
  listener_name                  = "${azurerm_virtual_network.civiform_vnet.name}-httplstn"
  request_routing_rule_name      = "${azurerm_virtual_network.civiform_vnet.name}-rqrt"
  redirect_configuration_name    = "${azurerm_virtual_network.civiform_vnet.name}-rdrcfg"
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
    tier     = "Standard"
    size     = "S1"
    capacity = "2"
  }
}

resource "azurerm_app_service" "civiform-app" {
  name                = var.application_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.plan.id
  app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = false


    # Below only necessary if using private Docker repository
    DOCKER_REGISTRY_SERVER_USERNAME = var.docker_username
    DOCKER_REGISTRY_SERVER_PASSWORD = var.docker_password

    DB_USERNAME    = "${azurerm_postgresql_server.civiform.administrator_login}@${azurerm_postgresql_server.civiform.name}"
    DB_PASSWORD    = azurerm_postgresql_server.civiform.administrator_login_password
    DB_JDBC_STRING = "jdbc:postgresql://${azurerm_postgresql_server.civiform.fqdn}:5432/postgres?ssl=true&sslmode=require"

    SECRET_KEY = "insecure-secret-key"
  }
  # Configure Docker Image to load on start
  site_config {
    linux_fx_version                     = "DOCKER|${var.docker_username}/${var.docker_repository_name}:${var.tag_name}"
    always_on                            = "true"
    acr_use_managed_identity_credentials = "true"
    vnet_route_all_enabled               = "true"
  }

  identity {
    type = "SystemAssigned"
  }

}


resource "azurerm_app_service_virtual_network_swift_connection" "appservice_vnet_connection" {
  app_service_id = azurerm_app_service.civiform-app.id
  subnet_id      = azurerm_subnet.server_subnet.id
}

resource "azurerm_log_analytics_workspace" "civiform_logs" {
  name                = "civiform-server-logs"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

output "app_service_default_hostname" {
  value = "https://${azurerm_app_service.civiform-app.default_site_hostname}"
}

resource "azurerm_monitor_diagnostic_setting" "app_service_log_analytics" {
  name                       = "app_service_log_analytics"
  target_resource_id         = azurerm_app_service.civiform-app.id
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

  administrator_login          = "psqladmin"
  administrator_login_password = "H@Sh1CoR3!"

  // fqdn civiform-psqlserver.postgres.database.azure.com

  sku_name   = "GP_Gen5_4"
  version    = "11"
  storage_mb = 5120

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  auto_grow_enabled            = true

  # TODO: configure a subnet and restrict access only to the application servers.
  public_network_access_enabled = true

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


resource "azurerm_postgresql_virtual_network_rule" "civiform" {
  name                                 = "sqlvnetrule"
  resource_group_name                  = azurerm_resource_group.rg.name
  server_name                          = azurerm_postgresql_server.civiform.name
  subnet_id                            = azurerm_subnet.server_subnet.id
  ignore_missing_vnet_service_endpoint = true
}