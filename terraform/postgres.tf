# Banco de usuários da API Java (manager_back)
resource "random_password" "postgres" {
  length           = 24
  special          = true
  override_special = "_-"
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                          = "psql-aprovia-${local.suffix}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = coalesce(var.postgres_location, azurerm_resource_group.main.location)
  version                       = "16"
  administrator_login           = "aproviaadmin"
  administrator_password        = random_password.postgres.result
  sku_name                      = var.postgres_high_availability ? "GP_Standard_D2ds_v5" : "B_Standard_B1ms"
  storage_mb                    = 32768
  auto_grow_enabled             = true
  backup_retention_days         = 14
  geo_redundant_backup_enabled  = var.postgres_geo_backup
  public_network_access_enabled = true
  zone                          = "1"

  # HA com réplica em outra zona: só existe nos tiers General Purpose e Memory Optimized
  dynamic "high_availability" {
    for_each = var.postgres_high_availability ? [1] : []
    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = "2"
    }
  }

  maintenance_window {
    day_of_week  = 0
    start_hour   = 4
    start_minute = 0
  }

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_postgresql_flexible_server_database" "aprovia" {
  name      = "aprovia"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Libera serviços da Azure (0.0.0.0, inclui o Container Apps) e os IPs informados (ex.: sua máquina)
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "azure-services"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allowed" {
  for_each         = toset(var.postgres_allowed_ips)
  name             = "ip-${replace(each.value, ".", "-")}"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = each.value
  end_ip_address   = each.value
}

resource "azurerm_monitor_diagnostic_setting" "postgres" {
  name                       = "diag-postgres"
  target_resource_id         = azurerm_postgresql_flexible_server.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "PostgreSQLLogs"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_metric_alert" "postgres_cpu" {
  name                = "alerta-postgres-cpu-alta"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_postgresql_flexible_server.main.id]
  description         = "CPU do PostgreSQL acima de 80% por 15 minutos."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "postgres_storage" {
  name                = "alerta-postgres-disco"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_postgresql_flexible_server.main.id]
  description         = "Armazenamento do PostgreSQL acima de 85%."
  severity            = 2
  frequency           = "PT15M"
  window_size         = "PT1H"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "storage_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }

  tags = var.tags
}
