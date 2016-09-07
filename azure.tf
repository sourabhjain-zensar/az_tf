variable "subscription_id" {}
variable "client_id" {}
variable "client_secret" {}
variable "tenant_id" {}

# Configure the Azure Resource Manager Provider
provider "azurerm" {
  subscription_id = "${var.subscription_id}"
  client_id       = "${var.client_id}"
  client_secret   = "${var.client_secret}"
  tenant_id       = "${var.tenant_id}"
}

# Create a resource group
resource "azurerm_resource_group" "production" {
    name     = "production"
    location = "West US"
}

# Create a virtual network in the web_servers resource group
resource "azurerm_virtual_network" "productionNetwork" {
  name                = "productionNetwork"
  address_space       = ["11.0.0.0/16"]
  location            = "West US"
  resource_group_name = "${azurerm_resource_group.production.name}"
  #depends_on = ["azurerm_virtual_machine.webprod01"]
/*  provisioner "chef" {
                server_url = "https://manage.chef.io/organizations/waseema"
                validation_client_name = "waseema-validator"
                validation_key = "/home/jenkins/Terraform_config_files/chef/chef-repo/.chef/waseema-validator.pem"
                node_name = "Webserver"
                run_list = ["role[windowsrole]"]
                environment = "production"
                ssl_verify_mode = ":verify_none"
                connection {
                        type = "winrm"
                        user = "zenadmin"
                        password = "Redhat#10"      
                        host = "${azurerm_public_ip.prodweb01pub.ip_address}"
			timeout = "20m"
		}
  }
*/
}

resource "azurerm_subnet" "public" {
    name = "public"
    resource_group_name = "${azurerm_resource_group.production.name}"
    virtual_network_name = "${azurerm_virtual_network.productionNetwork.name}"
    address_prefix = "11.0.1.0/24"
    network_security_group_id = "${azurerm_network_security_group.prodwebNSG.id}"
}

resource "azurerm_subnet" "private" {
    name = "private"
    resource_group_name = "${azurerm_resource_group.production.name}"
    virtual_network_name = "${azurerm_virtual_network.productionNetwork.name}"
    address_prefix = "11.0.2.0/24"
    network_security_group_id = "${azurerm_network_security_group.proddbNSG.id}"
}

resource "azurerm_dns_zone" "azureprod" {
   name = "azr.zencloud.com"
   resource_group_name = "${azurerm_resource_group.production.name}"
}

resource "azurerm_dns_a_record" "azureprod_a_web_pub" {
   name = "web_pub"
   zone_name = "${azurerm_dns_zone.azureprod.name}"
   resource_group_name = "${azurerm_resource_group.production.name}"
   ttl = "300"
   records = ["${azurerm_public_ip.prodweb01pub.ip_address}"]
}

resource "azurerm_dns_a_record" "azureprod_a_web_pri" {
   name = "web_pri"
   zone_name = "${azurerm_dns_zone.azureprod.name}"
   resource_group_name = "${azurerm_resource_group.production.name}"
   ttl = "300"
   records = ["${azurerm_network_interface.prodwebpudinter.private_ip_address}"]
}


resource "azurerm_dns_a_record" "zenprod_a_app" {
   name = "app"
   zone_name = "${azurerm_dns_zone.azureprod.name}"
   resource_group_name = "${azurerm_resource_group.production.name}"
   ttl = "300"
   records = ["${azurerm_network_interface.proddbpudinter.private_ip_address}"]
}

resource "azurerm_public_ip" "prodweb01pub" {
    name = "prodweb01pub"
    location = "West US"
    resource_group_name = "${azurerm_resource_group.production.name}"
    public_ip_address_allocation = "static"
}

resource "azurerm_network_interface" "prodwebpudinter" {
    name = "prodwebpudinter"
    location = "West US"
    resource_group_name = "${azurerm_resource_group.production.name}"
    network_security_group_id = "${azurerm_network_security_group.prodwebNSG.id}"

    ip_configuration {
        name = "prodconfiguration1"
        subnet_id = "${azurerm_subnet.public.id}"
        private_ip_address_allocation = "dynamic"
	public_ip_address_id = "${azurerm_public_ip.prodweb01pub.id}"
	#load_balancer_backend_address_pools_ids = ["${azurerm_simple_lb.prodwebpudinter.backend_pool_id}"]
    }
}

