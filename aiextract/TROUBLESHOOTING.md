# Troubleshooting Guide - Invoice Processing Pipeline

## Quick Diagnostic Checklist

Run this query first to get an overview:

```sql
USE DATABASE invoice_processing_poc;
USE SCHEMA invoice_pipeline;

SELECT 
    'Files in Stage' as check_item,
    COUNT(*) as count
FROM DIRECTORY(@invoice_stage)
WHERE RELATIVE_PATH ILIKE '%.pdf'

UNION ALL

SELECT 
    'Extractions in raw_json',
    COUNT(*)
FROM raw_json

UNION ALL

SELECT 
    'Successful Extractions',
    COUNT(*)
FROM raw_json
WHERE processing_status = 'SUCCESS'

UNION ALL

SELECT 
    'Failed Extractions',
    COUNT(*)
FROM raw_json
WHERE processing_status = 'ERROR'

UNION ALL

SELECT 
    'Invoices Created',
    COUNT(*)
FROM invoice

UNION ALL

SELECT 
    'Line Items Created',
    COUNT(*)
FROM invoice_detail;
```

---

## Common Issues and Solutions

### 1. No Files Detected in Stage

**Symptoms:**
- `SELECT * FROM DIRECTORY(@invoice_stage);` returns empty
- Directory table has no records

**Solutions:**

```sql
-- Solution A: Refresh the stage
ALTER STAGE invoice_stage REFRESH;

-- Solution B: Verify files were uploaded
-- Check using Snowflake UI: Data → Stages → invoice_stage
-- Or upload files again:
-- PUT file:///path/to/file.pdf @invoice_stage AUTO_COMPRESS=FALSE;
```

**Prevention:**
- Always run `ALTER STAGE invoice_stage REFRESH;` after uploading files
- Ensure `AUTO_COMPRESS=FALSE` when uploading PDFs

---

### 2. Tasks Not Running

**Symptoms:**
- Data stays in streams but tasks don't execute
- Task history shows no recent runs

**Diagnosis:**

```sql
-- Check task state
SHOW TASKS IN SCHEMA invoice_pipeline;

-- Check if stream has data
SELECT SYSTEM$STREAM_HAS_DATA('invoice_stage_stream');
SELECT SYSTEM$STREAM_HAS_DATA('raw_json_stream');

-- Check task execution history
SELECT 
    name,
    state,
    scheduled_time,
    error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name IN ('TASK_EXTRACT_INVOICES', 'TASK_PARSE_JSON_TO_TABLES')
ORDER BY scheduled_time DESC
LIMIT 10;
```

**Solutions:**

```sql
-- Solution A: Resume tasks
ALTER TASK task_parse_json_to_tables RESUME;
ALTER TASK task_extract_invoices RESUME;

-- Solution B: Check warehouse is running
SHOW WAREHOUSES;

-- If warehouse doesn't exist, create it:
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH 
WITH WAREHOUSE_SIZE = 'XSMALL'
AUTO_SUSPEND = 60
AUTO_RESUME = TRUE;

-- Update tasks to use correct warehouse
ALTER TASK task_extract_invoices SET WAREHOUSE = COMPUTE_WH;
ALTER TASK task_parse_json_to_tables SET WAREHOUSE = COMPUTE_WH;

-- Solution C: Execute tasks manually for testing
EXECUTE TASK task_extract_invoices;
-- Wait 30 seconds...
EXECUTE TASK task_parse_json_to_tables;
```

---

### 3. AI Extraction Fails

**Symptoms:**
- Records in `raw_json` have `processing_status = 'ERROR'`
- Error messages about Cortex or model access

**Diagnosis:**

```sql
-- View extraction errors
SELECT 
    file_name,
    error_message,
    extraction_timestamp
FROM raw_json
WHERE processing_status = 'ERROR'
ORDER BY extraction_timestamp DESC;
```

**Common Error Messages:**

#### Error: "Cortex function not found" or "Invalid function"

```sql
-- Check if Cortex is enabled
-- Contact Snowflake support or your account admin
-- Verify account has access to Snowflake Cortex AI features
```

**Solution:** Enable Snowflake Cortex in your account (contact Snowflake support)

#### Error: "AI_EXTRACT function not available"

```sql
-- Verify AI_EXTRACT is available in your region
SELECT SNOWFLAKE.CORTEX.AI_EXTRACT(
    TO_FILE(@invoice_stage, 'test.pdf'),
    {'test_field': 'Test extraction'}
);
```

**Solution:** AI_EXTRACT may not be available in all regions yet. Contact Snowflake support to enable it, or check if your region supports this function.

#### Error: "Document processing timeout"

```sql
-- For very large documents, AI_EXTRACT may timeout
-- Solution: Split large documents or increase warehouse size
-- Consider preprocessing PDFs to reduce file size
```

