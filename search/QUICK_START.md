# Quick Start Guide - Invoice Search Pipeline

Get up and running with the Invoice Search Pipeline in minutes.

## Prerequisites

- Snowflake account with Cortex AI features enabled
- Warehouse: `COMPUTE_WH` (or adjust warehouse names in the SQL)
- Sample invoice PDFs (we'll use the ones from the docs folder)

## 5-Minute Setup

### 1. Create the Pipeline

```sql
-- Run the complete setup
@search/invoice_search_pipeline.sql
```

This single script creates everything you need:
- ✓ Database schema
- ✓ Stage and stream
- ✓ Parsing task
- ✓ Search service
- ✓ Semantic view
- ✓ Cortex Agent

**Time: ~2 minutes**

### 2. Upload Sample Invoices

```sql
USE DATABASE invoice_processing_poc;
USE SCHEMA invoice_search;

-- Upload the sample PDFs
PUT file:///Users/pcline/My\ Drive/Accounts/Grayson/Inspire/Document\ Parsing/aisql-demo/docs/MB66680464.pdf 
    @invoice_search_stage 
    AUTO_COMPRESS=FALSE;

PUT file:///Users/pcline/My\ Drive/Accounts/Grayson/Inspire/Document\ Parsing/aisql-demo/docs/B20277431.pdf 
    @invoice_search_stage 
    AUTO_COMPRESS=FALSE;

-- Refresh the stage
ALTER STAGE invoice_search_stage REFRESH;

-- Verify upload
SELECT * FROM DIRECTORY(@invoice_search_stage);
```

**Time: ~1 minute**

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
SELECT * FROM TABLE(
    invoice_search_service.SEARCH(
        'invoice',
        5
    )
);
```

### 📊 Structured Query

Query invoice data (requires aiextract project to be set up):

```sql
-- Get invoice summary
SELECT 
    invoice_number,
    vendor_name,
    invoice_date,
    total_amount,
    currency_code
FROM invoice_semantic_view
ORDER BY invoice_date DESC
LIMIT 10;
```

### 🤖 Ask the Agent

Use natural language to query your invoices:

```sql
-- Simple question
SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'How many invoices do we have?'
);

-- More complex query
SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'Show me the total amount for all invoices and break it down by vendor'
);

-- Search-based query
SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'Find invoices that mention medical supplies or equipment'
);
```

---

## Common Use Cases

### Use Case 1: Find Invoices by Content

**Scenario:** You remember a vendor mentioned "rush delivery" but don't know which invoice.

```sql
SELECT * FROM TABLE(
    invoice_search_service.SEARCH(
        'rush delivery',
        10
    )
);
```

### Use Case 2: Vendor Analysis

**Scenario:** You want to know which vendors you've paid the most.

```sql
SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'Which vendors have we spent the most money with? Show me the top 5.'
);
```

### Use Case 3: Date-Based Queries

**Scenario:** You need all invoices from last quarter.

```sql
SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'Show me all invoices from the last 3 months with their totals'
);
```

### Use Case 4: Item-Level Search

**Scenario:** You want to find all invoices containing a specific product.

```sql
SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'Find all invoices where we purchased laptops or computers'
);
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

```bash
# Upload a whole directory
PUT file:///path/to/invoices/*.pdf @invoice_search_stage AUTO_COMPRESS=FALSE;
```

Then refresh and process:
```sql
CALL refresh_and_parse();
```

### Customize the Agent

Edit the agent's orchestration instructions to match your specific needs:

```sql
ALTER CORTEX AGENT invoice_agent SET
    ORCHESTRATION_INSTRUCTIONS = 'Your custom instructions here...';
```

### Create Reports

Build standard queries for common questions:

```sql
-- Monthly spending report
SELECT 
    DATE_TRUNC('MONTH', invoice_date) as month,
    COUNT(*) as invoice_count,
    SUM(total_amount) as total_spent
FROM invoice_semantic_view
GROUP BY month
ORDER BY month DESC;
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

### Problem: Agent gives unexpected answers

**Solution:**
```sql
-- Test the underlying views directly
SELECT COUNT(*) FROM invoice_semantic_view;

-- If this returns 0, you need to set up the aiextract project first
-- The semantic view joins data from invoice_pipeline.invoice and invoice_pipeline.invoice_detail
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
Name your PDFs clearly: `invoice_vendor_date.pdf` helps with organization.

### 3. Monitor Regularly
Check the `search_pipeline_monitoring` view daily when starting out.

### 4. Iterate on Agent Instructions
As you use the agent, refine the orchestration instructions based on common questions.

### 5. Combine with aiextract
For best results, run both projects:
- **aiextract**: Structured data extraction
- **search**: Full-text search and conversational queries

---

## Quick Reference Commands

```sql
-- Upload files
PUT file:///path/to/invoice.pdf @invoice_search_stage AUTO_COMPRESS=FALSE;

-- Process files
CALL refresh_and_parse();

-- Search invoices
SELECT * FROM TABLE(invoice_search_service.SEARCH('search term', 10));

-- Ask agent
SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT('invoice_agent', 'your question');

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

Start querying your invoices with natural language and powerful search capabilities.

