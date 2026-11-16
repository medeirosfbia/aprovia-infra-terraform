resource "azurerm_virtual_network" "main" {
  name                = "vnet-aprovia"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.10.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_network_security_group" "vm" {
  name                = "nsg-aprovia-vm"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  security_rule {
    name                       = "http-https"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # SSH só do IP de quem administra; sem admin_ip_cidr a porta 22 fica fechada
  dynamic "security_rule" {
    for_each = var.admin_ip_cidr == "" ? [] : [var.admin_ip_cidr]
    content {
      name                       = "ssh-admin"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = security_rule.value
      destination_address_prefix = "*"
    }
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "vm" {
  subnet_id                 = azurerm_subnet.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

# IP fixo com nome DNS da Azure: <label>.<região>.cloudapp.azure.com, usado no certificado HTTPS
resource "azurerm_public_ip" "vm" {
  name                = "pip-aprovia-api"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [var.vm_zone]
  domain_name_label   = "aprovia-api-${local.suffix}"
  tags                = var.tags
}

resource "azurerm_network_interface" "vm" {
  name                = "nic-aprovia-api"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  ip_configuration {
    name                          = "principal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }

  tags = var.tags
}