**Solution:** Optimize document size or use larger warehouse for processing

#### Error: "PDF cannot be parsed"

**Causes:**
- Corrupted PDF file
- Password-protected PDF
- Scanned image without OCR
- Unsupported PDF version

**Solution:**
```bash
# Verify PDF is valid on your local machine
# Try re-uploading the file
# If scanned, OCR the document first
# Remove password protection
```

---

### 4. JSON Extraction Returns NULL or Invalid Data

**Symptoms:**
- `extracted_json` column contains NULL
- JSON doesn't match expected schema
- Missing fields in parsed data

**Diagnosis:**

```sql
-- View the extracted JSON
SELECT 
    extraction_id,
    file_name,
    TO_JSON(extracted_json) as json_data
FROM raw_json
WHERE processing_status = 'SUCCESS'
ORDER BY extraction_timestamp DESC
LIMIT 1;

-- Check specific fields
SELECT 
    extraction_id,
    extracted_json:invoice_number,
    extracted_json:vendor.name,
    extracted_json:line_items
FROM raw_json
WHERE processing_status = 'SUCCESS';
```

**Solutions:**

```sql
-- Solution A: Refine AI_EXTRACT schema descriptions
-- Modify the task to provide more explicit field descriptions
-- Make descriptions more specific to help AI understand what to extract
-- Example: Instead of "Invoice date", use "Invoice date in YYYY-MM-DD format found near invoice number"

-- Solution B: Test extraction manually
SELECT 
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        TO_FILE(@invoice_stage, 'MB66680464.pdf'),
        {
            'invoice_number': 'Invoice number',
            'total_amount': 'Total amount'
        }
    ) as test_extraction;

-- Then gradually add more fields to test

-- Solution C: Simplify extraction schema
-- Start with essential fields only
-- Add optional fields incrementally
-- Ensure PDFs have clear, readable text (not scanned images without OCR)
```

---

### 5. No Data in Invoice Tables

**Symptoms:**
- `raw_json` has data with SUCCESS status
- `invoice` and `invoice_detail` tables are empty
- Task 2 runs but produces no results

**Diagnosis:**

```sql
-- Check raw_json stream
SELECT * FROM raw_json_stream;

-- Check if task 2 has errors
SELECT 
    error_message,
    return_value
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name = 'TASK_PARSE_JSON_TO_TABLES'
  AND state = 'FAILED'
ORDER BY scheduled_time DESC;

-- Test JSON parsing manually
SELECT 
    extraction_id,
    extracted_json:invoice_number::VARCHAR as invoice_number,
    TRY_TO_DATE(extracted_json:invoice_date::VARCHAR) as invoice_date,
    extracted_json:vendor.name::VARCHAR as vendor_name
FROM raw_json
WHERE processing_status = 'SUCCESS'
LIMIT 1;
```

**Solutions:**

```sql
-- Solution A: Execute parsing task manually
EXECUTE TASK task_parse_json_to_tables;

-- Solution B: Check JSON structure matches expected schema
-- If structure is different, modify the INSERT queries in task_parse_json_to_tables

-- Solution C: Recreate raw_json stream
CREATE OR REPLACE STREAM raw_json_stream 
ON TABLE raw_json
APPEND_ONLY = TRUE;

-- Then re-execute task
EXECUTE TASK task_parse_json_to_tables;
```

---

### 6. Duplicate Invoices

**Symptoms:**
- Same invoice appears multiple times
- Line items are duplicated

**Diagnosis:**

```sql
-- Find duplicates
SELECT 
    invoice_number,
    COUNT(*) as count
FROM invoice
GROUP BY invoice_number
HAVING COUNT(*) > 1;

-- Check what's causing duplicates
SELECT 
    i.invoice_number,
    i.invoice_id,
    r.extraction_id,
    r.file_name,
    i.created_timestamp
FROM invoice i
JOIN raw_json r ON i.extraction_id = r.extraction_id
WHERE i.invoice_number IN (
    SELECT invoice_number 
    FROM invoice 
    GROUP BY invoice_number 
    HAVING COUNT(*) > 1
)
ORDER BY i.invoice_number, i.created_timestamp;
```

**Solutions:**

