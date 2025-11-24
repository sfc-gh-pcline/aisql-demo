# Quick Start Guide - Invoice Search Pipeline

Get up and running with the Invoice Search Pipeline in minutes.

> **📁 File Upload Note:** When using the `PUT` command, replace `/path/to/your/` with your actual file path. On Windows, use forward slashes (e.g., `file://C:/Users/YourName/Documents/invoice.pdf`). On Mac/Linux, use the full path (e.g., `file:///Users/yourname/Documents/invoice.pdf`).

## Prerequisites

- Snowflake account with Cortex AI features enabled
- Warehouse: `SNOWFLAKE_INTELLIGENCE_WH`
- Sample invoice files (PDF, DOCX, or other supported formats)
- **Note:** This project uses the same schema and stage as the aiextract project

## 5-Minute Setup

### 1. Create the Pipeline

```sql
-- Run the complete setup
@search/invoice_search_pipeline.sql
```

This single script creates everything you need:
- ✓ Database and schema (if not exists)
- ✓ Stage (shared with aiextract)
- ✓ Table for parsed content
- ✓ Stream for monitoring new files
- ✓ Parsing task
- ✓ Search service

**Time: ~2 minutes**

### 2. Upload Sample Invoices

```sql
USE DATABASE invoice_processing_poc;
USE SCHEMA invoice_pipeline;

-- Upload invoice files from your local system
-- Replace the path with your actual file location
PUT file:///path/to/your/invoice1.pdf 
    @invoice_stage 
    AUTO_COMPRESS=FALSE;

PUT file:///path/to/your/invoice2.pdf 
    @invoice_stage 
    AUTO_COMPRESS=FALSE;

-- Refresh the stage to update the directory table
ALTER STAGE invoice_stage REFRESH;

-- Verify upload
SELECT * FROM DIRECTORY(@invoice_stage);
```

**Time: ~1 minute**

> **Note:** Replace `/path/to/your/` with the actual path to your invoice files. On Windows, use forward slashes: `file://C:/Users/YourName/Documents/invoice.pdf`

### 3. Process the Invoices

```sql
-- Option A: Start automatic processing
ALTER TASK task_parse_invoices RESUME;
-- Wait ~1 minute for next scheduled run

-- Option B: Process immediately (recommended for testing)
CALL refresh_and_parse();
```

**Time: ~1 minute**

### 4. Verify Everything Works

```sql
-- Check parsed invoices
SELECT 
    file_name,
    processing_status,
    parse_timestamp
FROM parsed_invoices;

-- View some extracted text
SELECT 
    file_name,
    SUBSTRING(extracted_text, 1, 200) as text_preview
FROM parsed_invoices
LIMIT 1;
```

**Time: ~30 seconds**

---

## Your First Queries

### 🔍 Full-Text Search

Search for specific content in invoices:

```sql
-- Find invoices mentioning specific terms
SELECT 
    file_name,
    parse_timestamp
FROM TABLE(
    invoice_search_service.SEARCH(
        'medical supplies equipment',
        10
    )
);
```

### 📊 Check Parsing Status

Monitor what's been processed:

```sql
-- View recently parsed invoices
SELECT 
    file_name,
    processing_status,
    parse_timestamp
FROM parsed_invoices
ORDER BY parse_timestamp DESC
LIMIT 10;
```

### 📈 Search Statistics

Get insights into your indexed content:

```sql
-- View search service statistics
SELECT * FROM search_service_stats;
```

---

## Common Use Cases

### Use Case 1: Find Invoices by Content

**Scenario:** You remember a vendor mentioned "rush delivery" but don't know which invoice.

```sql
SELECT 
    file_name,
    parse_timestamp
FROM TABLE(
    invoice_search_service.SEARCH(
        'rush delivery expedited',
        10
    )
);
```

### Use Case 2: Find Specific Products

**Scenario:** Find all invoices mentioning medical equipment.

```sql
SELECT 
    file_name,
    parse_timestamp,
    file_size
FROM TABLE(
    invoice_search_service.SEARCH(
        'medical equipment surgical supplies',
        20
    )
);
```

### Use Case 3: Search for Contract Terms

**Scenario:** Find invoices with specific payment terms or conditions.

```sql
SELECT 
    file_name
FROM TABLE(
    invoice_search_service.SEARCH(
        'net 30 payment terms',
        15
    )
);
```

### Use Case 4: Monitor Recent Activity

**Scenario:** Check what invoices were recently processed.

```sql
SELECT 
    file_name,
    processing_status,
    parse_timestamp
FROM parsed_invoices
WHERE parse_timestamp > DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY parse_timestamp DESC;
```

