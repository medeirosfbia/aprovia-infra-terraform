resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  suffix = random_string.suffix.result
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}
