# Invoice Search Pipeline with Cortex AI

## Overview

This project creates an intelligent, searchable invoice system using Snowflake's Cortex AI capabilities. It combines document parsing, semantic search, and conversational AI to provide powerful invoice querying capabilities.

## Architecture

```
┌─────────────────┐
│   PDF Files     │
│   (Stage)       │
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│  Stage Stream           │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  Task: Parse Document   │
│  (LAYOUT mode)          │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  parsed_invoices Table  │
│  (Full text + metadata) │
└────────┬────────────────┘
         │
         ├──────────────────────┐
         ▼                      ▼
┌──────────────────┐   ┌──────────────────┐
│ Cortex Search    │   │  Semantic View   │
│ Service          │   │  (Join invoice   │
│                  │   │   + line items)  │
└────────┬─────────┘   └────────┬─────────┘
         │                      │
         └──────────┬───────────┘
                    ▼
         ┌──────────────────────┐
         │   Cortex Agent       │
         │   "Invoice Agent"    │
         └──────────────────────┘
```

## Components

### 1. Document Parsing Layer

**Stage and Stream:**
- `invoice_search_stage`: Internal stage for PDF storage
- `invoice_search_stream`: Stream monitoring for new files

**Parsing Task:**
- `task_parse_invoices`: Uses `SNOWFLAKE.CORTEX.PARSE_DOCUMENT` with LAYOUT mode
- Extracts full text content and structure from PDFs
- Stores results in `parsed_invoices` table

**Table:**
- `parsed_invoices`: Contains parsed content (VARIANT) and extracted text (VARCHAR)

### 2. Search Layer

**Cortex Search Service:**
- `invoice_search_service`: Full-text semantic search on invoice content
- Indexes the `extracted_text` from parsed invoices
- Provides natural language search capabilities
- Target lag: 1 minute for near real-time updates

**Attributes indexed:**
- `file_name`
- `file_size`
- `last_modified`
- `parse_timestamp`

### 3. Structured Query Layer

**Semantic View:**
- `invoice_semantic_view`: Joins invoice headers with line items from aiextract project
- Includes comprehensive semantic model with:
  - Table descriptions
  - Column descriptions and synonyms
  - Join definitions

**Available Fields:**
- Invoice header: invoice number, dates, vendor/customer info, totals
- Line items: descriptions, quantities, prices, amounts

### 4. Conversational AI Layer

**Cortex Agent:**
- `invoice_agent`: Intelligent assistant for invoice queries
- Combines search service (unstructured) with semantic view (structured)
- Natural language interface for complex queries

**Agent Capabilities:**
- Find invoices by number, vendor, customer, date, or amount
- Full-text search across invoice content
- Analyze spending patterns and trends
- Calculate aggregations and summaries
- Provide insights from invoice data

## Key Differences from aiextract Project

| Feature | aiextract | search |
|---------|-----------|--------|
| **Extraction Method** | AI_EXTRACT (structured) | PARSE_DOCUMENT (layout-aware) |
| **Output** | Structured JSON with schema | Full text + layout information |
| **Primary Use** | Data extraction & ETL | Search & retrieval |
| **Search** | None | Cortex Search Service |
| **Query Interface** | SQL only | SQL + Cortex Agent |
| **Schema** | Pre-defined response format | Layout-based parsing |

## Setup Instructions

### Step 1: Run the SQL Pipeline

```sql
-- Execute the main pipeline script
@search/invoice_search_pipeline.sql
```

This creates:
- Database schema: `invoice_processing_poc.invoice_search`
- Stage, stream, table, and task
- Cortex Search Service
- Semantic View
- Cortex Agent

### Step 2: Upload Invoice Files

```sql
USE SCHEMA invoice_search;

-- Upload files to the stage
PUT file:///path/to/invoices/*.pdf @invoice_search_stage AUTO_COMPRESS=FALSE;

-- Refresh directory
ALTER STAGE invoice_search_stage REFRESH;

-- Verify files
SELECT * FROM DIRECTORY(@invoice_search_stage);
```

### Step 3: Start the Pipeline

```sql
-- Resume the parsing task
ALTER TASK task_parse_invoices RESUME;

-- Or manually trigger for testing
CALL refresh_and_parse();
```

### Step 4: Verify Processing

```sql
-- Check parsed invoices
SELECT * FROM search_pipeline_monitoring;

-- View search service stats
SELECT * FROM search_service_stats;
```

## Usage Examples

### 1. Full-Text Search

Search for invoices containing specific text:

```sql
SELECT * FROM TABLE(
    invoice_search_service.SEARCH(
        'medical supplies equipment',
        10
    )
);
```

### 2. Structured Queries

Query structured invoice data:

```sql
-- Find all invoices from a specific vendor
SELECT 
    invoice_number,
    invoice_date,
    vendor_name,
    total_amount,
    COUNT(line_item_number) as item_count
FROM invoice_semantic_view
WHERE vendor_name ILIKE '%medical%'
GROUP BY 1, 2, 3, 4
ORDER BY invoice_date DESC;

-- Calculate total spending by vendor
SELECT 
    vendor_name,
    COUNT(DISTINCT invoice_number) as invoice_count,
    SUM(total_amount) as total_spent,
    AVG(total_amount) as avg_invoice_amount
FROM invoice_semantic_view
GROUP BY vendor_name
ORDER BY total_spent DESC;
```

