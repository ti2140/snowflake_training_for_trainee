# ==========================================
# File Format定義
# ==========================================
resource "snowflake_file_format" "mail_jsonl_format" {
  database           = snowflake_database.training_db.name
  schema             = snowflake_schema.training_raw.name
  name               = "MAIL_JSONL_FORMAT"
  format_type        = "JSON"
  strip_outer_array  = false
  ignore_utf8_errors = true
  comment            = "File format for mail JSONL files."
}

# ==========================================
# External Stage定義
# ==========================================
resource "snowflake_stage" "st_s3_mail" {
  database            = snowflake_database.training_db.name
  schema              = snowflake_schema.training_raw.name
  name                = "ST_S3_MAIL"
  url                 = var.s3_bucket_url
  storage_integration = "S3_INT_TRAINING"
  file_format         = "FORMAT_NAME = ${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}.${snowflake_file_format.mail_jsonl_format.name}"
  comment             = "External stage for mail data from S3."
}

# ==========================================
# MAILS_RAWテーブル定義
# ==========================================
resource "snowflake_table" "mails_raw" {
  database = snowflake_database.training_db.name
  schema   = snowflake_schema.training_raw.name
  name     = "MAILS_RAW"
  comment  = "Raw mail data ingested from S3 via Snowpipe."

  column {
    name = "MESSAGE_ID"
    type = "VARCHAR"
  }
  column {
    name = "SUBJECT"
    type = "VARCHAR"
  }
  column {
    name = "FROM_EMAIL"
    type = "VARCHAR"
  }
  column {
    name = "RECEIVED_AT"
    type = "VARCHAR"
  }
  column {
    name = "BODY_TEXT"
    type = "VARCHAR"
  }
  column {
    name = "HAS_ATTACHMENTS"
    type = "BOOLEAN"
  }
  column {
    name = "ATTACHMENTS"
    type = "VARIANT"
  }
  column {
    name = "META"
    type = "VARIANT"
  }
  column {
    name = "AI_PROCESSED"
    type = "BOOLEAN"
  }
  column {
    name = "AI_RESULT"
    type = "VARIANT"
  }
  column {
    name = "CATEGORY"
    type = "VARCHAR"
  }
  column {
    name = "JOB_SCORE"
    type = "NUMBER"
  }
  column {
    name = "CANDIDATE_SCORE"
    type = "NUMBER"
  }
  column {
    name = "FOOTER_START_LINE"
    type = "NUMBER"
  }
  column {
    name = "MATCHED_JOB_KEYWORDS"
    type = "VARIANT"
  }
  column {
    name = "MATCHED_CANDIDATE_KEYWORDS"
    type = "VARIANT"
  }
  column {
    name = "ITEMS"
    type = "VARIANT"
  }
  column {
    name = "REASON"
    type = "VARCHAR"
  }
  column {
    name = "RECEIVER_COMPANY"
    type = "VARCHAR"
  }
  column {
    name = "REFERAL_COMPANY"
    type = "VARCHAR"
  }
}

# ==========================================
# Snowpipe定義
# ==========================================
resource "snowflake_pipe" "pipe_s3_to_mails_raw" {
  database    = snowflake_database.training_db.name
  schema      = snowflake_schema.training_raw.name
  name        = "PIPE_S3_TO_MAILS_RAW"
  auto_ingest = true
  comment     = "Snowpipe for auto-ingesting mail data from S3."
  # TODO：以下の???となっている箇所を補完し、最適なクエリを生成してください。
  copy_statement = "COPY INTO ${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}.${snowflake_table.mails_raw.name} FROM @${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}.${snowflake_pipe.pipe_s3_to_mails_raw.name} MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE"
}

# ==========================================
# 権限付与
# ==========================================
resource "snowflake_grant_privileges_to_account_role" "s3_int_usage" {
  account_role_name = var.snowflake_role_name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "INTEGRATION"
    object_name = "S3_INT_TRAINING"
  }
}

resource "snowflake_grant_privileges_to_account_role" "mails_raw_grants" {
  account_role_name = var.snowflake_role_name
  privileges        = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"]
  on_schema_object {
    object_type = "TABLE"
    object_name = "${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}.${snowflake_table.mails_raw.name}"
  }
}

resource "snowflake_grant_privileges_to_account_role" "future_table_grants" {
  account_role_name = var.snowflake_role_name
  privileges        = ["SELECT", "INSERT", "UPDATE", "DELETE"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "stage_usage" {
  account_role_name = var.snowflake_role_name
  privileges        = ["USAGE", "READ"]
  on_schema_object {
    object_type = "STAGE"
    object_name = "${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}.${snowflake_stage.st_s3_mail.name}"
  }
}

resource "snowflake_grant_privileges_to_account_role" "future_stage_usage" {
  account_role_name = var.snowflake_role_name
  privileges        = ["USAGE", "READ"]
  on_schema_object {
    future {
      object_type_plural = "STAGES"
      in_schema          = "${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "file_format_usage" {
  account_role_name = var.snowflake_role_name
  privileges        = ["USAGE"]
  on_schema_object {
    object_type = "FILE FORMAT"
    object_name = "${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}.${snowflake_file_format.mail_jsonl_format.name}"
  }
}

resource "snowflake_grant_privileges_to_account_role" "future_file_format_usage" {
  account_role_name = var.snowflake_role_name
  privileges        = ["USAGE"]
  on_schema_object {
    future {
      object_type_plural = "FILE FORMATS"
      in_schema          = "${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}"
    }
  }
}
