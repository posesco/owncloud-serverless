variable "organization" {
  description = "The Name of your organization"
  type        = string
  default     = "yourOrg"
}

variable "region" {
  description = "The region Terraform deploy your instance"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "The project Name"
  type        = string
  default     = "owncloud"
}

variable "aws_iam_role" {
  description = "Role IAM capable of executing ECS tasks"
  type        = string
  default     = "ecsTaskExecutionRole"
}

variable "db_username" {
  description = "Database administrator username"
  type        = string
  sensitive   = true
  default     = "administrator"
}

variable "db_password" {
  description = "Database administrator password"
  type        = string
  sensitive   = true
  default     = "nNos2FrQ54ad5ef54j0cXZhfv"
}

variable "tags" {
  description = "Default tag Environment"
  type        = map(any)
  default = {
    Terraform   = "true"
    Environment = "dev"
  }
}
