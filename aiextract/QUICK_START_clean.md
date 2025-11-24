# Quick Start Guide - Snowflake Invoice Processing Pipeline

## 5-Minute Setup

### Step 1: Deploy the Pipeline (2 minutes)

1. Open Snowflake Web UI or SnowSQL
2. Copy and paste the entire contents of `snowflake_invoice_pipeline_v2.sql`
3. Execute the script
4. Wait for all objects to be created

**Expected Output:**
- Database: `invoice_processing_poc`
- Schema: `invoice_pipeline`  
- 6 tables, 2 streams, 2 tasks, 3 views, 2 procedures

### Step 2: Upload Test Invoice (1 minute)

**Option A: Using SnowSQL Command Line**
```bash
snowsql -a <your_account> -u <your_user>

# Upload file
PUT file:///Users/pcline/My\ Drive/Accounts/Grayson/Inspire/Document\ Parsing/docs/MB66680464.pdf 
    @invoice_processing_poc.invoice_pipeline.invoice_stage 
    AUTO_COMPRESS=FALSE;
```

**Option B: Using Snowflake Web UI**
1. Navigate to: Data → Databases → `invoice_processing_poc` → `invoice_pipeline` → Stages
2. Click on `invoice_stage`
3. Click "+ Files" button
4. Upload `docs/MB66680464.pdf`

### Step 3: Process the Invoice (2 minutes)

```sql
USE DATABASE invoice_processing_poc;
USE SCHEMA invoice_pipeline;

-- Refresh stage and process
CALL refresh_and_process();

-- Wait 30-60 seconds for processing...

-- Check results
SELECT * FROM pipeline_monitoring;
SELECT * FROM invoice_summary;
SELECT * FROM invoice_detail_view;
```

### Step 4: Enable Automatic Processing (Optional)

```sql
-- Resume tasks for automatic processing
ALTER TASK task_parse_json_to_tables RESUME;
ALTER TASK task_extract_invoices RESUME;

-- Verify tasks are running
SHOW TASKS;
```

## Validation Checklist

After setup, verify everything works:

- [ ] Stage contains files: `SELECT * FROM DIRECTORY(@invoice_stage);`
- [ ] Raw JSON extracted: `SELECT COUNT(*) FROM raw_json;`
- [ ] Invoices created: `SELECT COUNT(*) FROM invoice;`
- [ ] Line items created: `SELECT COUNT(*) FROM invoice_detail;`
- [ ] Monitoring view works: `SELECT * FROM pipeline_monitoring;`
- [ ] Tasks are resumed: `SHOW TASKS;` (state = 'started')

## Sample Queries to Try

### View Your First Invoice
```sql
-- See the invoice header
SELECT 
    invoice_number,
    invoice_date,
    vendor_name,
    customer_name,
    total_amount,
    currency
FROM invoice_summary
LIMIT 1;
```

### View Invoice Line Items
```sql
-- See all line items
SELECT 
    invoice_number,
    line_number,
    item_description,
    quantity,
    unit_price,
    line_amount
FROM invoice_detail_view
ORDER BY invoice_number, line_number;
```

### View Extracted JSON
```sql
-- See the raw AI extraction
SELECT 
    file_name,
    TO_JSON(extracted_json) as json_output
FROM raw_json
LIMIT 1;
```

### Get Pipeline Statistics
```sql
-- Run the stats procedure
CALL get_pipeline_stats();
```

## What Happens When You Upload New Files?

Once tasks are resumed:

1. **Every minute** → Task checks for new files in stage
2. **If new files found** → AI extraction starts automatically
3. **JSON saved to raw_json** → Second task triggers
4. **JSON parsed** → Data inserted into invoice and invoice_detail tables
5. **Complete** → View results in monitoring views

## Adding More Invoices

### Batch Upload
```bash
# Upload multiple files at once
PUT file:///path/to/invoices/*.pdf @invoice_stage AUTO_COMPRESS=FALSE;
```

### Trigger Processing
```sql
-- Option 1: Automatic (if tasks are resumed)
-- Wait up to 1 minute for next task run

-- Option 2: Manual (immediate)
CALL refresh_and_process();
```

## Stopping the Pipeline

```sql
-- Suspend automatic processing
ALTER TASK task_extract_invoices SUSPEND;
ALTER TASK task_parse_json_to_tables SUSPEND;

-- You can still process manually with:
-- CALL refresh_and_process();
```

## Common Issues

###  "No data found in pipeline_monitoring"

**Solution:**
```sql
-- 1. Verify file upload
SELECT * FROM DIRECTORY(@invoice_stage);

-- 2. Manually refresh and process
ALTER STAGE invoice_stage REFRESH;
CALL refresh_and_process();

-- 3. Wait 30 seconds, then check again
SELECT * FROM pipeline_monitoring;
```

###  "Task execution failed"

**Solution:**
```sql
-- Check task history for errors
SELECT 
    name,
    error_code,
    error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE state = 'FAILED'
ORDER BY scheduled_time DESC
LIMIT 5;
```

###  "AI extraction returned null"

**Solution:**
- Ensure Snowflake Cortex AI is enabled in your account
- Verify your account has access to 'mistral-large2' model
- Check PDF file is valid and readable

###  "Warehouse not found: COMPUTE_WH"

**Solution:**
```sql
-- Create warehouse if it doesn't exist
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH 
WITH WAREHOUSE_SIZE = 'XSMALL'
AUTO_SUSPEND = 60
AUTO_RESUME = TRUE;

-- OR update tasks to use your existing warehouse
ALTER TASK task_extract_invoices SET WAREHOUSE = YOUR_WAREHOUSE_NAME;
ALTER TASK task_parse_json_to_tables SET WAREHOUSE = YOUR_WAREHOUSE_NAME;
```

## Next Steps

1. **Upload more invoices** to test at scale
2. **Customize JSON schema** for your specific invoice format
3. **Add data quality checks** using the extensions in README
4. **Set up monitoring dashboards** in your BI tool
5. **Integrate with downstream systems** (ERP, accounting software)

## Need Help?

1. Check the detailed `README_INVOICE_PIPELINE.md`
2. Review Snowflake Cortex documentation
3. Contact your Snowflake account team

---

**Congratulations!**  You now have an AI-powered invoice processing pipeline running in Snowflake.

