# environments/prod/variables.tf

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for the cluster"
  type        = string
  default     = "us-central1"
}

variable "vpc_name" {
  description = "VPC network name (must already exist — use lab1-vpc module output)"
  type        = string
}

variable "subnet_name" {
  description = "Subnet name for cluster nodes (must already exist)"
  type        = string
}

variable "pods_range_name" {
  description = "Secondary range name for pod IPs"
  type        = string
}

variable "services_range_name" {
  description = "Secondary range name for service IPs"
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "/28 CIDR for the control plane internal IP. Cannot be changed after creation."
  type        = string
  default     = "172.16.0.0/28"
}
