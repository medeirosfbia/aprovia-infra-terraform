# VM da API Python + Ollama + ChromaDB, instalada pelo cloud-init (templates/vm-cloud-init.yaml.tftpl)
resource "random_bytes" "jwt_secret" {
  length = 64
}

locals {
  api_domain = azurerm_public_ip.vm.fqdn

  # Variáveis de ambiente da API Python (/etc/aprovia/api.env)
  api_env = {
    TEMP_FOLDER                           = "./_temp"
    CHROMA_PATH                           = "chroma"
    COLLECTION_NAME                       = "aprovia"
    TEXT_EMBEDDING_MODEL                  = "nomic-embed-text"
    URL_CONNECTION_MONGODB                = var.mongo_connection_string
    DATABASE_NAME                         = var.mongo_db_name
    ASSISTANT_COLLECTION                  = "assistant"
    JWT_SECRET_B64                        = random_bytes.jwt_secret.base64
    ADMIN_USERS                           = var.admin_users
    CORS_ORIGINS                          = var.cors_origins
    REMINDER_TIMEZONE                     = "America/Sao_Paulo"
    AZURE_STORAGE_CONNECTION_STRING       = azurerm_storage_account.main.primary_connection_string
    QUEUE_NAME                            = azurerm_storage_queue.chat_history.name
    NOTIFICATIONS_QUEUE_NAME              = azurerm_storage_queue.notifications.name
    MATERIALS_CONTAINER                   = azurerm_storage_container.materiais.name
    MATERIALS_MAX_SIZE_MB                 = "50"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
    OTEL_SERVICE_NAME                     = "aprovia-api-python"
  }
}

resource "azurerm_linux_virtual_machine" "api" {
  name                            = "vm-aprovia-api"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = var.vm_size
  zone                            = var.vm_zone
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
  }

  os_disk {
    name                 = "osdisk-aprovia-api"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Identidade gerenciada: exigida pelo Azure Monitor Agent
  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {}

  custom_data = base64encode(templatefile("${path.module}/templates/vm-cloud-init.yaml.tftpl", {
    api_env       = local.api_env
    domain        = local.api_domain
    email         = var.alert_email
    repo_url      = var.api_repo_url
    repo_branch   = var.api_repo_branch
    ollama_models = "nomic-embed-text qwen2-math llama3"
    backup_script = file("${path.module}/../scripts/backup_mongodb.sh")
  }))

  tags = var.tags

  lifecycle {
    # O cloud-init só roda na criação; mudar o .env depois é feito na VM, sem recriá-la
    ignore_changes = [custom_data]
  }
}

# Desligamento automático diário para economizar crédito (opcional: derruba a API à noite)
resource "azurerm_dev_test_global_vm_shutdown_schedule" "api" {
  count                 = var.vm_auto_shutdown ? 1 : 0
  virtual_machine_id    = azurerm_linux_virtual_machine.api.id
  location              = azurerm_resource_group.main.location
  enabled               = true
  daily_recurrence_time = "2330"
  timezone              = "E. South America Standard Time"

  notification_settings {
    enabled         = true
    email           = var.alert_email
    time_in_minutes = 30
  }

  tags = var.tags
}

# Azure Monitor Agent + regra de coleta: CPU, memória, disco e syslog da VM no Log Analytics
resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.api.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = var.tags
}

resource "azurerm_monitor_data_collection_rule" "vm" {
  name                = "dcr-aprovia-vm"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kind                = "Linux"

  destinations {
    log_analytics {
      name                  = "log-aprovia"
      workspace_resource_id = azurerm_log_analytics_workspace.main.id
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Syslog"]
    destinations = ["log-aprovia"]
  }

  data_sources {
    performance_counter {
      name                          = "perf-basico"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor(*)\\% Processor Time",
        "\\Memory(*)\\% Used Memory",
        "\\Memory(*)\\Available MBytes Memory",
        "\\Logical Disk(*)\\% Used Space",
        "\\Network(*)\\Total Bytes Transmitted",
        "\\Network(*)\\Total Bytes Received",
      ]
    }

    syslog {
      name           = "syslog-servicos"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["daemon", "auth", "syslog"]
      log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_data_collection_rule_association" "vm" {
  name                    = "dcra-aprovia-vm"
  target_resource_id      = azurerm_linux_virtual_machine.api.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.vm.id
}

resource "azurerm_monitor_metric_alert" "vm_cpu" {
  name                = "alerta-vm-cpu-alta"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_virtual_machine.api.id]
  description         = "CPU da VM acima de 80% por 15 minutos."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "vm_availability" {
  name                = "alerta-vm-indisponivel"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_virtual_machine.api.id]
  description         = "A VM ficou indisponível."
  severity            = 0
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "VmAvailabilityMetric"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }

  tags = var.tags
}

# Azure Backup da VM: backup diário às 03:00 (Brasília)
resource "azurerm_recovery_services_vault" "main" {
  name                = "rsv-aprovia"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  storage_mode_type   = "GeoRedundant"
  tags                = var.tags
}

resource "azurerm_backup_policy_vm" "daily" {
  name                = "politica-diaria-aprovia"
  resource_group_name = azurerm_resource_group.main.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  timezone            = "E. South America Standard Time"

  instant_restore_retention_days = 2

  backup {
    frequency = "Daily"
    time      = "03:00"
  }

  retention_daily {
    count = 7
  }

  retention_weekly {
    count    = 4
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 3
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }
}

resource "azurerm_backup_protected_vm" "api" {
  resource_group_name = azurerm_resource_group.main.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  source_vm_id        = azurerm_linux_virtual_machine.api.id
  backup_policy_id    = azurerm_backup_policy_vm.daily.id
}
