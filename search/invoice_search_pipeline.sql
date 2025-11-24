-- ============================================================================
-- Snowflake Invoice Search Pipeline using AI_PARSE_DOCUMENT and Cortex Search
-- ============================================================================
-- This pipeline creates a searchable invoice repository using:
-- - AI_PARSE_DOCUMENT for layout-aware extraction
-- - Cortex Search Service for semantic search on parsed invoice content
-- ============================================================================

-- ============================================================================
-- STEP 1: SETUP DATABASE AND SCHEMA
-- ============================================================================

CREATE DATABASE IF NOT EXISTS invoice_processing_poc;
USE DATABASE invoice_processing_poc;

-- Use the same schema as aiextract project
CREATE SCHEMA IF NOT EXISTS invoice_processing_poc.invoice_pipeline;
USE SCHEMA invoice_processing_poc.invoice_pipeline;

-- ============================================================================
-- STEP 2: CREATE STAGE FOR INVOICES (SHARED WITH AIEXTRACT)
-- ============================================================================

-- Use the same stage as aiextract project
CREATE STAGE IF NOT EXISTS invoice_stage
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for storing invoice files';

-- ============================================================================
-- STEP 3: CREATE STREAM ON STAGE DIRECTORY
-- ============================================================================

-- Stream to capture new files added to the stage for parsing
-- Note: Directory streams cannot be APPEND_ONLY since they track both additions and deletions
CREATE OR REPLACE STREAM invoice_parse_stream 
ON STAGE invoice_stage
COMMENT = 'Stream to track new invoice files for document parsing';

-- ============================================================================
-- STEP 4: CREATE TABLE FOR PARSED INVOICE DATA
-- ============================================================================

CREATE OR REPLACE TABLE parsed_invoices (
    parsed_id NUMBER AUTOINCREMENT PRIMARY KEY,
    file_name VARCHAR(500) NOT NULL,
    file_url VARCHAR(1000) NOT NULL,
    file_size NUMBER,
    last_modified TIMESTAMP_NTZ,
    parsed_content VARIANT NOT NULL,
    extracted_text VARCHAR,
    parse_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    processing_status VARCHAR(50) DEFAULT 'SUCCESS',
    error_message VARCHAR(5000)
);

-- ============================================================================
-- STEP 5: CREATE TASK TO PARSE DOCUMENTS USING AI_PARSE_DOCUMENT
-- ============================================================================

CREATE OR REPLACE TASK task_parse_invoices
    WAREHOUSE = SNOWFLAKE_INTELLIGENCE_WH
    SCHEDULE = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('invoice_parse_stream')
AS
INSERT INTO parsed_invoices (
    file_name,
    file_url,
    file_size,
    last_modified,
    parsed_content,
    processing_status
)
SELECT 
    s.RELATIVE_PATH as file_name,
    BUILD_SCOPED_FILE_URL(@invoice_stage, s.RELATIVE_PATH) as file_url,
    s.SIZE as file_size,
    s.LAST_MODIFIED::TIMESTAMP_NTZ as last_modified,
    AI_PARSE_DOCUMENT(
        TO_FILE('@invoice_stage', s.RELATIVE_PATH),
        {'mode': 'LAYOUT'}
    ) as parsed_content,
    'SUCCESS' as processing_status
FROM invoice_parse_stream s
WHERE s.metadata$action = 'INSERT';

-- ============================================================================
-- STEP 6: CREATE CORTEX SEARCH SERVICE
-- ============================================================================

-- Create search service on parsed invoice data
CREATE OR REPLACE CORTEX SEARCH SERVICE invoice_search_service
ON parsed_content
ATTRIBUTES file_name, file_url, file_size, last_modified, parse_timestamp
WAREHOUSE = SNOWFLAKE_INTELLIGENCE_WH
TARGET_LAG = '1 minute'
EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
AS (
    SELECT 
        parsed_id,
        file_name,
        file_url,
        file_size,
        last_modified,
        parse_timestamp,
        TO_JSON(parsed_content) as parsed_content
    FROM parsed_invoices
    WHERE processing_status = 'SUCCESS'
);

-- ============================================================================
-- STEP 7: HELPER PROCEDURES AND VIEWS
-- ============================================================================

-- Procedure to manually refresh directory and process files
CREATE OR REPLACE PROCEDURE refresh_and_parse()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    -- Refresh the stage directory (updates the implicit directory table)
    ALTER STAGE invoice_stage REFRESH;
    
    -- Execute task manually (for testing)
    EXECUTE TASK task_parse_invoices;
    
    RETURN 'Processing initiated successfully';
END;
$$;

-- View to monitor pipeline status
CREATE OR REPLACE VIEW search_pipeline_monitoring AS
SELECT 
    parsed_id,
    file_name,
    file_size,
    parse_timestamp,
    processing_status,
    error_message,
    CASE 
        WHEN processing_status = 'SUCCESS' THEN '✓'
        ELSE '✗'
    END as status_icon
FROM parsed_invoices
ORDER BY parse_timestamp DESC;

-- View to get search service statistics
CREATE OR REPLACE VIEW search_service_stats AS
SELECT 
    COUNT(*) as total_documents_indexed,
    COUNT(DISTINCT file_name) as unique_files,
    MIN(parse_timestamp) as first_indexed,
    MAX(parse_timestamp) as last_indexed,
    AVG(file_size) as avg_file_size,
    SUM(file_size) as total_size_bytes
FROM parsed_invoices
WHERE processing_status = 'SUCCESS';

-- ============================================================================
-- STEP 8: RESUME TASKS (Execute after setup complete)
-- ============================================================================

-- Uncomment to start the pipeline:
-- ALTER TASK task_parse_invoices RESUME;

-- ============================================================================
-- TESTING QUERIES
-- ============================================================================

-- 1. Upload a file to the stage
-- PUT file:///path/to/docs/MB66680464.pdf @invoice_stage AUTO_COMPRESS=FALSE;

-- 2. Refresh directory and check
-- ALTER STAGE invoice_stage REFRESH;
-- SELECT * FROM DIRECTORY(@invoice_stage);

-- 3. Check stream for new files
-- SELECT * FROM invoice_parse_stream;

-- 4. Manually execute parsing task
-- CALL refresh_and_parse();

-- 5. Check parsed results
-- SELECT * FROM parsed_invoices ORDER BY parse_timestamp DESC;

-- 6. View extracted text
-- SELECT file_name, extracted_text FROM parsed_invoices LIMIT 1;

-- 7. Test search service
-- SELECT * FROM TABLE(
--     invoice_search_service.SEARCH(
--         'invoice',
--         10
--     )
-- );

-- 8. Monitor pipeline
-- SELECT * FROM search_pipeline_monitoring;

-- 9. View search service stats
-- SELECT * FROM search_service_stats;

-- ============================================================================
-- CLEANUP
-- ============================================================================

/*
-- To suspend task:
ALTER TASK task_parse_invoices SUSPEND;

-- To drop search-specific objects:
DROP CORTEX SEARCH SERVICE IF EXISTS invoice_search_service;
DROP VIEW IF EXISTS search_pipeline_monitoring;
DROP VIEW IF EXISTS search_service_stats;
DROP PROCEDURE IF EXISTS refresh_and_parse();
DROP STREAM IF EXISTS invoice_parse_stream;
DROP TABLE IF EXISTS parsed_invoices;
-- Note: invoice_stage is shared with aiextract project - don't drop unless cleaning up everything
*/

