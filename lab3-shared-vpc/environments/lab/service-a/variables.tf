# environments/lab/service-a/variables.tf

variable "service_project_id" {
  description = "Service project A project ID"
  type        = string
}

variable "host_project_id" {
  description = "Host project ID — needed for cross-project resource references"
  type        = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "state_bucket" {
  description = "GCS bucket holding Terraform state — used to read host project outputs"
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "/28 CIDR for the GKE control plane in service project A"
  type        = string
  default     = "172.16.0.16/28"
  # Use a different /28 than service project B to avoid overlap.
  # Host project master CIDR (from lab2-gke) used 172.16.0.0/28.
  # Service A: 172.16.0.16/28, Service B: 172.16.0.32/28
}
