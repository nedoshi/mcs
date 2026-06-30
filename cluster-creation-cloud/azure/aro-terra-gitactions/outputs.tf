output "aro_cluster_id" {
  description = "The ID of the Azure Red Hat OpenShift cluster."
  value       = azapi_resource.aro_cluster.id
}

output "aro_cluster_name" {
  description = "The name of the Azure Red Hat OpenShift cluster."
  value       = azapi_resource.aro_cluster.name
}

output "aro_cluster_location" {
  description = "The location of the Azure Red Hat OpenShift cluster."
  value       = azapi_resource.aro_cluster.location
}

output "aro_cluster_domain" {
  description = "The domain of the Azure Red Hat OpenShift cluster."
  value       = var.domain
  sensitive   = false
}

output "aro_cluster_console_url" {
  description = "The console URL of the Azure Red Hat OpenShift cluster."
  value       = try(jsondecode(azapi_resource.aro_cluster.output).properties.consoleProfile.url, null)
}

output "aro_cluster_api_server_url" {
  description = "The API server URL of the Azure Red Hat OpenShift cluster."
  value       = try(jsondecode(azapi_resource.aro_cluster.output).properties.apiserverProfile.url, null)
}

output "virtual_network_id" {
  description = "The ID of the virtual network."
  value       = azurerm_virtual_network.virtual_network.id
}

output "virtual_network_name" {
  description = "The name of the virtual network."
  value       = azurerm_virtual_network.virtual_network.name
}

output "master_subnet_id" {
  description = "The ID of the master subnet."
  value       = azurerm_subnet.master_subnet.id
}

output "worker_subnet_id" {
  description = "The ID of the worker subnet."
  value       = azurerm_subnet.worker_subnet.id
}

output "resource_group_name" {
  description = "The name of the resource group."
  value       = var.resource_group_name
}