### 3. Cortex Agent Queries

Use natural language to query invoices:

```sql
-- Ask the agent questions
SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'Show me all invoices from last month totaling more than $1000'
);

SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'Which vendor have we spent the most money with?'
);

SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'Find invoices containing references to medical equipment'
);

SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'What are the most common items we purchase?'
);
```

### 4. Combined Search and Query

The agent automatically uses both search and structured data:

```sql
SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'Find all invoices mentioning "rush delivery" and show me the total cost'
);
```

## Monitoring and Maintenance

### Monitor Pipeline Status

```sql
-- View recent processing activity
SELECT * FROM search_pipeline_monitoring
LIMIT 20;

-- Check for errors
SELECT * FROM search_pipeline_monitoring
WHERE processing_status != 'SUCCESS';
```

### Search Service Statistics

```sql
-- View indexing statistics
SELECT * FROM search_service_stats;
```

### Task Execution History

```sql
SELECT 
    name,
    state,
    scheduled_time,
    completed_time,
    return_value,
    error_code,
    error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name = 'TASK_PARSE_INVOICES'
ORDER BY scheduled_time DESC
LIMIT 20;
```

## Integration with aiextract Project

The search project complements the aiextract project:

1. **aiextract**: Structured data extraction → invoice tables
2. **search**: Full-text indexing + semantic queries

The semantic view (`invoice_semantic_view`) bridges both by:
- Using structured data from aiextract's invoice tables
- Making it queryable through the Cortex Agent
- Combining with search service for powerful hybrid queries

## Advanced Features

### Custom Search Queries

```sql
-- Search with filters
SELECT * FROM TABLE(
    invoice_search_service.SEARCH(
        'medical supplies',
        10,
        {'filters': {'file_size': {'$gt': 50000}}}
    )
);
```

### Agent Conversations

The Cortex Agent maintains context in conversations:

```sql
-- Start a conversation
SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'Show me invoices from Acme Corp'
);

-- Follow-up question (agent remembers context)
SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'What was the total amount?'
);
```

## Troubleshooting

### No Results in Search

1. Verify documents are parsed:
   ```sql
   SELECT COUNT(*) FROM parsed_invoices WHERE processing_status = 'SUCCESS';
   ```

2. Check search service status:
   ```sql
   SHOW CORTEX SEARCH SERVICES;
   ```

3. Refresh search service if needed:
   ```sql
   ALTER CORTEX SEARCH SERVICE invoice_search_service REFRESH;
   ```

### Agent Not Working

1. Verify agent exists:
   ```sql
   SHOW CORTEX AGENTS;
   ```

2. Check that both search service and semantic view are accessible:
   ```sql
   SELECT COUNT(*) FROM invoice_semantic_view;
   ```

### Parsing Failures

1. Check error messages:
   ```sql
   SELECT file_name, error_message 
   FROM parsed_invoices 
   WHERE processing_status != 'SUCCESS';
   ```

2. Test parsing manually:
   ```sql
   SELECT SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
       TO_FILE(@invoice_search_stage, 'test.pdf'),
       {'mode': 'LAYOUT'}
   );
   ```

## Performance Optimization

### For High Volume

```sql
-- Increase warehouse size for parsing
ALTER TASK task_parse_invoices SET WAREHOUSE = LARGE_WH;

-- Adjust search service target lag
ALTER CORTEX SEARCH SERVICE invoice_search_service 
    SET TARGET_LAG = '5 minutes';
```

### For Better Search Quality

- Ensure parsed text is clean and complete
- Use descriptive file names
- Consider adding more metadata to search attributes

## Cleanup

To remove the search pipeline:

```sql
-- Suspend task first
ALTER TASK task_parse_invoices SUSPEND;

-- Drop all objects
DROP AGENT IF EXISTS invoice_agent;
DROP CORTEX SEARCH SERVICE IF EXISTS invoice_search_service;
DROP VIEW IF EXISTS invoice_semantic_view;
DROP VIEW IF EXISTS search_pipeline_monitoring;
DROP VIEW IF EXISTS search_service_stats;
DROP PROCEDURE IF EXISTS refresh_and_parse();
DROP STREAM IF EXISTS invoice_search_stream;
DROP TABLE IF EXISTS parsed_invoices;
DROP STAGE IF EXISTS invoice_search_stage;
DROP SCHEMA IF EXISTS invoice_search;
```

## Next Steps

1. **Enhance the Agent**: Add more orchestration rules for specific use cases
2. **Add More Metadata**: Extract additional fields to make search more powerful
3. **Create Dashboards**: Build Streamlit apps using the agent
4. **Implement Alerts**: Set up notifications for specific invoice patterns
5. **Expand Synonyms**: Add more synonyms to the semantic model for better natural language understanding

