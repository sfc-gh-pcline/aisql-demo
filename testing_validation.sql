-- ============================================================================
-- Invoice Processing Pipeline - Testing & Validation Script
-- ============================================================================
-- This script provides comprehensive testing scenarios and validation queries
-- for the Snowflake AI Invoice Processing Pipeline
-- ============================================================================

USE DATABASE invoice_processing_poc;
USE SCHEMA invoice_pipeline;

-- ============================================================================
-- SECTION 1: PRE-DEPLOYMENT VALIDATION
-- ============================================================================

-- Verify all required objects exist
SELECT 'Checking Database Objects...' as status;

-- Check Tables
SELECT 'Tables' as object_type, COUNT(*) as count 
FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_SCHEMA = 'INVOICE_PIPELINE'
  AND TABLE_TYPE = 'BASE TABLE';
-- Expected: 4 tables (invoice_stage_directory, raw_json, invoice, invoice_detail)

-- Check Views
SELECT 'Views' as object_type, COUNT(*) as count 
FROM INFORMATION_SCHEMA.VIEWS 
WHERE TABLE_SCHEMA = 'INVOICE_PIPELINE';
-- Expected: 3 views

-- Check Streams
SELECT 'Streams' as object_type, COUNT(*) as count 
FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_SCHEMA = 'INVOICE_PIPELINE'
  AND TABLE_TYPE = 'STREAM';
-- Expected: 2 streams

-- Check Tasks
SHOW TASKS IN SCHEMA invoice_pipeline;
-- Expected: 2 tasks (task_extract_invoices, task_parse_json_to_tables)

-- Check Procedures
SHOW PROCEDURES IN SCHEMA invoice_pipeline;
-- Expected: 2 procedures

-- Check Stage
SHOW STAGES IN SCHEMA invoice_pipeline;
-- Expected: 1 stage (invoice_stage)

-- ============================================================================
-- SECTION 2: STAGE AND FILE UPLOAD TESTING
-- ============================================================================

SELECT '=== STAGE TESTING ===' as test_section;

-- Test 1: Verify stage exists and directory is enabled
DESC STAGE invoice_stage;

-- Test 2: Check current files in stage
SELECT 
    'Files in Stage' as test_name,
    COUNT(*) as file_count
FROM DIRECTORY(@invoice_stage);

-- Test 3: View detailed file information
SELECT 
    RELATIVE_PATH as filename,
    SIZE as file_size_bytes,
    ROUND(SIZE / 1024, 2) as file_size_kb,
    LAST_MODIFIED,
    FILE_URL
FROM DIRECTORY(@invoice_stage)
ORDER BY LAST_MODIFIED DESC;

-- Test 4: Check for PDF files specifically
SELECT 
    'PDF Files' as test_name,
    COUNT(*) as count
FROM DIRECTORY(@invoice_stage)
WHERE RELATIVE_PATH ILIKE '%.pdf';

-- Test 5: Verify stage stream has data
SELECT 
    'Stream Has New Files' as test_name,
    SYSTEM$STREAM_HAS_DATA('invoice_stage_stream') as has_data;

-- Test 6: View stream contents
SELECT * FROM invoice_stage_stream LIMIT 10;

-- ============================================================================
-- SECTION 3: AI EXTRACTION TESTING
-- ============================================================================

SELECT '=== AI EXTRACTION TESTING ===' as test_section;

-- Test 7: Manual extraction test (single file)
-- This tests the AI_EXTRACT function without running the full task
SELECT 
    'AI Extraction Test' as test_name,
    RELATIVE_PATH as file_name,
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        BUILD_SCOPED_FILE_URL(@invoice_stage, RELATIVE_PATH),
        {
            'invoice_number': 'Invoice number',
            'invoice_date': 'Invoice date',
            'vendor': {'name': 'Vendor name'},
            'customer': {'name': 'Customer name'},
            'financial': {'total_amount': 'Total amount'},
            'line_items': [
                {
                    'description': 'Item description',
                    'quantity': 'Quantity',
                    'unit_price': 'Unit price',
                    'line_amount': 'Line total'
                }
            ]
        }
    ) as extracted_sample
FROM DIRECTORY(@invoice_stage)
WHERE RELATIVE_PATH ILIKE '%.pdf'
LIMIT 1;

-- Test 8: Execute extraction task manually
EXECUTE TASK task_extract_invoices;

