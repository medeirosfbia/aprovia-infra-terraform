# Function App dos consumidores de fila e rotinas agendadas (consumers_messaging/my_func_history)
resource "azurerm_service_plan" "functions" {
  name                = "asp-aprovia-func"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = var.tags
}

resource "azurerm_linux_function_app" "consumers" {
  name                       = "func-aprovia-${local.suffix}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  service_plan_id            = azurerm_service_plan.functions.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  https_only                 = true

  site_config {
    application_insights_connection_string = azurerm_application_insights.main.connection_string

    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    MONGO_DB_CONNECTION_STRING = var.mongo_connection_string
    MONGO_DB_NAME              = var.mongo_db_name
    QUEUE_NAME                 = azurerm_storage_queue.chat_history.name
    NOTIFICATIONS_QUEUE_NAME   = azurerm_storage_queue.notifications.name
    EXPO_ACCESS_TOKEN          = var.expo_access_token
    REMINDER_TIMEZONE          = "America/Sao_Paulo"
  }

  tags = var.tags

  lifecycle {
    # O deploy do código (func azure functionapp publish) grava estas chaves
    ignore_changes = [app_settings["WEBSITE_RUN_FROM_PACKAGE"]]
  }
}
