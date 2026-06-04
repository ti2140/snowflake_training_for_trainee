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
        REGEXP_REPLACE(BODY_TEXT, '<[^>]+>', '') AS body_stripped,
        LEN(REGEXP_REPLACE(BODY_TEXT, '<[^>]+>', '')) AS stripped_length
    FROM {{ source('raw', 'MAILS_RAW') }}
),

ai_processed AS (
    SELECT
        t.MESSAGE_ID,
        t.SUBJECT,
        t.FROM_EMAIL,
        t.RECEIVED_AT,
        CASE
            WHEN t.stripped_length <= 3000
            THEN SNOWFLAKE.CORTEX.SUMMARIZE(t.body_stripped)
            ELSE '本文が長すぎるため要約をスキップしました'
        END AS summary,
        CASE
            WHEN t.stripped_length <= 3000
            THEN SNOWFLAKE.CORTEX.CLASSIFY_TEXT(t.body_stripped, l.label_array)
            ELSE NULL
        END AS classify_result,
        CASE
            WHEN t.stripped_length <= 3000
            THEN SNOWFLAKE.CORTEX.SENTIMENT(t.body_stripped)
            ELSE NULL
        END AS sentiment_score,
        CASE
            WHEN t.stripped_length <= 3000
            THEN SNOWFLAKE.CORTEX.COMPLETE(
                'mistral-large',
                CONCAT(
                    'Extract 3-5 important keywords from the following email body. Return only a JSON array of strings. Body: ',
                    t.body_stripped
                )
            )
            ELSE NULL
        END AS keywords
    FROM trimmed AS t
    CROSS JOIN labels AS l
)

SELECT
    MESSAGE_ID,
    SUBJECT,
    FROM_EMAIL,
    RECEIVED_AT,
    TRUE AS AI_PROCESSED,
    summary AS AI_SUMMARY,
    classify_result:label::VARCHAR AS AI_CATEGORY,
    CASE
        WHEN sentiment_score > 0.3 THEN 'positive'
        WHEN sentiment_score < -0.3 THEN 'negative'
        ELSE 'neutral'
    END AS AI_SENTIMENT,
    keywords AS AI_KEYWORDS,
    OBJECT_CONSTRUCT(
        'summary', summary,
        'classify', classify_result,
        'sentiment_score', sentiment_score,
        'keywords', keywords
    ) AS AI_RAW_RESULT,
    CURRENT_TIMESTAMP() AS NORMALIZED_AT
FROM ai_processed