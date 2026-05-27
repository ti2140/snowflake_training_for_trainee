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
      source  = "snowflakedb/snowflake"
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
# 3. DB定義（SYSADMINで実行）
# ==========================================
resource "snowflake_database" "training_db" {
  name    = "${upper(var.trainee_name)}_TRAINING_DB"
  comment = "Training DB for ${var.trainee_name}. Created by Terraform."
}

# ==========================================
# 4. DBT用ロールへの権限付与
# ==========================================

# DBへのUSAGE権限
resource "snowflake_grant_privileges_to_account_role" "training_db_usage" {
  account_role_name = "FR_ANCHOR_DEMO_ROLE"
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.training_db.name
  }
}

