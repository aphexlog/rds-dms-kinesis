variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "The VPC ID to deploy resources in"
  type        = string
}

variable "subnet_ids" {
  description = "The subnet IDs to deploy resources in"
  type        = list(string)
}

variable "db_name" {
  description = "The name of the database"
  type        = string
  default     = "mydb"
}

variable "db_username" {
  description = "The username for the database"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "The password for the database"
  type        = string
  default     = "postgres"
  sensitive   = true
}
