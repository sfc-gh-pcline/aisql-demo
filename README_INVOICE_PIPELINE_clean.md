# Snowflake AI Invoice Processing Pipeline POC

## Overview

This proof-of-concept demonstrates an automated invoice processing pipeline using Snowflake's AI capabilities. The pipeline extracts structured data from PDF invoices using Snowflake Cortex AI functions and processes them through a series of automated tasks and streams.

## Architecture

```
┌─────────────────┐
│   PDF Files     │
│  (Stage)        │
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│  Stage Directory Table  │
│  + Stream               │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  Task 1:                │
│  AI_EXTRACT             │
│  (Parse PDF → JSON)     │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  raw_json Table         │
│  + Stream               │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  Task 2:                │
│  Parse JSON to Tables   │
└────────┬────────────────┘
         │
         ├────────────────┐
         ▼                ▼
┌──────────────┐  ┌──────────────────┐
│  invoice     │  │  invoice_detail  │
│  (Header)    │  │  (Line Items)    │
└──────────────┘  └──────────────────┘
```

## Components

### 1. **Stage and Monitoring**
- `invoice_stage`: Internal stage for PDF storage (with implicit directory table enabled)
- `invoice_stage_stream`: Stream on stage to detect new files

### 2. **Extraction Layer**
- `raw_json`: Stores AI-extracted JSON data
- `raw_json_stream`: Stream to detect new extractions
- `task_extract_invoices`: Task that uses Snowflake Cortex AI to extract invoice data

### 3. **Structured Data Layer**
- `invoice`: Invoice header information (vendor, customer, totals)
- `invoice_detail`: Invoice line items
- `task_parse_json_to_tables`: Task that parses JSON into structured tables

### 4. **Monitoring**
- `pipeline_monitoring`: View showing end-to-end pipeline status
- `invoice_summary`: Aggregated invoice information
- `invoice_detail_view`: Denormalized view of invoices and line items

## JSON Schema

The AI extraction produces JSON with this structure:

```json
{
  "invoice_number": "INV-12345",
  "invoice_date": "2024-01-15",
  "due_date": "2024-02-15",
  "vendor": {
    "name": "Acme Corp",
    "address": "123 Main St",
    "city": "Springfield",
    "state": "IL",
    "zip": "62701",
    "country": "USA",
    "phone": "(555) 123-4567",
    "email": "billing@acme.com",
    "tax_id": "12-3456789"
  },
  "customer": {
    "name": "Customer Company",
    "address": "456 Oak Ave",
    "city": "Chicago",
    "state": "IL",
    "zip": "60601",
    "country": "USA",
    "phone": "(555) 987-6543",
    "email": "ap@customer.com"
  },
  "financial": {
    "subtotal": 1000.00,
    "tax_amount": 80.00,
    "tax_rate": 8.00,
    "shipping_amount": 25.00,
    "discount_amount": 0.00,
    "total_amount": 1105.00,
    "currency": "USD"
  },
  "payment_terms": "Net 30",
  "po_number": "PO-98765",
  "notes": "Thank you for your business",
  "line_items": [
    {
      "line_number": 1,
      "description": "Product A - Widget",
      "item_code": "PROD-A-001",
      "quantity": 10,
      "unit_of_measure": "EA",
      "unit_price": 50.00,
      "line_amount": 500.00,
      "discount_percent": 0,
      "discount_amount": 0,
      "tax_amount": 40.00,
      "category": "Hardware",
      "notes": ""
    },
    {
      "line_number": 2,
      "description": "Service - Installation",
      "item_code": "SVC-INST-001",
      "quantity": 5,
      "unit_of_measure": "HR",
      "unit_price": 100.00,
      "line_amount": 500.00,
      "discount_percent": 0,
      "discount_amount": 0,
      "tax_amount": 40.00,
      "category": "Services",
      "notes": "On-site installation"
    }
  ]
}
```

## Prerequisites

