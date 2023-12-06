#Need terraform init in cmd.

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.0.0"
    }
  }
}

#Authentication using Azure Cli.
#https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/azure_cli

provider "azurerm" {
  subscription_id = "placeholder"
  tenant_id       = "placeholder"
  features {}
}



# Create a resource group.
# ***Container that holds related resources for an Azure solution
resource "azurerm_resource_group" "mtc-rc" {
  name     = "mtc-rc"
  location = "East Us"
  tags = {
    environment = "dev"
  }
}


# Creating my VPN. 
resource "azurerm_virtual_network" "mtc-network" {
  name                = "mtc-network"
  location            = azurerm_resource_group.mtc-rc.location
  resource_group_name = azurerm_resource_group.mtc-rc.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "mtc-subnetA" {
  name                 = "mtc-subnetA"
  resource_group_name  = azurerm_resource_group.mtc-rc.name
  virtual_network_name = azurerm_virtual_network.mtc-network.name
  address_prefixes     = ["10.0.1.0/24"]
}

#NIC
resource "azurerm_network_interface" "main" {
  name                = "main"
  location            = azurerm_resource_group.mtc-rc.location
  resource_group_name = azurerm_resource_group.mtc-rc.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.mtc-subnetA.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.mtc-pub-ip.id
  }
  depends_on = [azurerm_virtual_network.mtc-network,
    azurerm_public_ip.mtc-pub-ip,
  azurerm_subnet.mtc-subnetA]
}

#Create VM
resource "azurerm_virtual_machine" "mtc-vm" {
  name                  = "mtc-vm"
  location              = azurerm_resource_group.mtc-rc.location
  resource_group_name   = azurerm_resource_group.mtc-rc.name
  network_interface_ids = [azurerm_network_interface.main.id]
  vm_size               = "Standard_DS1_v2"
  availability_set_id   = azurerm_availability_set.mtc-avset.id

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile_windows_config {
    provision_vm_agent = true
  }
  os_profile {
    computer_name  = "winDatacenter"
    admin_username = "testadmin"
    admin_password = "@zure123!"
  }
  tags = {
    environment = "dev"
  }
  depends_on = [azurerm_network_interface.main,
  azurerm_availability_set.mtc-avset]
}

#Creating my public ip address.
resource "azurerm_public_ip" "mtc-pub-ip" {
  name                = "mtc-pub-ip"
  location            = azurerm_resource_group.mtc-rc.location
  resource_group_name = azurerm_resource_group.mtc-rc.name
  allocation_method   = "Static"
  depends_on = [ azurerm_resource_group.mtc-rc ]
}

#Creating additional disk.
resource "azurerm_managed_disk" "mtc-disk1" {
  name                 = "mtc-disk1"
  location             = azurerm_resource_group.mtc-rc.location
  resource_group_name  = azurerm_resource_group.mtc-rc.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 16
}

#Attaching additional disk to created vm.
resource "azurerm_virtual_machine_data_disk_attachment" "mtc-diskattach" {
  managed_disk_id    = azurerm_managed_disk.mtc-disk1.id
  virtual_machine_id = azurerm_virtual_machine.mtc-vm.id
  lun                = "0"
  caching            = "ReadWrite"
  depends_on = [azurerm_virtual_machine.mtc-vm,
  azurerm_managed_disk.mtc-disk1]
}

#Create an available set.
resource "azurerm_availability_set" "mtc-avset" {
  name                         = "mtc-avset"
  location                     = azurerm_resource_group.mtc-rc.location
  resource_group_name          = azurerm_resource_group.mtc-rc.name
  platform_fault_domain_count  = 3
  platform_update_domain_count = 3
  depends_on = [ azurerm_resource_group.mtc-rc ]
}

#Creating an storage account
resource "azurerm_storage_account" "mtc-storageaccnt" {
  #name                     = var.storage_account_name #Using variables file
  name                     = "mtcstorageaccnt"
  resource_group_name      = azurerm_resource_group.mtc-rc.name
  location                 = azurerm_resource_group.mtc-rc.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags = {
    environment = "dev2s"
  }
}

#Adding a storage container
resource "azurerm_storage_container" "mtc-data" {
  name                  = "mtc-data"
  storage_account_name  = azurerm_storage_account.mtc-storageaccnt.name
  container_access_type = "blob"
  depends_on            = [azurerm_storage_account.mtc-storageaccnt]
}

#Uploading a local file onto container. 
# *** For blob, Container must be implemented first.
resource "azurerm_storage_blob" "iis-config" {
  name                   = "IISConfig.ps1"
  storage_account_name   = azurerm_storage_account.mtc-storageaccnt.name
  storage_container_name = azurerm_storage_container.mtc-data.name
  type                   = "Block"
  source                 = "IISConfig.ps1"
  depends_on             = [azurerm_storage_container.mtc-data]
}

#Install Custom Script Extension
resource "azurerm_virtual_machine_extension" "mtc-vmext" {
  name                 = "mtc-vmext"
  virtual_machine_id   = azurerm_virtual_machine.mtc-vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  depends_on           = [azurerm_storage_blob.iis-config]
  settings             = <<SETTINGS
    {
        "fileUris": ["https://mtcstorageaccnt.blob.core.windows.net/mtc-data/IISConfig.ps1"],
        "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file IISConfig.ps1"     
    }
SETTINGS
} 

resource "azurerm_network_security_group" "app_nsg" {
  name                = "app-nsg"
  location            = azurerm_resource_group.mtc-rc.location
  resource_group_name = azurerm_resource_group.mtc-rc.name

# We are creating a rule to allow traffic on port 80
  security_rule {
    name                       = "Allow_HTTP"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id                 = azurerm_subnet.mtc-subnetA.id
  network_security_group_id = azurerm_network_security_group.app_nsg.id
  depends_on = [
    azurerm_network_security_group.app_nsg
  ]
}
#Bastions
// This subnet is meant for the Azure Bastion service
resource "azurerm_subnet" "Azure_Bastion_Subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.mtc-rc.name
  virtual_network_name = azurerm_virtual_network.mtc-network.name
  address_prefixes     = ["10.0.2.0/24"]
  depends_on = [
    azurerm_virtual_network.mtc-network
  ]
}

resource "azurerm_public_ip" "bastion_ip" {
  name                = "bastion-ip"
  location            = azurerm_resource_group.mtc-rc.location
  resource_group_name = azurerm_resource_group.mtc-rc.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "app_bastion" {
  name                = "app-bastion"
  location            = azurerm_resource_group.mtc-rc.location
  resource_group_name = azurerm_resource_group.mtc-rc.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.Azure_Bastion_Subnet.id
    public_ip_address_id = azurerm_public_ip.bastion_ip.id
  }

  depends_on=[
    azurerm_subnet.Azure_Bastion_Subnet,
    azurerm_public_ip.bastion_ip
  ]
}