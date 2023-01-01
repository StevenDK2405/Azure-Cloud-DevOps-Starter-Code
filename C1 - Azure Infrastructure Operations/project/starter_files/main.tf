provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "vmudacity" {
  name     = var.resource_group_name
  location = var.location
  tags = var.tags
}

resource "random_string" "fqdn" {
 length  = 6
 special = false
 upper   = false
 number  = false
}

resource "azurerm_network_security_group" "vmudacity" {
  name                = var.vmudacity-nsg
  location            = azurerm_resource_group.vmudacity.location
  resource_group_name = azurerm_resource_group.vmudacity.name
}

resource "azurerm_network_security_rule" "vmudacity" {
  name                        = "vmudacity-sernet"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "10.0.2.0/24"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.vmudacity.name
  network_security_group_name = azurerm_network_security_group.vmudacity.name
}

resource "azurerm_virtual_network" "vmudacity" {
  name                = "vmudacity-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.vmudacity.name
  tags = var.tags
}

resource "azurerm_subnet" "vmudacity" {
  name                 = "vmudacity-subnet"
  resource_group_name  = azurerm_resource_group.vmudacity.name
  virtual_network_name = azurerm_virtual_network.vmudacity.name
  address_prefixes       = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "vmudacity" {
  name                         = "vmudacity-public-ip"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.vmudacity.name
  allocation_method            = "Static"
  domain_name_label            = random_string.fqdn.result
  tags = var.tags
}

resource "azurerm_lb" "vmudacity" {
  name                = "vmudacity-lb"
  location            = var.location
  resource_group_name = azurerm_resource_group.vmudacity.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.vmudacity.id
  }

  tags = var.tags
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
  loadbalancer_id     = azurerm_lb.vmudacity.id
  name                = var.BackEndAddressPool
}

resource "azurerm_lb_rule" "lbnatrule" {
  loadbalancer_id                = azurerm_lb.vmudacity.id
  name                           = "http"
  protocol                       = "Tcp"
  frontend_port                  = var.application_port
  backend_port                   = var.application_port
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.bpepool.id]
}

resource "azurerm_network_interface" "vmudacity" {  
  count               = var.number
  name                = var.vmudacity-nic[count.index]
  location            = var.location
  resource_group_name = azurerm_resource_group.vmudacity.name

  ip_configuration {
    name                          = "IPConfiguration"
    subnet_id                     = azurerm_subnet.vmudacity.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

resource "azurerm_network_interface_backend_address_pool_association" "vmudacity" {
  count = var.number
  network_interface_id      = azurerm_network_interface.vmudacity[count.index].id
  ip_configuration_name   = "IPConfiguration"
  backend_address_pool_id = azurerm_lb_backend_address_pool.bpepool.id
}

resource "azurerm_network_interface_security_group_association" "vmudacity" {
  count = var.number
  network_interface_id      = azurerm_network_interface.vmudacity[count.index].id
  network_security_group_id = azurerm_network_security_group.vmudacity.id
}

data "azurerm_resource_group" "image" {
  name                = var.packer_resource_group_name
}

data "azurerm_image" "image" {
  name                = var.packer_image_name
  resource_group_name = data.azurerm_resource_group.image.name
}

resource "azurerm_managed_disk" "vmudacity" {
  count = var.number
  name                = var.disks[count.index]
  location            = var.location
  resource_group_name = azurerm_resource_group.vmudacity.name
  create_option  = "Empty"
  storage_account_type = "Standard_LRS"
  disk_size_gb   = 10
  tags = var.tags
}

resource "azurerm_availability_set" "vmudacity" {
  name                = "vmudacity-aset"
  location            = azurerm_resource_group.vmudacity.location
  resource_group_name = azurerm_resource_group.vmudacity.name

  tags = var.tags
}

resource "azurerm_virtual_machine" "vmudacity" {
  count               = var.number
  name                = var.virtual_machine_names[count.index]
  location            = var.location
  resource_group_name = azurerm_resource_group.vmudacity.name
  network_interface_ids = [azurerm_network_interface.vmudacity[count.index].id]
  availability_set_id = azurerm_availability_set.vmudacity.id
  vm_size = "Standard_DS1_v2"
   
  storage_image_reference {
    id=data.azurerm_image.image.id
  }
  
  storage_os_disk {
    name              = var.vmdisks[count.index]
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name = "vmlab"
    admin_username       = var.admin_user
    admin_password       = var.admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
  
  tags = var.tags
}
