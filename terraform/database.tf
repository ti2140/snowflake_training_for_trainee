# ==========================================
# DB定義
# ==========================================
resource "snowflake_database" "training_db" {
  name    = "${upper(var.trainee_name)}_TRAINING_DB"
  comment = "Training DB for ${var.trainee_name}. Created by Terraform."
}

# ==========================================
# DBへの権限付与
# ==========================================
resource "snowflake_grant_privileges_to_account_role" "training_db_usage" {
  account_role_name = "FR_ANCHOR_DEMO_ROLE"
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.training_db.name
  }
}