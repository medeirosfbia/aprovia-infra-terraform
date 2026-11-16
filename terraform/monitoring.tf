resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-aprovia"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 1
  tags                = var.tags
}

resource "azurerm_application_insights" "main" {
  name                = "appi-aprovia"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_monitor_action_group" "email" {
  name                = "ag-aprovia-email"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "aprovia"

  email_receiver {
    name                    = "responsavel"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }

  tags = var.tags
}

# Logs de leitura/escrita do Blob e da Queue no Log Analytics
resource "azurerm_monitor_diagnostic_setting" "blob" {
  name                       = "diag-blob"
  target_resource_id         = "${azurerm_storage_account.main.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }
  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_diagnostic_setting" "queue" {
  name                       = "diag-queue"
  target_resource_id         = "${azurerm_storage_account.main.id}/queueServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }
  enabled_metric {
    category = "Transaction"
  }
}

# Testes de disponibilidade: chamam o health check das duas APIs a cada 5 minutos, de 3 regiões
resource "azurerm_application_insights_standard_web_test" "api_health" {
  name                    = "webtest-api-health"
  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  application_insights_id = azurerm_application_insights.main.id
  frequency               = 300
  timeout                 = 30
  enabled                 = true
  retry_enabled           = true
  geo_locations           = ["latam-br-gru-edge", "us-va-ash-azr", "emea-nl-ams-azr"]

  request {
    url = "https://${local.api_domain}/health"
  }

  validation_rules {
    expected_status_code        = 200
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = 7
  }

  tags = var.tags
}

resource "azurerm_application_insights_standard_web_test" "java_health" {
  name                    = "webtest-java-health"
  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  application_insights_id = azurerm_application_insights.main.id
  frequency               = 300
  timeout                 = 30
  enabled                 = true
  retry_enabled           = true
  geo_locations           = ["latam-br-gru-edge", "us-va-ash-azr", "emea-nl-ams-azr"]

  request {
    url = "https://${azurerm_container_app.java.ingress[0].fqdn}/actuator/health"
  }

  validation_rules {
    expected_status_code = 200
    ssl_check_enabled    = true
  }

  tags = var.tags
}

# Alertas
resource "azurerm_monitor_metric_alert" "api_down" {
  name                = "alerta-api-fora-do-ar"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights_standard_web_test.api_health.id, azurerm_application_insights.main.id]
  description         = "A API Python falhou no /health em 2 ou mais regiões."
  severity            = 1

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.api_health.id
    component_id          = azurerm_application_insights.main.id
    failed_location_count = 2
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "java_down" {
  name                = "alerta-java-fora-do-ar"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights_standard_web_test.java_health.id, azurerm_application_insights.main.id]
  description         = "A API Java falhou no /actuator/health em 2 ou mais regiões."
  severity            = 1

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.java_health.id
    component_id          = azurerm_application_insights.main.id
    failed_location_count = 2
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "exceptions" {
  name                = "alerta-excecoes"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main.id]
  description         = "Mais de 10 exceções em 15 minutos (API ou Function App)."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "exceptions/count"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 10
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "queue_backlog" {
  name                = "alerta-fila-acumulando"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = ["${azurerm_storage_account.main.id}/queueServices/default"]
  description         = "Mais de 100 mensagens paradas nas filas: a Function App pode estar parada."
  severity            = 2
  frequency           = "PT15M"
  window_size         = "PT1H"

  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts/queueServices"
    metric_name      = "QueueMessageCount"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 100
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "storage_availability" {
  name                = "alerta-storage-disponibilidade"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_storage_account.main.id]
  description         = "Disponibilidade da Storage Account abaixo de 99%."
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "Availability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 99
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }

  tags = var.tags
}
