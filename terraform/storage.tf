# Storage Account única: Blob (materiais, fotos, backups), Queue (mensageria) e armazenamento da Function App
resource "azurerm_storage_account" "main" {
  name                            = "staprovia${local.suffix}"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = var.storage_replication
  access_tier                     = "Hot"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled            = true
    change_feed_enabled           = true
    change_feed_retention_in_days = 30

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }

    # Point-in-time restore: precisa ser menor que a retenção do soft delete
    restore_policy {
      days = 7
    }
  }

  tags = var.tags
}

# Blob Storage
resource "azurerm_storage_container" "materiais" {
  name                  = "aprovia-materiais"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "profile_pictures" {
  name                  = "aprovia-profile-pictures"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "backups" {
  name                  = "aprovia-backups"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

# Queue Storage
resource "azurerm_storage_queue" "chat_history" {
  name                 = "aprovia-chat-history"
  storage_account_name = azurerm_storage_account.main.name
}

resource "azurerm_storage_queue" "notifications" {
  name                 = "aprovia-notifications"
  storage_account_name = azurerm_storage_account.main.name
}

# Ciclo de vida: dumps do MongoDB vão para Cool em 7 dias e são apagados em 90 (Archive não existe em contas ZRS)
resource "azurerm_storage_management_policy" "main" {
  storage_account_id = azurerm_storage_account.main.id

  rule {
    name    = "backups-mongodb"
    enabled = true

    filters {
      prefix_match = ["aprovia-backups/mongodb/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 7
        delete_after_days_since_modification_greater_than       = 90
      }
    }
  }

  rule {
    name    = "versoes-antigas"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = 30
      }
    }
  }
}
