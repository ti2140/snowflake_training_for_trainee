{{ config(
    materialized='table',
    schema='NORMALIZED'
) }}

WITH labels AS (
    SELECT ARRAY_AGG(
        LABEL || ': ' || COALESCE(DESCRIPTION, LABEL)
    ) AS label_array
    FROM {{ this.database }}.NORMALIZED.CLASSIFY_TEXT_LABELS
),

trimmed AS (
    SELECT
        MESSAGE_ID,
        SUBJECT,
        FROM_EMAIL,
        RECEIVED_AT,
        LEFT(
            REGEXP_REPLACE(BODY_TEXT, '<[^>]+>', ''),
            4000
        ) AS body_trimmed
    FROM {{ source('raw', 'MAILS_RAW') }}
),

ai_processed AS (
    SELECT
        t.MESSAGE_ID,
        t.SUBJECT,
        t.FROM_EMAIL,
        t.RECEIVED_AT,
        SNOWFLAKE.CORTEX.SUMMARIZE(t.body_trimmed) AS summary,
        SPLIT_PART(
            SNOWFLAKE.CORTEX.CLASSIFY_TEXT(t.body_trimmed, l.label_array):label::VARCHAR,
            ':',
            1
        ) AS AI_CATEGORY,
        SNOWFLAKE.CORTEX.SENTIMENT(t.body_trimmed) AS sentiment_score,
        SNOWFLAKE.CORTEX.COMPLETE(
            'mistral-large',
            CONCAT(
                'Extract 3-5 important keywords from the following email. ',
                'Return ONLY a JSON array of strings with no explanation, no preamble, no markdown. ',
                'Example output: ["keyword1", "keyword2", "keyword3"]\n',
                'Email: ',
                t.body_trimmed
            )
        ) AS keywords
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
    AI_CATEGORY,
    CASE
        WHEN sentiment_score > 0.3 THEN 'positive'
        WHEN sentiment_score < -0.3 THEN 'negative'
        ELSE 'neutral'
    END AS AI_SENTIMENT,
    keywords AS AI_KEYWORDS,
    OBJECT_CONSTRUCT(
        'summary', summary,
        'category', AI_CATEGORY,
        'sentiment_score', sentiment_score,
        'keywords', keywords
    ) AS AI_RAW_RESULT,
    CURRENT_TIMESTAMP() AS NORMALIZED_AT
FROM ai_processed