1. **Snowflake Account** with:
   - Snowflake Cortex AI features enabled
   - Warehouse (e.g., `COMPUTE_WH`) with appropriate size
   - Proper privileges to create databases, schemas, tables, stages, streams, and tasks

2. **Required Permissions**:
   - `CREATE DATABASE`
   - `CREATE SCHEMA`
   - `CREATE TABLE`
   - `CREATE STAGE`
   - `CREATE STREAM`
   - `CREATE TASK`
   - `CREATE VIEW`
   - `CREATE PROCEDURE`
   - `EXECUTE TASK`
   - Usage on Snowflake Cortex AI functions

3. **Cost Considerations**:
   - Cortex AI functions incur compute costs
   - Tasks require warehouse compute
   - Consider starting with smaller warehouse and adjusting based on volume

## Installation

### Step 1: Execute the SQL Script

```sql
-- Run the complete pipeline setup
-- Use snowflake_invoice_pipeline_v2.sql (recommended)
```

Connect to your Snowflake account and execute `snowflake_invoice_pipeline_v2.sql`. This will create:
- Database: `invoice_processing_poc`
- Schema: `invoice_pipeline`
- All tables, streams, tasks, views, and procedures

### Step 2: Upload Invoice Files

Upload your PDF invoice files to the stage:

```sql
-- From SnowSQL or Snowflake UI
PUT file:///Users/pcline/My\ Drive/Accounts/Grayson/Inspire/Document\ Parsing/docs/MB66680464.pdf 
    @invoice_processing_poc.invoice_pipeline.invoice_stage 
    AUTO_COMPRESS=FALSE;
```

Or use the Snowflake UI:
1. Navigate to Databases → `invoice_processing_poc` → `invoice_pipeline` → Stages
2. Select `invoice_stage`
3. Click "Upload Files"
4. Select your PDF files

### Step 3: Refresh Directory Table

```sql
USE DATABASE invoice_processing_poc;
USE SCHEMA invoice_pipeline;

-- Refresh the stage to detect new files
ALTER STAGE invoice_stage REFRESH;

-- Verify files are detected using the implicit directory table
SELECT * FROM DIRECTORY(@invoice_stage);
```

### Step 4: Resume Tasks

Tasks are created in SUSPENDED state. Resume them to start automatic processing:

```sql
-- Resume in reverse dependency order
ALTER TASK task_parse_json_to_tables RESUME;
ALTER TASK task_extract_invoices RESUME;

-- Verify task state
SHOW TASKS;
```

## Usage

### Manual Processing (Testing)

For testing without waiting for scheduled execution:

```sql
-- Option 1: Use the helper procedure
CALL refresh_and_process();

-- Option 2: Execute tasks manually
EXECUTE TASK task_extract_invoices;
EXECUTE TASK task_parse_json_to_tables;
```

### Monitoring

```sql
-- View overall pipeline status
SELECT * FROM pipeline_monitoring;

-- View invoice summaries
SELECT * FROM invoice_summary;

-- View invoice details with line items
SELECT * FROM invoice_detail_view;

-- Get statistics
CALL get_pipeline_stats();

-- Check task execution history
SELECT 
    name,
    state,
    scheduled_time,
    completed_time,
    return_value,
    error_code,
    error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name IN ('TASK_EXTRACT_INVOICES', 'TASK_PARSE_JSON_TO_TABLES')
ORDER BY scheduled_time DESC
LIMIT 20;

-- Check stream status
SELECT SYSTEM$STREAM_HAS_DATA('invoice_stage_stream') as has_new_files;
SELECT SYSTEM$STREAM_HAS_DATA('raw_json_stream') as has_new_extractions;
```

### Querying Results

