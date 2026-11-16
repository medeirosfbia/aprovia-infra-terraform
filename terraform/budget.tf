# Orçamento mensal da assinatura: avisa por e-mail antes de o crédito de estudante acabar
resource "azurerm_consumption_budget_subscription" "mensal" {
  count           = var.budget_amount > 0 ? 1 : 0
  name            = "orcamento-aprovia"
  subscription_id = "/subscriptions/${var.subscription_id}"
  amount          = var.budget_amount
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 50
    threshold_type = "Actual"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = [var.alert_email]
  }

  notification {
    enabled        = true
    threshold      = 80
    threshold_type = "Actual"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = [var.alert_email]
    contact_groups = [azurerm_monitor_action_group.email.id]
  }

  # Previsão: avisa quando o ritmo de gasto vai estourar o orçamento até o fim do mês (ex.: HA do Postgres esquecida ligada)
  notification {
    enabled        = true
    threshold      = 100
    threshold_type = "Forecasted"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = [var.alert_email]
    contact_groups = [azurerm_monitor_action_group.email.id]
  }

  lifecycle {
    # A Azure guarda a data de início; mudar a variável depois não recria o orçamento
    ignore_changes = [time_period]
  }
}
