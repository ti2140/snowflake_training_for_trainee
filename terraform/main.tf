# ==========================================
# 1. プラグイン（Provider）の設定
# ==========================================
terraform {
  cloud {
    organization = "snowflake-training"
    workspaces {
      name = "snowflake-workspace"
    }
  }

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake" # ← ここも変更
      version = ">= 1.0.0"
    }
  }
}

# ==========================================
# 2. Snowflakeへの接続設定
# ==========================================
provider "snowflake" {
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_user
  role              = var.snowflake_role
  warehouse         = var.snowflake_warehouse
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = var.snowflake_private_key
}

# ==========================================
# 3. 作成するリソース（データベース）の定義
# ==========================================
resource "snowflake_database" "tf_test_db" {
  name    = "TF_TEST_DB" # データベース名
  comment = "Test DB created by Terraform"
}