```sql
-- Get all invoices from a specific vendor
SELECT * FROM invoice_summary
WHERE vendor_name LIKE '%Acme%';

-- Get invoices over a certain amount
SELECT * FROM invoice_summary
WHERE total_amount > 1000.00
ORDER BY total_amount DESC;

-- Get all line items for a specific invoice
SELECT * FROM invoice_detail_view
WHERE invoice_number = 'INV-12345';

-- Find invoices with specific products
SELECT DISTINCT 
    invoice_number,
    vendor_name,
    invoice_total
FROM invoice_detail_view
WHERE item_description LIKE '%Widget%';

-- Analyze line item quantities and totals
SELECT 
    item_description,
    COUNT(*) as times_ordered,
    SUM(quantity) as total_quantity,
    AVG(unit_price) as avg_unit_price,
    SUM(line_amount) as total_revenue
FROM invoice_detail d
GROUP BY item_description
ORDER BY total_revenue DESC;

-- Monthly invoice summary
SELECT 
    DATE_TRUNC('MONTH', invoice_date) as month,
    COUNT(*) as invoice_count,
    SUM(total_amount) as total_amount,
    AVG(total_amount) as avg_invoice_amount
FROM invoice
GROUP BY month
ORDER BY month DESC;
```

## Troubleshooting

### Task Errors

```sql
-- Check for task errors
SELECT *
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name = 'TASK_EXTRACT_INVOICES'
  AND state = 'FAILED'
ORDER BY scheduled_time DESC;
```

### Extraction Errors

```sql
-- Check for extraction errors
SELECT 
    file_name,
    error_message,
    extraction_timestamp
FROM raw_json
WHERE processing_status = 'ERROR';
```

### Stream Issues

```sql
-- Reset stream if needed
CREATE OR REPLACE STREAM invoice_stage_stream 
ON STAGE invoice_stage
APPEND_ONLY = TRUE;
```

### Common Issues

1. **No files detected**: Ensure `ALTER STAGE invoice_stage REFRESH` is executed after uploading files

2. **Tasks not running**: 
   - Verify tasks are RESUMED: `SHOW TASKS;`
   - Check warehouse is running: `SHOW WAREHOUSES;`
   - Verify stream has data: `SELECT SYSTEM$STREAM_HAS_DATA('invoice_stage_stream');`

3. **AI extraction errors**:
   - Verify Cortex AI is enabled for your account
   - Check if PDF is readable
   - Ensure AI_EXTRACT function is available in your region

4. **JSON parsing errors**:
   - Check if extracted JSON matches expected schema
   - Review `extracted_json` column in `raw_json` table
   - Validate JSON structure: `SELECT TO_JSON(extracted_json) FROM raw_json;`

## Performance Optimization

### For High Volume

```sql
-- Increase warehouse size
ALTER TASK task_extract_invoices SET WAREHOUSE = LARGE_WH;
ALTER TASK task_parse_json_to_tables SET WAREHOUSE = LARGE_WH;

-- Adjust schedule for more frequent processing
ALTER TASK task_extract_invoices SET SCHEDULE = '30 SECONDS';

-- Enable multi-threading for large batches
-- Consider splitting into multiple parallel tasks
```

### Cost Optimization

```sql
-- Use smaller warehouse for light processing
ALTER TASK task_extract_invoices SET WAREHOUSE = XSMALL_WH;

-- Reduce frequency
ALTER TASK task_extract_invoices SET SCHEDULE = '5 MINUTE';

-- Suspend tasks when not needed
ALTER TASK task_extract_invoices SUSPEND;
ALTER TASK task_parse_json_to_tables SUSPEND;
```

## Cleanup

To remove the entire pipeline:

```sql
-- Suspend tasks first
ALTER TASK task_extract_invoices SUSPEND;
ALTER TASK task_parse_json_to_tables SUSPEND;

-- Drop all objects
DROP TASK IF EXISTS task_parse_json_to_tables;
DROP TASK IF EXISTS task_extract_invoices;
DROP PROCEDURE IF EXISTS refresh_and_process();
DROP PROCEDURE IF EXISTS get_pipeline_stats();
DROP STREAM IF EXISTS raw_json_stream;
DROP STREAM IF EXISTS invoice_stage_stream;
DROP VIEW IF EXISTS invoice_detail_view;
DROP VIEW IF EXISTS invoice_summary;
DROP VIEW IF EXISTS pipeline_monitoring;
DROP TABLE IF EXISTS invoice_detail;
DROP TABLE IF EXISTS invoice;
DROP TABLE IF EXISTS raw_json;
DROP STAGE IF EXISTS invoice_stage;
DROP SCHEMA IF EXISTS invoice_pipeline;
DROP DATABASE IF EXISTS invoice_processing_poc;
```