-- Wait 10-15 seconds, then check results

-- Test 9: Verify raw_json table has data
SELECT 
    'Raw JSON Records' as test_name,
    COUNT(*) as count,
    SUM(CASE WHEN processing_status = 'SUCCESS' THEN 1 ELSE 0 END) as success_count,
    SUM(CASE WHEN processing_status = 'ERROR' THEN 1 ELSE 0 END) as error_count
FROM raw_json;

-- Test 10: View extraction details
SELECT 
    extraction_id,
    file_name,
    file_size,
    processing_status,
    extraction_timestamp,
    error_message
FROM raw_json
ORDER BY extraction_timestamp DESC;

-- Test 11: View extracted JSON (pretty formatted)
SELECT 
    extraction_id,
    file_name,
    TO_JSON(extracted_json) as json_output
FROM raw_json
WHERE processing_status = 'SUCCESS'
ORDER BY extraction_timestamp DESC
LIMIT 1;

-- Test 12: Validate JSON structure
SELECT 
    extraction_id,
    file_name,
    extracted_json:invoice_number::VARCHAR as invoice_number,
    extracted_json:invoice_date::VARCHAR as invoice_date,
    extracted_json:vendor.name::VARCHAR as vendor_name,
    extracted_json:customer.name::VARCHAR as customer_name,
    extracted_json:financial.total_amount::NUMBER as total_amount,
    ARRAY_SIZE(extracted_json:line_items) as line_item_count
FROM raw_json
WHERE processing_status = 'SUCCESS'
ORDER BY extraction_timestamp DESC;

-- Test 13: Check raw_json stream
SELECT 
    'Raw JSON Stream Has Data' as test_name,
    SYSTEM$STREAM_HAS_DATA('raw_json_stream') as has_data;

SELECT * FROM raw_json_stream LIMIT 10;

-- ============================================================================
-- SECTION 4: JSON PARSING TESTING
-- ============================================================================

SELECT '=== JSON PARSING TESTING ===' as test_section;

-- Test 14: Execute parsing task manually
EXECUTE TASK task_parse_json_to_tables;

-- Wait 5-10 seconds, then check results

-- Test 15: Verify invoice table has data
SELECT 
    'Invoice Records' as test_name,
    COUNT(*) as count
FROM invoice;

-- Test 16: Verify invoice_detail table has data
SELECT 
    'Invoice Detail Records' as test_name,
    COUNT(*) as count
FROM invoice_detail;

-- Test 17: View invoice records
SELECT 
    invoice_id,
    extraction_id,
    invoice_number,
    invoice_date,
    vendor_name,
    customer_name,
    subtotal,
    tax_amount,
    total_amount,
    currency,
    created_timestamp
FROM invoice
ORDER BY created_timestamp DESC;

-- Test 18: View invoice detail records
SELECT 
    invoice_detail_id,
    invoice_id,
    line_number,
    item_description,
    quantity,
    unit_price,
    line_amount
FROM invoice_detail
ORDER BY invoice_id, line_number;

-- Test 19: Validate foreign key relationships
SELECT 
    'Invoice to Detail Relationship' as test_name,
    i.invoice_id,
    i.invoice_number,
    COUNT(d.invoice_detail_id) as line_item_count
FROM invoice i
LEFT JOIN invoice_detail d ON i.invoice_id = d.invoice_id
GROUP BY i.invoice_id, i.invoice_number;

-- Test 20: Validate extraction_id relationship
SELECT 
    'Raw JSON to Invoice Relationship' as test_name,
    r.extraction_id,
    r.file_name,
    i.invoice_id,
    i.invoice_number
FROM raw_json r
LEFT JOIN invoice i ON r.extraction_id = i.extraction_id
WHERE r.processing_status = 'SUCCESS';

-- ============================================================================
-- SECTION 5: MONITORING VIEWS TESTING
-- ============================================================================

SELECT '=== MONITORING VIEWS TESTING ===' as test_section;

-- Test 21: Pipeline monitoring view
SELECT * FROM pipeline_monitoring;

-- Test 22: Invoice summary view
SELECT * FROM invoice_summary;

-- Test 23: Invoice detail view
SELECT * FROM invoice_detail_view;

-- ============================================================================
-- SECTION 6: DATA QUALITY VALIDATION
-- ============================================================================

SELECT '=== DATA QUALITY VALIDATION ===' as test_section;

