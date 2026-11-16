# API Java (manager_back) no Azure Container Apps, no lugar do Render.
# min_replicas >= 1 mantém uma réplica sempre ligada: sem os ~50 s de "cold start" do plano gratuito do Render.
resource "azurerm_container_app_environment" "main" {
  name                       = "cae-aprovia"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Perfil padrão que a Azure cria em todo ambiente novo
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = var.tags
}

resource "azurerm_container_app" "java" {
  name                         = "ca-aprovia-java"
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"

  secret {
    name  = "postgres-password"
    value = random_password.postgres.result
  }

  secret {
    name  = "jwt-secret"
    value = random_bytes.jwt_secret.base64
  }

  secret {
    name  = "storage-connection"
    value = azurerm_storage_account.main.primary_connection_string
  }

  secret {
    name  = "admin-password"
    value = var.java_admin_password
  }

  ingress {
    external_enabled = true
    target_port      = 8090
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.java_min_replicas
    max_replicas = 3

    http_scale_rule {
      name                = "http"
      concurrent_requests = "50"
    }

    container {
      name   = "manager-back"
      image  = var.java_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "POSTGRESHOST"
        value = azurerm_postgresql_flexible_server.main.fqdn
      }
      env {
        name  = "POSTGRESPORT"
        value = "5432"
      }
      env {
        name  = "POSTGRESDATABASE"
        value = azurerm_postgresql_flexible_server_database.aprovia.name
      }
      env {
        name  = "POSTGRESUSER"
        value = azurerm_postgresql_flexible_server.main.administrator_login
      }
      env {
        name        = "POSTGRESPASSWORD"
        secret_name = "postgres-password"
      }
      env {
        name        = "JWT_SECRET_B64"
        secret_name = "jwt-secret"
      }
      env {
        name        = "AZURE_STORAGE_CONNECTION_STRING"
        secret_name = "storage-connection"
      }
      env {
        name        = "ADMIN_PASSWORD"
        secret_name = "admin-password"
      }
      env {
        name  = "PROFILE_PICTURES_CONTAINER"
        value = azurerm_storage_container.profile_pictures.name
      }
      env {
        name  = "JAVA_TOOL_OPTIONS"
        value = "-XX:MaxRAMPercentage=75"
      }

      # O Spring leva ~30 s para subir: até 3 min de tolerância antes de reiniciar
      startup_probe {
        transport               = "HTTP"
        port                    = 8090
        path                    = "/actuator/health"
        interval_seconds        = 10
        failure_count_threshold = 18
      }

      liveness_probe {
        transport               = "HTTP"
        port                    = 8090
        path                    = "/actuator/health"
        interval_seconds        = 30
        failure_count_threshold = 3
      }

      readiness_probe {
        transport               = "HTTP"
        port                    = 8090
        path                    = "/actuator/health"
        interval_seconds        = 10
        failure_count_threshold = 3
      }
    }
  }

  tags = var.tags

  lifecycle {
    # O GitHub Actions publica cada versão nova (az containerapp update --image); o Terraform não volta a imagem
    ignore_changes = [template[0].container[0].image]
  }
}

resource "azurerm_monitor_metric_alert" "java_restarts" {
  name                = "alerta-java-reinicios"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.java.id]
  description         = "A API Java reiniciou mais de 3 vezes em 15 minutos."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "RestartCount"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 3
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }

  tags = var.tags
}
