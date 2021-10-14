# Author: David Bennett 
# Email: david.bennett.fl@gmail.com

#############
# Providers #
#############

# Configure the Azure provider
provider "azurerm" { 
  # The "feature" block is required for AzureRM provider 2.x. 
  # If you are using version 1.x, the "features" block is not allowed.
  # load_config_file = true
  # config_path = "config"
  version = "~>2.0"
  features {}
}

provider "kubernetes" {
  host                   = "${azurerm_kubernetes_cluster.k8s.kube_config.0.host}"
  username               = "${azurerm_kubernetes_cluster.k8s.kube_config.0.username}"
  password               = "${azurerm_kubernetes_cluster.k8s.kube_config.0.password}"
  client_certificate     = "${base64decode(azurerm_kubernetes_cluster.k8s.kube_config.0.client_certificate)}"
  client_key             = "${base64decode(azurerm_kubernetes_cluster.k8s.kube_config.0.client_key)}"
  cluster_ca_certificate = "${base64decode(azurerm_kubernetes_cluster.k8s.kube_config.0.cluster_ca_certificate)}"
}

###################
# Resource Groups #
###################

resource "azurerm_resource_group" "k8s" {
    name     = var.resource_group_name
    location = var.location
}

##############
# random ids #
##############

resource "random_id" "log_analytics_workspace_name_suffix" {
    byte_length = 8
}

resource "random_id" "keyvault" {
    byte_length = 4
}

#######################
# Azure client config #
#######################

data "azurerm_client_config" "current" {}

#################
# Log Analytics #
#################

resource "azurerm_log_analytics_workspace" "test" {
    # The WorkSpace name has to be unique across the whole of azure, not just the current subscription/tenant.
    name                = var.log_analytics_workspace_name #-${random_id.log_analytics_workspace_name_suffix.dec}"
    location            = var.log_analytics_workspace_location
    resource_group_name = azurerm_resource_group.k8s.name
    sku                 = var.log_analytics_workspace_sku
}

resource "azurerm_log_analytics_solution" "test" {
    solution_name         = var.solutionName 
    location              = azurerm_log_analytics_workspace.test.location
    resource_group_name   = azurerm_resource_group.k8s.name
    workspace_resource_id = azurerm_log_analytics_workspace.test.id
    workspace_name        = azurerm_log_analytics_workspace.test.name

    plan {
        publisher = "Microsoft"
        product   = "OMSGallery/ContainerInsights"
    }
}

#############
# Key Vault #
#############

resource "azurerm_key_vault" "k8svault" {
  name                        =  var.keyVaultName
  location                    = azurerm_resource_group.k8s.location
  resource_group_name         = azurerm_resource_group.k8s.name
  enabled_for_disk_encryption = var.KeyVaultDiskEncryptionEnabled
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = var.KeyVaultSoftDeleterRetentionDays
  purge_protection_enabled    = var.KeyVaultPurgeProtectionEnabled
  sku_name = var.KeyVaultSkuName

  access_policy {
    tenant_id = var.tenant_id
    object_id = data.azurerm_client_config.current.object_id
      #application_id =

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get",
      "purge",
    ]

    storage_permissions = [
      "Get",
    ]
  }
 
  access_policy {
    tenant_id = var.tenant_id
    object_id = data.azurerm_client_config.current.object_id
      #application_id = 
	
    key_permissions = [
      "get",
	  "list",
	  "create",
      "delete",
    ]

    secret_permissions = [
      "get",
	  "list",
	  "set",
      "delete",
      "purge",
    ]
  }
}

####################
# KeyVault Secrets #
####################

resource "azurerm_key_vault_secret" "k8svaultSecret" {
  name         = "#####"
  value        = "#####"
  key_vault_id = azurerm_key_vault.k8svault.id
}

resource "azurerm_key_vault_secret" "k8svaultSecret2" {
  name         = "testSecret"
  value        = file(var.test_secret_value)
  key_vault_id = azurerm_key_vault.k8svault.id
}

resource "azurerm_key_vault_secret" "k8svaultSecret3" {
  name         = "testSecret2"
  value        = file(var.test_php)
  key_vault_id = azurerm_key_vault.k8svault.id
}

#####################################################################
# Example for the php app secrets this will replace the above items #
#####################################################################