## Extensions and Enhancements

### 1. Add Data Quality Checks

```sql
CREATE OR REPLACE VIEW data_quality_issues AS
SELECT 
    invoice_id,
    invoice_number,
    CASE 
        WHEN invoice_number IS NULL THEN 'Missing invoice number'
        WHEN invoice_date IS NULL THEN 'Missing invoice date'
        WHEN vendor_name IS NULL THEN 'Missing vendor'
        WHEN total_amount IS NULL THEN 'Missing total'
        WHEN total_amount <= 0 THEN 'Invalid total amount'
        ELSE 'Unknown issue'
    END as issue
FROM invoice
WHERE invoice_number IS NULL 
   OR invoice_date IS NULL
   OR vendor_name IS NULL
   OR total_amount IS NULL
   OR total_amount <= 0;
```

### 2. Add Duplicate Detection

```sql
CREATE OR REPLACE VIEW potential_duplicates AS
SELECT 
    i1.invoice_id as invoice_id_1,
    i2.invoice_id as invoice_id_2,
    i1.invoice_number,
    i1.vendor_name,
    i1.total_amount,
    i1.invoice_date
FROM invoice i1
JOIN invoice i2 
    ON i1.invoice_number = i2.invoice_number
    AND i1.vendor_name = i2.vendor_name
    AND i1.invoice_id < i2.invoice_id;
```

### 3. Add Email Notifications

```sql
-- Create notification task for errors
CREATE OR REPLACE TASK task_notify_errors
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '1 HOUR'
AS
BEGIN
    -- Check for recent errors
    LET error_count NUMBER := (
        SELECT COUNT(*) 
        FROM raw_json 
        WHERE processing_status = 'ERROR' 
        AND extraction_timestamp > DATEADD(HOUR, -1, CURRENT_TIMESTAMP())
    );
    
    -- Send notification if errors found
    IF (error_count > 0) THEN
        CALL SYSTEM$SEND_EMAIL(
            'error_notification_integration',
            'admin@company.com',
            'Invoice Processing Errors',
            'There are ' || error_count || ' invoice processing errors in the last hour.'
        );
    END IF;
END;
```

### 4. Archive Old Records

```sql
CREATE OR REPLACE TASK task_archive_old_records
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 0 2 * * SUN America/New_York'  -- Weekly on Sunday at 2 AM
AS
BEGIN
    -- Archive raw_json older than 90 days
    CREATE TABLE IF NOT EXISTS raw_json_archive LIKE raw_json;
    
    INSERT INTO raw_json_archive
    SELECT * FROM raw_json
    WHERE extraction_timestamp < DATEADD(DAY, -90, CURRENT_TIMESTAMP());
    
    DELETE FROM raw_json
    WHERE extraction_timestamp < DATEADD(DAY, -90, CURRENT_TIMESTAMP());
END;
```

## Additional Resources

- [Snowflake Cortex Documentation](https://docs.snowflake.com/en/user-guide/snowflake-cortex)
- [Snowflake Streams Documentation](https://docs.snowflake.com/en/user-guide/streams)
- [Snowflake Tasks Documentation](https://docs.snowflake.com/en/user-guide/tasks-intro)
- [Snowflake Stages Documentation](https://docs.snowflake.com/en/user-guide/data-load-internal-tutorial-stage-data-files)

## License

This is a proof-of-concept for demonstration purposes.

## Support

For questions or issues, contact your Snowflake account team or consult Snowflake documentation.

