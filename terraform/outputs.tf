output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "storage_connection_string" {
  description = "Já configurada na VM, na Function App e no Container App."
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "applicationinsights_connection_string" {
  description = "Já configurada na VM e na Function App."
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "function_app_name" {
  description = "Publicar com: func azure functionapp publish <nome> (em consumers_messaging/my_func_history)."
  value       = azurerm_linux_function_app.consumers.name
}

output "workbook_url" {
  value = "https://portal.azure.com/#@/resource${azurerm_application_insights_workbook.ambiente.id}/workbook"
}

output "api_python_url" {
  description = "URL da API Python (EXPO_PUBLIC_API_URL no app e variável da API no front)."
  value       = "https://${local.api_domain}"
}

output "api_java_url" {
  description = "URL da API Java (EXPO_PUBLIC_AUTH_API no app e variável de auth no front)."
  value       = "https://${azurerm_container_app.java.ingress[0].fqdn}"
}

output "vm_ssh" {
  value = "ssh azureuser@${local.api_domain}"
}

output "jwt_secret_b64" {
  description = "Chave JWT compartilhada pelas duas APIs (já configurada nelas pelo Terraform)."
  value       = random_bytes.jwt_secret.base64
  sensitive   = true
}

output "recovery_vault_name" {
  value = azurerm_recovery_services_vault.main.name
}


output "postgres_fqdn" {
  description = "Host do PostgreSQL (para acessar com psql)."
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgres_password" {
  value     = random_password.postgres.result
  sensitive = true
}