-- Test 24: Check for missing required fields
SELECT 
    'Invoices with Missing Data' as test_name,
    invoice_id,
    invoice_number,
    CASE 
        WHEN invoice_number IS NULL THEN 'Missing invoice_number'
        WHEN invoice_date IS NULL THEN 'Missing invoice_date'
        WHEN vendor_name IS NULL THEN 'Missing vendor_name'
        WHEN total_amount IS NULL THEN 'Missing total_amount'
        ELSE 'OK'
    END as data_issue
FROM invoice
WHERE invoice_number IS NULL 
   OR invoice_date IS NULL
   OR vendor_name IS NULL
   OR total_amount IS NULL;

-- Test 25: Validate numeric fields
SELECT 
    'Invalid Numeric Values' as test_name,
    invoice_id,
    invoice_number,
    total_amount,
    subtotal,
    tax_amount
FROM invoice
WHERE total_amount <= 0
   OR subtotal < 0
   OR tax_amount < 0;

-- Test 26: Validate date fields
SELECT 
    'Invalid Dates' as test_name,
    invoice_id,
    invoice_number,
    invoice_date,
    due_date
FROM invoice
WHERE invoice_date > CURRENT_DATE()
   OR (due_date IS NOT NULL AND due_date < invoice_date);

-- Test 27: Check for orphaned detail records
SELECT 
    'Orphaned Detail Records' as test_name,
    COUNT(*) as count
FROM invoice_detail d
LEFT JOIN invoice i ON d.invoice_id = i.invoice_id
WHERE i.invoice_id IS NULL;

-- Test 28: Validate line item totals match invoice totals
SELECT 
    'Line Item Total Validation' as test_name,
    i.invoice_id,
    i.invoice_number,
    i.subtotal as invoice_subtotal,
    SUM(d.line_amount) as detail_total,
    ABS(i.subtotal - SUM(d.line_amount)) as variance
FROM invoice i
JOIN invoice_detail d ON i.invoice_id = d.invoice_id
GROUP BY i.invoice_id, i.invoice_number, i.subtotal
HAVING ABS(i.subtotal - SUM(d.line_amount)) > 0.01;

-- ============================================================================
-- SECTION 7: TASK EXECUTION TESTING
-- ============================================================================

SELECT '=== TASK EXECUTION TESTING ===' as test_section;

-- Test 29: View task execution history
SELECT 
    name,
    state,
    scheduled_time,
    query_start_time,
    completed_time,
    TIMESTAMPDIFF(SECOND, query_start_time, completed_time) as execution_seconds,
    return_value,
    error_code,
    error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name IN ('TASK_EXTRACT_INVOICES', 'TASK_PARSE_JSON_TO_TABLES')
  AND scheduled_time > DATEADD(HOUR, -24, CURRENT_TIMESTAMP())
ORDER BY scheduled_time DESC
LIMIT 20;