# resource "azurerm_key_vault_secret" "k8svaultExampleSecret" {
#   name         = "exampleSecret"
#   value        = file(var.exampleSecret)
#   key_vault_id = azurerm_key_vault.k8svault.id
# }

#####################
# User assinged ids #
#####################

resource "azurerm_user_assigned_identity" "k8s" {
  name                =  var.managed_id # "aks-example-identity"
  resource_group_name = azurerm_resource_group.k8s.name
  location            = azurerm_resource_group.k8s.location
}

resource "azurerm_user_assigned_identity" "k8svault" {
  name                =  var.managed_id2 # "aks-example-identity"
  resource_group_name = azurerm_resource_group.k8s.name
  location            = azurerm_resource_group.k8s.location
}

resource "azurerm_role_assignment" "k8sClusterRole" {
  scope                = azurerm_kubernetes_cluster.k8s.id
  role_definition_name = var.UserAssingedId_Cluster_RoleDefinitionName
  principal_id         = azurerm_user_assigned_identity.k8s.principal_id
}

resource "azurerm_role_assignment" "k8sRg_Role" {
  scope                = azurerm_resource_group.k8s.id
  role_definition_name = var.UserAssingedId_RG_RoleDefinitionName
  principal_id         = azurerm_user_assigned_identity.k8svault.principal_id
}

resource "azurerm_role_assignment" "k8sVaultRole" {
  scope                = azurerm_key_vault.k8svault.id
  role_definition_name = var.UserAssingedId_KeyVault_RoleDefinitionName
  principal_id         = azurerm_user_assigned_identity.k8svault.principal_id
}


###############
# K8s Cluster #
###############

resource "azurerm_kubernetes_cluster" "k8s" {
    name                = var.cluster_name
    location            = azurerm_resource_group.k8s.location
    resource_group_name = azurerm_resource_group.k8s.name
    dns_prefix          = var.dns_prefix
    private_cluster_enabled = var.PrivateClusterEnabled

    linux_profile {
        admin_username = var.admin_username
        ssh_key {
            key_data = file(var.ssh_public_key)
        }
    }
    
    default_node_pool {
        name            = var.default_node_pool_name
        node_count      = var.agent_count
        vm_size         = var.ClusterVmSize
        #vnet_subnet_id  =
    }

    service_principal {
        client_id     = var.client_id
        client_secret = var.client_secret
    }

    addon_profile {
        oms_agent {
        enabled                    = var.ClusterAddOnOmsAgentEnabled
        log_analytics_workspace_id = azurerm_log_analytics_workspace.test.id
        }
        # kube_dashboard {
        # enabled = var.kube_dashboard_enabled
        # }

    }
   
    network_profile {
    load_balancer_sku = var.ClusterLoadBalancerSku
    network_plugin = var.ClusterNetworkPlugin
    #service_cidr = 
    #docker_bridge_cidr =
    #dns_service_ip = 
    #network_plugin = "kubenet"
    }

    tags = {
        Environment = var.ClusterEnviromentTag
    } 

    role_based_access_control {
        enabled = var.ClusterRbacEnabled
    }

    # depends_on = [
    #   azurerm_role_assignment.k8s,
    # ]
}

#############
# Namespace #
#############

resource "kubernetes_namespace" "k8s" {
  metadata {
    annotations = {
      name = var.NamespaceAnnotationName  
    }
    
    # annotations = {
    #   name = "Test-Annotation"
    # }

    labels = {
      mylabel = var.NamespaceLabel 
    }
  
    # labels = {
    #   mylabel = "test-label"
    # }

    name = var.NamespaceName
    # name = "terraform-test-namespace"
  }
  depends_on = [
      azurerm_kubernetes_cluster.k8s,
    ]
}


#########
Subnet #
#########

resource "azurerm_subnet" "akspodssubnet" {
  name                        = "akspodssubnet"
  resource_group_name         = azurerm_resource_group.rg.name
  virtual_network_name        = azurerm_virtual_network.vnet.name
  address_prefix              = var.akspodssubnet
}

#####################
Container Registry #
#####################

resource "azurerm_container_registry" "k8s" {
  name                     = "containerRegistryTLH330"
  resource_group_name      = azurerm_resource_group.k8s.name
  location                 = azurerm_resource_group.k8s.location
  sku                      = "Standard"
  admin_enabled            = false
  #georeplication_locations = ["East US","West Europe"]
}