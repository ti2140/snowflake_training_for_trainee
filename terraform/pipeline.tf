# ==========================================
# Storage Integration定義
# ==========================================
resource "snowflake_storage_integration" "s3_int" {
  name                      = "S3_INT"
  type                      = "EXTERNAL_STAGE"
  enabled                   = true
  storage_provider          = "S3"
  storage_aws_role_arn      = "arn:aws:iam::160621358952:role/snowflake_demo_role"
  storage_allowed_locations = ["s3://anchor-demo-mybucket/messages/"]
  comment                   = "Storage integration for S3 mail data."
}

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

  depends_on = [snowflake_schema.training_raw]
}

# ==========================================
# External Stage定義
# ==========================================
resource "snowflake_stage" "st_s3_mail" {
  database            = snowflake_database.training_db.name
  schema              = snowflake_schema.training_raw.name
  name                = "ST_S3_MAIL"
  url                 = "s3://anchor-demo-mybucket/messages/"
  storage_integration = snowflake_storage_integration.s3_int.name
  file_format         = "FORMAT_NAME = ${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}.MAIL_JSONL_FORMAT"
  comment             = "External stage for mail data from S3."

  depends_on = [
    snowflake_schema.training_raw,
    snowflake_file_format.mail_jsonl_format,
    snowflake_storage_integration.s3_int
  ]
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

  depends_on = [snowflake_schema.training_raw]
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

  copy_statement = "COPY INTO ${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}.MAILS_RAW FROM @${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}.ST_S3_MAIL MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE"

  depends_on = [
    snowflake_table.mails_raw,
    snowflake_stage.st_s3_mail
  ]
}

# ==========================================
# MAILS_RAWテーブル権限付与
# ==========================================
resource "snowflake_grant_privileges_to_account_role" "mails_raw_select" {
  account_role_name = "FR_ANCHOR_DEMO_ROLE"
  privileges        = ["SELECT"]
  on_schema_object {
    object_type = "TABLE"
    object_name = "${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}.MAILS_RAW"
  }
  depends_on = [snowflake_table.mails_raw]
}

resource "snowflake_grant_privileges_to_account_role" "future_table_select" {
  account_role_name = "FR_ANCHOR_DEMO_ROLE"
  privileges        = ["SELECT", "INSERT", "UPDATE", "DELETE"]
  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}"
    }
  }
}

# ST_S3_MAILステージへのUSAGE権限
resource "snowflake_grant_privileges_to_account_role" "stage_usage" {
  account_role_name = "FR_ANCHOR_DEMO_ROLE"
  privileges        = ["USAGE", "READ"]
  on_schema_object {
    object_type = "STAGE"
    object_name = "${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}.ST_S3_MAIL"
  }
  depends_on = [snowflake_stage.st_s3_mail]
}

# 将来作成されるステージへも自動付与
resource "snowflake_grant_privileges_to_account_role" "future_stage_usage" {
  account_role_name = "FR_ANCHOR_DEMO_ROLE"
  privileges        = ["USAGE", "READ"]
  on_schema_object {
    future {
      object_type_plural = "STAGES"
      in_schema          = "${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}"
    }
  }
}