-- Test 30: Check task success rate
SELECT 
    name,
    COUNT(*) as total_runs,
    SUM(CASE WHEN state = 'SUCCEEDED' THEN 1 ELSE 0 END) as successful_runs,
    SUM(CASE WHEN state = 'FAILED' THEN 1 ELSE 0 END) as failed_runs,
    ROUND(SUM(CASE WHEN state = 'SUCCEEDED' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) as success_rate_pct
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name IN ('TASK_EXTRACT_INVOICES', 'TASK_PARSE_JSON_TO_TABLES')
  AND scheduled_time > DATEADD(DAY, -7, CURRENT_TIMESTAMP())
GROUP BY name;

-- Test 31: Check task state
SHOW TASKS IN SCHEMA invoice_pipeline;

-- Test 32: Validate task dependencies
SELECT 
    name,
    predecessors,
    state,
    schedule
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name IN ('TASK_EXTRACT_INVOICES', 'TASK_PARSE_JSON_TO_TABLES')
GROUP BY name, predecessors, state, schedule;

-- ============================================================================
-- SECTION 8: PERFORMANCE TESTING
-- ============================================================================

SELECT '=== PERFORMANCE TESTING ===' as test_section;

-- Test 33: Average processing time per invoice
SELECT 
    'Average Extraction Time' as metric,
    AVG(TIMESTAMPDIFF(SECOND, query_start_time, completed_time)) as avg_seconds
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name = 'TASK_EXTRACT_INVOICES'
  AND state = 'SUCCEEDED'
  AND scheduled_time > DATEADD(DAY, -7, CURRENT_TIMESTAMP());

SELECT 
    'Average Parsing Time' as metric,
    AVG(TIMESTAMPDIFF(SECOND, query_start_time, completed_time)) as avg_seconds
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name = 'TASK_PARSE_JSON_TO_TABLES'
  AND state = 'SUCCEEDED'
  AND scheduled_time > DATEADD(DAY, -7, CURRENT_TIMESTAMP());

-- Test 34: Processing throughput
SELECT 
    'Processing Throughput' as metric,
    DATE_TRUNC('HOUR', extraction_timestamp) as hour,
    COUNT(*) as invoices_processed
FROM raw_json
GROUP BY hour
ORDER BY hour DESC;

-- Test 35: File size vs processing time correlation
SELECT 
    r.file_name,
    r.file_size,
    ROUND(r.file_size / 1024, 2) as size_kb,
    t.execution_seconds,
    CASE 
        WHEN r.file_size < 100000 THEN 'Small (<100KB)'
        WHEN r.file_size < 500000 THEN 'Medium (100-500KB)'
        ELSE 'Large (>500KB)'
    END as size_category
FROM raw_json r
JOIN (
    SELECT 
        scheduled_time,
        TIMESTAMPDIFF(SECOND, query_start_time, completed_time) as execution_seconds
    FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
    WHERE name = 'TASK_EXTRACT_INVOICES' AND state = 'SUCCEEDED'
) t ON DATE_TRUNC('MINUTE', r.extraction_timestamp) = DATE_TRUNC('MINUTE', t.scheduled_time)
ORDER BY r.extraction_timestamp DESC;

-- ============================================================================
-- SECTION 9: END-TO-END VALIDATION
-- ============================================================================

SELECT '=== END-TO-END VALIDATION ===' as test_section;

-- Test 36: Complete pipeline trace for each file
SELECT 
    'Pipeline Trace' as test_name,
    sd.RELATIVE_PATH as original_file,
    r.extraction_id,
    r.file_name,
    r.extraction_timestamp,
    r.processing_status,
    i.invoice_id,
    i.invoice_number,
    COUNT(d.invoice_detail_id) as line_items
FROM invoice_stage_directory sd
LEFT JOIN raw_json r ON sd.RELATIVE_PATH = r.file_name
LEFT JOIN invoice i ON r.extraction_id = i.extraction_id
LEFT JOIN invoice_detail d ON i.invoice_id = d.invoice_id
WHERE sd.RELATIVE_PATH ILIKE '%.pdf'
GROUP BY 
    sd.RELATIVE_PATH,
    r.extraction_id,
    r.file_name,
    r.extraction_timestamp,
    r.processing_status,
    i.invoice_id,
    i.invoice_number
ORDER BY r.extraction_timestamp DESC;

-- Test 37: Verify data completeness
SELECT 
    'Data Completeness Check' as test_name,
    (SELECT COUNT(*) FROM DIRECTORY(@invoice_stage) WHERE RELATIVE_PATH ILIKE '%.pdf') as files_in_stage,
    (SELECT COUNT(*) FROM raw_json) as extractions,
    (SELECT COUNT(*) FROM invoice) as invoices,
    (SELECT COUNT(*) FROM invoice_detail) as line_items,
    CASE 
        WHEN (SELECT COUNT(*) FROM DIRECTORY(@invoice_stage) WHERE RELATIVE_PATH ILIKE '%.pdf') = 
             (SELECT COUNT(*) FROM raw_json WHERE processing_status = 'SUCCESS') 
        THEN '✓ All files extracted'
        ELSE '✗ Some files not extracted'
    END as extraction_status,
    CASE 
        WHEN (SELECT COUNT(*) FROM raw_json WHERE processing_status = 'SUCCESS') = 
             (SELECT COUNT(*) FROM invoice) 
        THEN '✓ All extractions parsed'
        ELSE '✗ Some extractions not parsed'
    END as parsing_status;

-- ============================================================================
-- SECTION 10: HELPER PROCEDURES TESTING
-- ============================================================================

SELECT '=== HELPER PROCEDURES TESTING ===' as test_section;

-- Test 38: Get pipeline statistics
CALL get_pipeline_stats();

-- Test 39: Test refresh_and_process procedure
-- CALL refresh_and_process();
-- (Commented out to prevent accidental execution)

-- ============================================================================
-- SECTION 11: STRESS TESTING (Optional)
-- ============================================================================

SELECT '=== STRESS TESTING ===' as test_section;

-- Test 40: Simulate processing multiple files
-- This query shows what would happen with batch processing
SELECT 
    'Batch Processing Simulation' as test_name,
    COUNT(*) as total_files,
    SUM(SIZE) as total_size_bytes,
    ROUND(SUM(SIZE) / 1024 / 1024, 2) as total_size_mb,
    ROUND(AVG(SIZE) / 1024, 2) as avg_file_size_kb
FROM DIRECTORY(@invoice_stage)
WHERE RELATIVE_PATH ILIKE '%.pdf';

-- ============================================================================
-- SECTION 12: ERROR SCENARIO TESTING
-- ============================================================================

SELECT '=== ERROR SCENARIO TESTING ===' as test_section;

-- Test 41: Check for extraction errors
SELECT 
    'Extraction Errors' as test_name,
    extraction_id,
    file_name,
    error_message,
    extraction_timestamp
FROM raw_json
WHERE processing_status = 'ERROR'
ORDER BY extraction_timestamp DESC;

-- Test 42: Check for parsing issues
SELECT 
    'JSON Parsing Issues' as test_name,
    extraction_id,
    file_name,
    CASE 
        WHEN extracted_json:invoice_number IS NULL THEN 'Missing invoice_number'
        WHEN extracted_json:line_items IS NULL THEN 'Missing line_items'
        WHEN ARRAY_SIZE(extracted_json:line_items) = 0 THEN 'Empty line_items'
        ELSE 'Other issue'
    END as issue_type
FROM raw_json
WHERE processing_status = 'SUCCESS'
  AND (
    extracted_json:invoice_number IS NULL OR
    extracted_json:line_items IS NULL OR
    ARRAY_SIZE(extracted_json:line_items) = 0
  );

-- ============================================================================
-- SECTION 13: CLEANUP AND RESET (Use with caution)
-- ============================================================================

SELECT '=== CLEANUP COMMANDS ===' as test_section;
SELECT '-- Uncomment these commands to reset the pipeline' as warning;

/*
-- Reset all data (keeps structure)
TRUNCATE TABLE invoice_detail;
TRUNCATE TABLE invoice;
TRUNCATE TABLE raw_json;
TRUNCATE TABLE invoice_stage_directory;

-- Recreate streams
CREATE OR REPLACE STREAM invoice_stage_stream 
ON TABLE invoice_stage_directory
APPEND_ONLY = TRUE;

CREATE OR REPLACE STREAM raw_json_stream 
ON TABLE raw_json
APPEND_ONLY = TRUE;

-- Clear stage files (use with extreme caution!)
-- REMOVE @invoice_stage;
*/

-- ============================================================================
-- SECTION 14: FINAL VALIDATION SUMMARY
-- ============================================================================

SELECT '=== FINAL VALIDATION SUMMARY ===' as test_section;

-- Generate comprehensive validation report
SELECT 
    'Pipeline Health Check' as report_name,
    CURRENT_TIMESTAMP() as report_time,
    (SELECT COUNT(*) FROM invoice_stage_directory WHERE RELATIVE_PATH ILIKE '%.pdf') as total_files,
    (SELECT COUNT(*) FROM raw_json) as total_extractions,
    (SELECT COUNT(*) FROM raw_json WHERE processing_status = 'SUCCESS') as successful_extractions,
    (SELECT COUNT(*) FROM raw_json WHERE processing_status = 'ERROR') as failed_extractions,
    (SELECT COUNT(*) FROM invoice) as total_invoices,
    (SELECT COUNT(*) FROM invoice_detail) as total_line_items,
    (SELECT ROUND(AVG(total_amount), 2) FROM invoice) as avg_invoice_amount,
    (SELECT SUM(total_amount) FROM invoice) as total_invoice_value,
    CASE 
        WHEN (SELECT COUNT(*) FROM raw_json WHERE processing_status = 'ERROR') = 0 
        THEN '✓ HEALTHY' 
        ELSE '⚠ NEEDS ATTENTION' 
    END as pipeline_status;

-- ============================================================================
-- TEST EXECUTION COMPLETE
-- ============================================================================

SELECT '=== TESTING COMPLETE ===' as status;
SELECT 'Review results above to validate pipeline functionality' as next_steps;

