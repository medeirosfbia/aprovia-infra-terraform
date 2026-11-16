# Liga a VM às 08:00 (Brasília) de segunda a sexta; o desligamento às 23:30 fica no vm.tf.
# A Logic App chama a API da Azure com a própria identidade gerenciada, que só pode operar esta VM.
resource "azurerm_logic_app_workflow" "vm_start" {
  count               = var.vm_auto_start ? 1 : 0
  name                = "logic-aprovia-vm-start"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_logic_app_trigger_recurrence" "dias_uteis" {
  count        = var.vm_auto_start ? 1 : 0
  name         = "dias-uteis-8h"
  logic_app_id = azurerm_logic_app_workflow.vm_start[0].id
  frequency    = "Week"
  interval     = 1
  time_zone    = "E. South America Standard Time"

  schedule {
    on_these_days    = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    at_these_hours   = [8]
    at_these_minutes = [0]
  }
}

resource "azurerm_logic_app_action_custom" "ligar_vm" {
  count        = var.vm_auto_start ? 1 : 0
  name         = "ligar-vm"
  logic_app_id = azurerm_logic_app_workflow.vm_start[0].id

  body = jsonencode({
    type     = "Http"
    runAfter = {}
    inputs = {
      method = "POST"
      uri    = "https://management.azure.com${azurerm_linux_virtual_machine.api.id}/start?api-version=2024-07-01"
      authentication = {
        type     = "ManagedServiceIdentity"
        audience = "https://management.azure.com/"
      }
    }
  })
}

resource "azurerm_role_assignment" "logic_vm_start" {
  count                = var.vm_auto_start ? 1 : 0
  scope                = azurerm_linux_virtual_machine.api.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_logic_app_workflow.vm_start[0].identity[0].principal_id
}