```sql
-- Solution A: Remove duplicates (keep latest)
-- Create backup first
CREATE TABLE invoice_backup AS SELECT * FROM invoice;
CREATE TABLE invoice_detail_backup AS SELECT * FROM invoice_detail;

-- Delete older duplicates
DELETE FROM invoice_detail
WHERE invoice_id IN (
    SELECT invoice_id FROM (
        SELECT 
            invoice_id,
            invoice_number,
            ROW_NUMBER() OVER (PARTITION BY invoice_number ORDER BY created_timestamp DESC) as rn
        FROM invoice
    ) WHERE rn > 1
);

DELETE FROM invoice
WHERE invoice_id IN (
    SELECT invoice_id FROM (
        SELECT 
            invoice_id,
            invoice_number,
            ROW_NUMBER() OVER (PARTITION BY invoice_number ORDER BY created_timestamp DESC) as rn
        FROM invoice
    ) WHERE rn > 1
);

-- Solution B: Prevent future duplicates
-- Add unique constraint
ALTER TABLE invoice ADD CONSTRAINT unique_invoice_number UNIQUE (invoice_number);

-- Or modify task to check for existing invoices before inserting
```

---

### 7. Line Item Totals Don't Match Invoice Total

**Symptoms:**
- Sum of line items ≠ invoice subtotal
- Financial data inconsistencies

**Diagnosis:**

```sql
-- Find mismatches
SELECT 
    i.invoice_id,
    i.invoice_number,
    i.subtotal as invoice_subtotal,
    SUM(d.line_amount) as line_items_total,
    ABS(i.subtotal - SUM(d.line_amount)) as variance
FROM invoice i
JOIN invoice_detail d ON i.invoice_id = d.invoice_id
GROUP BY i.invoice_id, i.invoice_number, i.subtotal
HAVING ABS(i.subtotal - SUM(d.line_amount)) > 0.01
ORDER BY variance DESC;
```

**Root Causes:**
1. AI extraction error (misread numbers)
2. Missing line items
3. Rounding differences
4. Invoice includes fees/discounts not in line items

**Solutions:**

```sql
-- Solution A: Manual correction
-- Review the original PDF and update incorrect data

-- Solution B: Add validation task
CREATE OR REPLACE TASK task_validate_totals
    WAREHOUSE = COMPUTE_WH
    AFTER task_parse_json_to_tables
AS
BEGIN
    -- Log validation issues
    CREATE TABLE IF NOT EXISTS validation_issues (
        issue_id NUMBER AUTOINCREMENT PRIMARY KEY,
        invoice_id NUMBER,
        issue_type VARCHAR(100),
        issue_details VARCHAR(5000),
        detected_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    );
    
    INSERT INTO validation_issues (invoice_id, issue_type, issue_details)
    SELECT 
        i.invoice_id,
        'TOTAL_MISMATCH',
        'Invoice subtotal: ' || i.subtotal || 
        ', Line items total: ' || SUM(d.line_amount) ||
        ', Variance: ' || ABS(i.subtotal - SUM(d.line_amount))
    FROM invoice i
    JOIN invoice_detail d ON i.invoice_id = d.invoice_id
    WHERE i.created_timestamp > DATEADD(HOUR, -1, CURRENT_TIMESTAMP())
    GROUP BY i.invoice_id, i.invoice_number, i.subtotal
    HAVING ABS(i.subtotal - SUM(d.line_amount)) > 0.01;
END;

-- Solution C: Refine AI_EXTRACT schema
-- Improve field descriptions for better accuracy
-- Add validation logic in parsing task to flag discrepancies
```

---

### 8. Performance Issues

**Symptoms:**
- Tasks take too long to execute
- Warehouse runs out of memory
- Timeouts occur

**Diagnosis:**

```sql
-- Check execution times
SELECT 
    name,
    scheduled_time,
    TIMESTAMPDIFF(SECOND, query_start_time, completed_time) as execution_seconds,
    state
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name IN ('TASK_EXTRACT_INVOICES', 'TASK_PARSE_JSON_TO_TABLES')
ORDER BY scheduled_time DESC
LIMIT 20;

-- Check warehouse usage
SELECT 
    warehouse_name,
    avg_running,
    avg_queued_load
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_LOAD_HISTORY
WHERE warehouse_name = 'COMPUTE_WH'
  AND start_time > DATEADD(HOUR, -24, CURRENT_TIMESTAMP())
ORDER BY start_time DESC;
```

**Solutions:**

```sql
-- Solution A: Increase warehouse size
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'SMALL';
-- Or MEDIUM, LARGE as needed

-- Solution B: Process files in smaller batches
-- Modify task to use LIMIT
CREATE OR REPLACE TASK task_extract_invoices
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('invoice_stage_stream')
AS
INSERT INTO raw_json (...)
SELECT ...
FROM invoice_stage_stream s
WHERE s.RELATIVE_PATH ILIKE '%.pdf'
LIMIT 10;  -- Process max 10 files per run

-- Solution C: Increase task execution timeout
ALTER TASK task_extract_invoices SET USER_TASK_TIMEOUT_MS = 3600000; -- 1 hour

-- Solution D: Use separate warehouses for each task
CREATE WAREHOUSE EXTRACTION_WH WITH WAREHOUSE_SIZE = 'MEDIUM';
CREATE WAREHOUSE PARSING_WH WITH WAREHOUSE_SIZE = 'SMALL';

ALTER TASK task_extract_invoices SET WAREHOUSE = EXTRACTION_WH;
ALTER TASK task_parse_json_to_tables SET WAREHOUSE = PARSING_WH;
```