---

## Monitoring Your Pipeline

### Quick Health Check

```sql
-- One-query health check
SELECT * FROM search_service_stats;
```

Expected output:
- `total_documents_indexed`: Should match your uploaded file count
- `unique_files`: Number of distinct PDFs processed
- `first_indexed` / `last_indexed`: Timestamp range

### Check for Errors

```sql
-- See if any files failed to process
SELECT * FROM search_pipeline_monitoring
WHERE processing_status != 'SUCCESS';
```

If you see errors:
1. Check the `error_message` column
2. Verify the PDF is valid and not corrupted
3. Try processing a single file manually

---

## Next Steps

### Add More Invoices

```sql
-- Upload multiple files from a directory
-- Use wildcards to upload all files at once
PUT file:///path/to/your/invoices/* @invoice_stage AUTO_COMPRESS=FALSE;
```

Then refresh and process:
```sql
ALTER STAGE invoice_stage REFRESH;
CALL refresh_and_parse();
```

> **Tip:** You can also use Snowflake's web interface to upload files by navigating to **Data > Databases > invoice_processing_poc > invoice_pipeline > Stages > invoice_stage** and clicking the **+ Files** button.

### Build Custom Search Queries

Create saved queries for common searches:

```sql
-- Create a view for frequently searched terms
CREATE OR REPLACE VIEW urgent_invoices AS
SELECT 
    file_name,
    parse_timestamp,
    file_url
FROM TABLE(
    invoice_search_service.SEARCH(
        'urgent rush expedited priority',
        50
    )
);
```

### Integrate with Structured Data

If you're also running the aiextract project, combine search with structured data:

```sql
-- Find invoices by content, then get structured details
WITH search_results AS (
    SELECT DISTINCT file_name
    FROM TABLE(invoice_search_service.SEARCH('medical equipment', 20))
)
SELECT 
    i.invoice_number,
    i.vendor_name,
    i.invoice_date,
    i.total_amount
FROM invoice i
JOIN search_results sr ON i.file_name = sr.file_name
ORDER BY i.invoice_date DESC;
```

---

## Troubleshooting

### Problem: Search returns no results

**Solution:**
```sql
-- Check if documents are indexed
SELECT COUNT(*) FROM parsed_invoices WHERE processing_status = 'SUCCESS';

-- If count is 0, parse the documents
CALL refresh_and_parse();

-- Wait a minute, then try search again
```


### Problem: "Cortex AI not available" error

**Solution:**
- Verify your Snowflake account has Cortex AI features enabled
- Check your region supports Cortex AI features
- Contact your Snowflake account team to enable Cortex AI

---

## Tips for Success

### 1. Start Small
Begin with 2-3 sample invoices to test the pipeline before scaling up.

### 2. Use Descriptive File Names
Name your files clearly: `invoice_vendor_date.pdf` helps with organization and makes search results more meaningful.

### 3. Monitor Regularly
Check the `search_pipeline_monitoring` view daily when starting out to ensure all files are processing successfully.

### 4. Optimize Search Queries
Experiment with different search terms and combinations to find what works best for your use cases.

### 5. Combine with aiextract
For best results, run both projects:
- **aiextract**: Structured data extraction for analytics and reporting
- **search**: Full-text search for content discovery and retrieval

---

## Quick Reference Commands

```sql
-- Upload files (replace with your actual file path)
PUT file:///path/to/your/invoice.pdf @invoice_stage AUTO_COMPRESS=FALSE;

-- Upload multiple files at once
PUT file:///path/to/your/invoices/* @invoice_stage AUTO_COMPRESS=FALSE;

-- Refresh stage after upload
ALTER STAGE invoice_stage REFRESH;

-- Process files
CALL refresh_and_parse();

-- Search invoices
SELECT * FROM TABLE(invoice_search_service.SEARCH('search term', 10));

-- Check parsed invoices
SELECT * FROM parsed_invoices ORDER BY parse_timestamp DESC;

-- Check status
SELECT * FROM search_pipeline_monitoring;

-- Get stats
SELECT * FROM search_service_stats;

-- Suspend processing
ALTER TASK task_parse_invoices SUSPEND;

-- Resume processing
ALTER TASK task_parse_invoices RESUME;
```

---

## Getting Help

If you run into issues:

1. Check the error messages in `search_pipeline_monitoring`
2. Review the task execution history
3. Test with a single, simple PDF first
4. Verify Cortex AI features are enabled in your account

For more detailed information, see the full [README.md](./README.md) documentation.

---

**You're all set! 🎉**

Start searching your invoices with powerful semantic search capabilities powered by Snowflake Cortex AI.

