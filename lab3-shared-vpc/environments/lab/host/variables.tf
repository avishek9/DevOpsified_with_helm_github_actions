# environments/lab/host/variables.tf

variable "host_project_id" {
  description = "GCP project ID for the Shared VPC host project"
  type        = string
}

variable "service_project_a_id" {
  description = "GCP project ID for service project A (runs GKE)"
  type        = string
}

variable "service_project_b_id" {
  description = "GCP project ID for service project B (IAM binding only)"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}
