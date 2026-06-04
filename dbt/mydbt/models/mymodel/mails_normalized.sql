{{ config(
    materialized='table',
    schema='NORMALIZED'
) }}

WITH labels AS (
    SELECT ARRAY_AGG(LABEL) AS label_array
    FROM {{ this.database }}.NORMALIZED.CLASSIFY_TEXT_LABELS
),

trimmed AS (
    SELECT
        MESSAGE_ID,
        SUBJECT,
        FROM_EMAIL,
        RECEIVED_AT,
        REGEXP_REPLACE(BODY_TEXT, '<[^>]+>', '') AS body_stripped
    FROM {{ source('raw', 'MAILS_RAW') }}
),

processable AS (
    SELECT *
    FROM trimmed
    WHERE LEN(body_stripped) <= 3000
),

skipped AS (
    SELECT *
    FROM trimmed
    WHERE LEN(body_stripped) > 3000
),

ai_processed AS (
    SELECT
        p.MESSAGE_ID,
        p.SUBJECT,
        p.FROM_EMAIL,
        p.RECEIVED_AT,
        TRUE AS AI_PROCESSED,
        SNOWFLAKE.CORTEX.SUMMARIZE(p.body_stripped) AS AI_SUMMARY,
        -- FALSE AS AI_SUMMARY,
        SNOWFLAKE.CORTEX.CLASSIFY_TEXT(p.body_stripped, l.label_array):label::VARCHAR AS AI_CATEGORY,
        SNOWFLAKE.CORTEX.SENTIMENT(p.body_stripped) AS sentiment_score,
        SNOWFLAKE.CORTEX.COMPLETE(
            'mistral-large',
            CONCAT(
                'Extract 3-5 important keywords from the following email body. Return only a JSON array of strings. Body: ',
                p.body_stripped
            )
        ) AS AI_KEYWORDS,
        l.label_array
    FROM processable AS p
    CROSS JOIN labels AS l
)

SELECT
    MESSAGE_ID,
    SUBJECT,
    FROM_EMAIL,
    RECEIVED_AT,
    AI_PROCESSED,
    AI_SUMMARY,
    AI_CATEGORY,
    CASE
        WHEN sentiment_score > 0.3 THEN 'positive'
        WHEN sentiment_score < -0.3 THEN 'negative'
        ELSE 'neutral'
    END AS AI_SENTIMENT,
    AI_KEYWORDS,
    OBJECT_CONSTRUCT(
        'summary', AI_SUMMARY,
        'classify', AI_CATEGORY,
        'sentiment_score', sentiment_score,
        'keywords', AI_KEYWORDS
    ) AS AI_RAW_RESULT,
    CURRENT_TIMESTAMP() AS NORMALIZED_AT
FROM ai_processed

UNION ALL

SELECT
    MESSAGE_ID,
    SUBJECT,
    FROM_EMAIL,
    RECEIVED_AT,
    FALSE AS AI_PROCESSED,
    'メール本文が長すぎるためスキップしました' AS AI_SUMMARY,
    NULL AS AI_CATEGORY,
    NULL AS AI_SENTIMENT,
    NULL AS AI_KEYWORDS,
    NULL AS AI_RAW_RESULT,
    CURRENT_TIMESTAMP() AS NORMALIZED_AT
FROM skipped