resource "azurerm_network_interface" "proddbpudinter" {
    name = "proddbpudinter"
    location = "West US"
    resource_group_name = "${azurerm_resource_group.production.name}"

    ip_configuration {
        name = "prodconfiguration1"
        subnet_id = "${azurerm_subnet.private.id}"
        private_ip_address_allocation = "dynamic"
    }
}

resource "azurerm_storage_account" "swebacnt" {
    name = "swebacnt"
    resource_group_name = "${azurerm_resource_group.production.name}"
    location = "westus"
    account_type = "Standard_LRS"
    tags {
        environment = "staging"
    }
}

resource "azurerm_storage_container" "swebcont" {
    name = "swebcont"
    resource_group_name = "${azurerm_resource_group.production.name}"
    storage_account_name = "${azurerm_storage_account.swebacnt.name}"
    container_access_type = "private"
}

resource "azurerm_storage_blob" "swebblob" {
    name = "swebblob.vhd"

    resource_group_name = "${azurerm_resource_group.production.name}"
    storage_account_name = "${azurerm_storage_account.swebacnt.name}"
    storage_container_name = "${azurerm_storage_container.swebcont.name}"
    type = "page"
    size = 5120
}

resource "azurerm_virtual_machine" "webprod01" {
    name = "webprod01"
    location = "West US"
    resource_group_name = "${azurerm_resource_group.production.name}"
    network_interface_ids = ["${azurerm_network_interface.prodwebpudinter.id}"]
    vm_size = "Standard_A0"


    storage_image_reference {
        publisher = "MicrosoftWindowsServer"
        offer = "WindowsServer"
        sku = "2008-R2-SP1"
        version = "latest"
    }
	
    storage_os_disk {
        name = "myosdisk1"
        vhd_uri = "${azurerm_storage_account.swebacnt.primary_blob_endpoint}${azurerm_storage_container.swebcont.name}/myosdisk1.vhd"
        caching = "ReadWrite"
        create_option = "FromImage"
    }

    os_profile {
        computer_name = "webprod01"
        admin_username = "zenadmin"
        admin_password = "Redhat#12345"
    }

    os_profile_windows_config {
        enable_automatic_upgrades = false
    }
	
    tags {
        environment = "staging"
    }
}

resource "azurerm_storage_account" "sdbacnt" {
    name = "sdbacnt"
    resource_group_name = "${azurerm_resource_group.production.name}"
    location = "westus"
    account_type = "Standard_LRS"
	tags {
        environment = "staging"
    }
}

resource "azurerm_storage_container" "sdbcont" {
    name = "sdbcont"
    resource_group_name = "${azurerm_resource_group.production.name}"
    storage_account_name = "${azurerm_storage_account.sdbacnt.name}"
    container_access_type = "private"
}

resource "azurerm_storage_blob" "sdbblob" {
    name = "sdbblob.vhd"
    resource_group_name = "${azurerm_resource_group.production.name}"
    storage_account_name = "${azurerm_storage_account.sdbacnt.name}"
    storage_container_name = "${azurerm_storage_container.sdbcont.name}"
    type = "page"
    size = 5120
}

resource "azurerm_virtual_machine" "dbprod01" {
    name = "dbprod01"
    location = "West US"
    resource_group_name = "${azurerm_resource_group.production.name}"
    network_interface_ids = ["${azurerm_network_interface.proddbpudinter.id}"]
    vm_size = "Standard_A0"

    storage_image_reference {
        publisher = "Canonical"
        offer = "UbuntuServer"
        sku = "14.04.2-LTS"
        version = "latest"
    }
	
    storage_os_disk {
        name = "myosdisk1"
        vhd_uri = "${azurerm_storage_account.sdbacnt.primary_blob_endpoint}${azurerm_storage_container.sdbcont.name}/myosdisk1.vhd"
        caching = "ReadWrite"
        create_option = "FromImage"
    }

    os_profile {
        computer_name = "webprod01"
        admin_username = "zenadmin"
        admin_password = "Redhat#12345"
    }

    os_profile_windows_config {
        enable_automatic_upgrades = false
    }
	
    tags {
        environment = "staging"
    }
}

resource "azurerm_network_security_group" "prodwebNSG" {
    name = "prodwebNSG"
    location = "West US"
    resource_group_name = "${azurerm_resource_group.production.name}"
}

