# environments/lab/service-b/variables.tf

variable "service_project_id" {
  type = string
}

variable "host_project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "state_bucket" {
  type = string
}