---

### 9. Stream Not Capturing Changes

**Symptoms:**
- New data added but stream appears empty
- `SYSTEM$STREAM_HAS_DATA()` returns FALSE

**Diagnosis:**

```sql
-- Check stream metadata
SHOW STREAMS IN SCHEMA invoice_pipeline;

-- Check if stream is stale
SELECT 
    SYSTEM$STREAM_HAS_DATA('invoice_stage_stream') as has_data,
    (SELECT COUNT(*) FROM invoice_stage_stream) as record_count;

-- Check files in stage directory
SELECT COUNT(*) FROM DIRECTORY(@invoice_stage);
```

**Solutions:**

```sql
-- Solution A: Recreate the stream
-- Note: Directory streams cannot use APPEND_ONLY = TRUE
CREATE OR REPLACE STREAM invoice_stage_stream 
ON STAGE invoice_stage;

-- Solution B: Check if stream was consumed
-- Streams are consumed after task reads from them
-- This is normal behavior - new changes will appear in stream

-- Solution C: For testing, query the stream before task consumes it
SELECT * FROM invoice_stage_stream;

-- Solution D: Use stream with AT before consuming
SELECT * FROM invoice_stage_stream AT(OFFSET => -1);
```

---

## Getting Additional Help

### Enable Detailed Logging

```sql
-- Add logging table
CREATE TABLE IF NOT EXISTS pipeline_log (
    log_id NUMBER AUTOINCREMENT PRIMARY KEY,
    log_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    task_name VARCHAR(100),
    log_level VARCHAR(20),
    message VARCHAR(5000)
);

-- Modify tasks to log progress
-- (Add logging statements in task procedures)
```

### Collect Diagnostic Information

Run this query and share results with support:

```sql
-- Comprehensive diagnostic report
SELECT 'SYSTEM INFO' as section, CURRENT_ACCOUNT() as account, CURRENT_REGION() as region
UNION ALL
SELECT 'DATABASE', CURRENT_DATABASE(), CURRENT_SCHEMA()
UNION ALL
SELECT 'WAREHOUSE', CURRENT_WAREHOUSE(), NULL;

-- Object counts
SELECT 'FILES IN STAGE', COUNT(*), NULL FROM DIRECTORY(@invoice_stage);
SELECT 'RAW JSON RECORDS', COUNT(*), NULL FROM raw_json;
SELECT 'INVOICES', COUNT(*), NULL FROM invoice;
SELECT 'LINE ITEMS', COUNT(*), NULL FROM invoice_detail;

-- Recent task runs
SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE scheduled_time > DATEADD(HOUR, -24, CURRENT_TIMESTAMP())
ORDER BY scheduled_time DESC;

-- Recent errors
SELECT * FROM raw_json WHERE processing_status = 'ERROR';
```

### Contact Points

1. **Snowflake Documentation**: https://docs.snowflake.com/
2. **Snowflake Support**: https://support.snowflake.com/
3. **Community Forums**: https://community.snowflake.com/

---

## Prevention Best Practices

1. **Always test manually first** before enabling automated tasks
2. **Monitor task execution** regularly using `TASK_HISTORY()`
3. **Set up alerts** for task failures
4. **Validate data quality** after each major change
5. **Keep backups** before making structural changes
6. **Document customizations** to the standard pipeline
7. **Test with sample data** before processing production files
8. **Review AI extraction results** periodically to ensure accuracy
9. **Monitor costs** - AI functions and warehouse usage
10. **Keep tasks suspended** when not actively processing

---

## Quick Reset (Nuclear Option)

If all else fails and you want to start fresh:

```sql
-- ⚠️ WARNING: This deletes all data ⚠️

-- Suspend tasks
ALTER TASK task_extract_invoices SUSPEND;
ALTER TASK task_parse_json_to_tables SUSPEND;

-- Clear all data
TRUNCATE TABLE invoice_detail;
TRUNCATE TABLE invoice;
TRUNCATE TABLE raw_json;

-- Recreate streams
-- Note: Directory streams cannot use APPEND_ONLY = TRUE
CREATE OR REPLACE STREAM invoice_stage_stream ON STAGE invoice_stage;
CREATE OR REPLACE STREAM raw_json_stream ON TABLE raw_json APPEND_ONLY = TRUE;

-- Refresh stage
ALTER STAGE invoice_stage REFRESH;

-- Start fresh
CALL refresh_and_process();
```

