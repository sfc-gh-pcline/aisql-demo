# Invoice Search Pipeline with Cortex AI

## Overview

This project creates a searchable invoice repository using Snowflake's Cortex AI capabilities. It uses AI_PARSE_DOCUMENT to extract full text from invoice files and Cortex Search Service to enable powerful semantic search across all invoice content.

## Architecture

```
┌─────────────────┐
│ Invoice Files   │
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
│  (AI_PARSE_DOCUMENT)    │
│  (LAYOUT mode)          │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  parsed_invoices Table  │
│  (Full text + metadata) │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ Cortex Search Service   │
│ (Semantic Search)       │
└─────────────────────────┘
```

## Components

### 1. Database and Schema
- **Database:** `invoice_processing_poc`
- **Schema:** `invoice_pipeline` (shared with aiextract project)

### 2. Stage and Stream
- **Stage:** `invoice_stage` - Internal stage for invoice file storage (shared with aiextract)
  - Server-side encryption enabled
  - Directory table enabled for file tracking
- **Stream:** `invoice_parse_stream` - Monitors stage for new files to parse

### 3. Parsing Layer
- **Task:** `task_parse_invoices`
  - Uses `AI_PARSE_DOCUMENT` with LAYOUT mode
  - Extracts full text content and structure from invoice files
  - Runs on `SNOWFLAKE_INTELLIGENCE_WH` warehouse
  - Scheduled to run every 1 minute when new files are detected
- **Table:** `parsed_invoices`
  - Stores parsed content (VARIANT)
  - Includes file metadata (name, URL, size, timestamps)
  - Processing status tracking

### 4. Search Layer
- **Cortex Search Service:** `invoice_search_service`
  - Full-text semantic search on invoice content
  - Indexes the `parsed_content` from parsed invoices
  - Provides natural language search capabilities
  - Target lag: 1 minute for near real-time updates
  - Indexed attributes: `file_name`, `file_size`, `last_modified`, `parse_timestamp`

### 5. Monitoring
- **View:** `search_pipeline_monitoring` - Track processing status and errors
- **View:** `search_service_stats` - Search service statistics and metrics
- **Procedure:** `refresh_and_parse()` - Manual processing trigger

## Key Differences from aiextract Project

| Feature | aiextract | search |
|---------|-----------|--------|
| **Extraction Method** | AI_EXTRACT (structured) | AI_PARSE_DOCUMENT (layout-aware) |
| **Output** | Structured JSON with schema | Full text + layout information |
| **Primary Use** | Data extraction & ETL | Full-text search & retrieval |
| **Search** | None | Cortex Search Service |
| **Query Interface** | SQL only | SQL with semantic search |
| **Schema** | Pre-defined response format | Layout-based parsing |
| **Tables** | invoice + invoice_detail (normalized) | parsed_invoices (document-oriented) |

## Setup Instructions

### Step 1: Run the SQL Pipeline

```sql
-- Execute the main pipeline script
@search/invoice_search_pipeline.sql
```

This creates (in the `invoice_processing_poc.invoice_pipeline` schema):
1. Database and schema (if not exists)
2. Shared stage: `invoice_stage` (same as aiextract)
3. Table: `parsed_invoices`
4. Stream: `invoice_parse_stream`
5. Task: `task_parse_invoices`
6. Cortex Search Service: `invoice_search_service`
7. Monitoring views and helper procedures

### Step 2: Upload Invoice Files

```sql
USE DATABASE invoice_processing_poc;
USE SCHEMA invoice_pipeline;

-- Upload files to the shared stage
PUT file:///path/to/invoices/*.pdf @invoice_stage AUTO_COMPRESS=FALSE;

-- Refresh directory
ALTER STAGE invoice_stage REFRESH;

-- Verify files
SELECT * FROM DIRECTORY(@invoice_stage);
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

### 1. Search for Specific Content

Search for invoices containing specific terms:

```sql
-- Find invoices mentioning medical supplies
SELECT * FROM TABLE(
    invoice_search_service.SEARCH(
        'medical supplies equipment',
        10
    )
);
```

### 2. Search with Multiple Terms

```sql
-- Find invoices about rush deliveries
SELECT 
    parsed_id,
    file_name,
    parse_timestamp
FROM TABLE(
    invoice_search_service.SEARCH(
        'rush delivery expedited',
        20
    )
);
```

### 3. Monitor Recent Parsing

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

### 4. Search Service Statistics

```sql
-- Get search index statistics
SELECT * FROM search_service_stats;
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

1. **aiextract**: Structured data extraction → normalized invoice tables
2. **search**: Full-text document parsing → searchable content

Both projects:
- Share the same stage (`invoice_stage`) for file storage
- Use the same schema (`invoice_pipeline`)
- Can process the same invoice files independently
- Provide different query capabilities (structured SQL vs semantic search)

## Advanced Features

### Search with Context

```sql
-- Search for multiple related terms
SELECT 
    file_name,
    parse_timestamp,
    file_size
FROM TABLE(
    invoice_search_service.SEARCH(
        'medical supplies surgical equipment',
        20
    )
);
```

### Combining Search with SQL

```sql
-- Search and then analyze results
WITH search_results AS (
    SELECT parsed_id
    FROM TABLE(invoice_search_service.SEARCH('urgent rush', 50))
)
SELECT 
    p.file_name,
    p.parse_timestamp,
    p.file_size
FROM parsed_invoices p
JOIN search_results sr ON p.parsed_id = sr.parsed_id
WHERE p.processing_status = 'SUCCESS'
ORDER BY p.parse_timestamp DESC;
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

-- Drop search-specific objects
DROP CORTEX SEARCH SERVICE IF EXISTS invoice_search_service;
DROP VIEW IF EXISTS search_pipeline_monitoring;
DROP VIEW IF EXISTS search_service_stats;
DROP PROCEDURE IF EXISTS refresh_and_parse();
DROP STREAM IF EXISTS invoice_parse_stream;
DROP TABLE IF EXISTS parsed_invoices;

-- Note: invoice_stage is shared with aiextract - don't drop unless cleaning up everything
-- Note: invoice_pipeline schema is shared with aiextract - don't drop unless cleaning up everything
```

## Next Steps

1. **Enhance Search**: Add more metadata attributes to improve search filtering
2. **Create Dashboards**: Build Streamlit apps using the search service
3. **Implement Alerts**: Set up notifications for specific invoice patterns found through search
4. **Optimize Performance**: Adjust target lag and warehouse size based on volume
5. **Expand Use Cases**: Use search to find specific clauses, terms, or patterns in invoices