resource "azurerm_network_security_rule" "HTTP" {
    name = "HTTP"
    priority = 100
	direction = "Inbound"
	access = "Allow"
	protocol = "TCP"
	source_port_range = "*"
	destination_port_range = "80"
	source_address_prefix = "0.0.0.0"
	destination_address_prefix = "*"
    resource_group_name = "${azurerm_resource_group.production.name}"
    network_security_group_name = "${azurerm_network_security_group.prodwebNSG.name}"
}

resource "azurerm_network_security_rule" "HTTPS" {
    name = "HTTPS"
    priority = 200
        direction = "Inbound"
        access = "Allow"
        protocol = "TCP"
        source_port_range = "*"
        destination_port_range = "443"
        source_address_prefix = "0.0.0.0"
        destination_address_prefix = "*"
    resource_group_name = "${azurerm_resource_group.production.name}"
    network_security_group_name = "${azurerm_network_security_group.prodwebNSG.name}"
}

resource "azurerm_network_security_rule" "RDP-web" {
    name = "RDP-web"
    priority = 300
        direction = "Inbound"
        access = "Allow"
        protocol = "TCP"
        source_port_range = "*"
        destination_port_range = "3389"
        source_address_prefix = "0.0.0.0"
        destination_address_prefix = "*"
    resource_group_name = "${azurerm_resource_group.production.name}"
    network_security_group_name = "${azurerm_network_security_group.prodwebNSG.name}"
}

resource "azurerm_network_security_rule" "Winrm" {
    name = "Winrm"
    priority = 400
        direction = "Inbound"
        access = "Allow"
        protocol = "TCP"
        source_port_range = "*"
        destination_port_range = "5985"
        source_address_prefix = "0.0.0.0"
        destination_address_prefix = "*"
    resource_group_name = "${azurerm_resource_group.production.name}"
    network_security_group_name = "${azurerm_network_security_group.prodwebNSG.name}"
}

resource "azurerm_network_security_rule" "HTTP-out" {
    name = "HTTP-out"
    priority = 100
        direction = "Outbound"
        access = "Allow"
        protocol = "TCP"
        source_port_range = "0"
        destination_port_range = "65535"
        source_address_prefix = "0.0.0.0"
        destination_address_prefix = "*"
    resource_group_name = "${azurerm_resource_group.production.name}"
    network_security_group_name = "${azurerm_network_security_group.prodwebNSG.name}"
}

resource "azurerm_network_security_rule" "HTTPS-out" {
    name = "HTTPS-out"
    priority = 200
        direction = "Outbound"
        access = "Allow"
        protocol = "TCP"
        source_port_range = "0"
        destination_port_range = "65535"
        source_address_prefix = "0.0.0.0"
        destination_address_prefix = "*"
    resource_group_name = "${azurerm_resource_group.production.name}"
    network_security_group_name = "${azurerm_network_security_group.prodwebNSG.name}"
}

resource "azurerm_network_security_rule" "Winrm-out" {
    name = "Winrm-out"
    priority = 300
        direction = "Outbound"
        access = "Allow"
        protocol = "TCP"
        source_port_range = "*"
        destination_port_range = "5985"
        source_address_prefix = "0.0.0.0"
        destination_address_prefix = "*"
    resource_group_name = "${azurerm_resource_group.production.name}"
    network_security_group_name = "${azurerm_network_security_group.prodwebNSG.name}"
}


resource "azurerm_network_security_group" "proddbNSG" {
    name = "proddbNSG"
    location = "West US"
    resource_group_name = "${azurerm_resource_group.production.name}"
}

resource "azurerm_network_security_rule" "RDP-App" {
    name = "RDP-App"
    priority = 100
	direction = "Inbound"
	access = "Allow"
	protocol = "TCP"
	source_port_range = "*"
	destination_port_range = "3389"
	source_address_prefix = "0.0.0.0"
	destination_address_prefix = "*"
    resource_group_name = "${azurerm_resource_group.production.name}"
    network_security_group_name = "${azurerm_network_security_group.proddbNSG.name}"
}

resource "azurerm_network_security_rule" "R1443" {
    name = "R1433"
    priority = 200
        direction = "Inbound"
        access = "Allow"
        protocol = "TCP"
        source_port_range = "*"
        destination_port_range = "1443"
        source_address_prefix = "0.0.0.0"
        destination_address_prefix = "*"
    resource_group_name = "${azurerm_resource_group.production.name}"
    network_security_group_name = "${azurerm_network_security_group.proddbNSG.name}"
}
