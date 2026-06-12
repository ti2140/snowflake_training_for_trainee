variable "snowflake_organization_name" {
  type = string
}

variable "snowflake_account_name" {
  type = string
}

variable "snowflake_user" {
  type = string
}

variable "snowflake_role" {
  type = string
}

variable "snowflake_warehouse" {
  type = string
}

variable "snowflake_private_key" {
  type      = string
  sensitive = true
}

variable "trainee_name" {
  type = string
}

variable "s3_bucket_url" {
  type = string
}

variable "snowflake_aws_role_arn" {
  type = string
}

variable "snowflake_role_name" {
  type = string
}

variable "snowflake_storage_integration_name" {
  type    = string
  default = "S3_INT_TRAINIG"
}
