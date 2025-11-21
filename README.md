# Snowflake Invoice Processing - AI Powered Solutions

This repository contains two complementary approaches to invoice processing using Snowflake's Cortex AI capabilities.

## Project Structure

```
aisql-demo/
├── aiextract/          # Structured data extraction pipeline
│   ├── snowflake_invoice_pipeline_v2.sql
│   ├── snowflake_invoice_pipeline.sql
│   ├── AI_EXTRACT_EXAMPLES.sql
│   ├── testing_validation.sql
│   └── Documentation...
│
├── search/             # Search and conversational AI pipeline
│   ├── invoice_search_pipeline.sql
│   ├── README.md
│   └── QUICK_START.md
│
└── docs/              # Sample invoice PDFs
    ├── MB66680464.pdf
    └── B20277431.pdf
```

## Two Approaches

### 📊 aiextract - Structured Data Extraction

**Purpose:** Extract structured data from invoices into relational tables

**Best for:**
- ETL and data warehousing
- Reporting and analytics
- Integration with existing systems
- Structured queries and aggregations

**Technology:**
- `SNOWFLAKE.CORTEX.AI_EXTRACT` - Schema-driven extraction
- Custom response format with predefined fields
- Normalized tables (invoice header + line items)

**Output:**
```
invoice table           invoice_detail table
├── invoice_number     ├── line_description
├── vendor_name        ├── quantity
├── total_amount       ├── unit_price
└── ...                └── ...
```

[📖 Full Documentation →](./aiextract/README.md)

---

### 🔍 search - Search and Conversational AI

**Purpose:** Enable full-text search and natural language queries on invoices

**Best for:**
- Finding invoices by content
- Ad-hoc exploratory queries
- Natural language questions
- Conversational interfaces

**Technology:**
- `SNOWFLAKE.CORTEX.PARSE_DOCUMENT` - Layout-aware parsing
- Cortex Search Service - Semantic search
- Semantic Views - Schema with synonyms
- Cortex Agent - Conversational AI

**Output:**
```
Conversational Interface
        ↓
┌───────────────────────┐
│   Cortex Agent        │
└───────┬───────────────┘
        ├─→ Search Service (full-text)
        └─→ Semantic View (structured)
```

[📖 Full Documentation →](./search/README.md)

---

## Quick Comparison

| Feature | aiextract | search |
|---------|-----------|--------|
| **Extraction** | AI_EXTRACT | PARSE_DOCUMENT |
| **Mode** | Structured schema | Layout-aware |
| **Output** | Normalized tables | Full text + metadata |
| **Query Style** | SQL only | SQL + Natural language |
| **Search** | ❌ | ✅ Cortex Search |
| **Agent** | ❌ | ✅ Cortex Agent |
| **Best for** | Data warehousing | Search & exploration |
| **Integration** | Easy SQL joins | Conversational UI |

## Which One Should You Use?

### Use **aiextract** if you need:
- ✅ Structured data in relational tables
- ✅ Integration with BI tools
- ✅ Predefined schema and fields
- ✅ Traditional SQL queries
- ✅ Data validation and quality checks

### Use **search** if you need:
- ✅ Full-text search capabilities
- ✅ Natural language queries
- ✅ Conversational interfaces
- ✅ Exploratory analysis
- ✅ Finding documents by content

### Use **both** for:
- ✅ Complete invoice processing solution
- ✅ Structured data + search
- ✅ Conversational AI with structured queries
- ✅ Best of both worlds

## Getting Started

### Option 1: Structured Data Extraction (aiextract)

```sql
-- Run the aiextract pipeline
@aiextract/snowflake_invoice_pipeline_v2.sql

-- Upload invoices
PUT file:///path/to/invoices/*.pdf @invoice_stage AUTO_COMPRESS=FALSE;

-- Process
CALL refresh_and_process();

-- Query
SELECT * FROM invoice WHERE vendor_name = 'Acme Corp';
```

[📖 aiextract Quick Start →](./aiextract/QUICK_START.md)

---

### Option 2: Search & Conversational AI (search)

```sql
-- Run the search pipeline
@search/invoice_search_pipeline.sql

-- Upload invoices
PUT file:///path/to/invoices/*.pdf @invoice_search_stage AUTO_COMPRESS=FALSE;

-- Process
CALL refresh_and_parse();

-- Search
SELECT * FROM TABLE(invoice_search_service.SEARCH('medical supplies', 10));

-- Ask questions
SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'Show me all invoices from last month'
);
```

[📖 search Quick Start →](./search/QUICK_START.md)

---

### Option 3: Both (Recommended for Production)

The **search** project's semantic view and agent work with the **aiextract** project's tables, giving you:

1. **Structured data** in `invoice` and `invoice_detail` tables
2. **Full-text search** via Cortex Search Service
3. **Conversational queries** via Cortex Agent

```sql
-- 1. Set up aiextract first
@aiextract/snowflake_invoice_pipeline_v2.sql

-- 2. Then set up search
@search/invoice_search_pipeline.sql

-- 3. Upload to both stages
PUT file:///path/to/invoices/*.pdf @invoice_stage AUTO_COMPRESS=FALSE;
PUT file:///path/to/invoices/*.pdf @invoice_search_stage AUTO_COMPRESS=FALSE;

-- 4. Process both
CALL invoice_pipeline.refresh_and_process();
CALL invoice_search.refresh_and_parse();

-- 5. Query using any method:
-- SQL on structured data
SELECT * FROM invoice_pipeline.invoice;

-- Full-text search
SELECT * FROM TABLE(invoice_search.invoice_search_service.SEARCH('term', 10));

-- Natural language
SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT('invoice_agent', 'your question');
```

## Sample Invoices

The `docs/` folder contains sample invoices you can use for testing:
- `MB66680464.pdf`
- `B20277431.pdf`

These are real-world invoice formats that demonstrate the capabilities of both pipelines.

## Architecture Overview

### aiextract Architecture

```
PDF → Stream → AI_EXTRACT → raw_json → Parse → invoice + invoice_detail
                  ↓
            (Structured schema)
```

### search Architecture

```
PDF → Stream → PARSE_DOCUMENT → parsed_invoices
                    ↓
              (Full text)
                    ↓
         ┌──────────┴──────────┐
         ↓                     ↓
  Search Service      Semantic View
         ↓                     ↓
         └──────────┬──────────┘
                    ↓
            Cortex Agent
```

### Combined Architecture

```
                PDF Files
                    ↓
        ┌───────────┴───────────┐
        ↓                       ↓
   aiextract               search
        ↓                       ↓
  Structured Tables      Full-text Index
        ↓                       ↓
        └───────────┬───────────┘
                    ↓
         Unified Query Interface
    (SQL + Search + Conversational)
```

## Key Technologies

### Snowflake Cortex AI Functions

1. **AI_EXTRACT**
   - Structured extraction with custom schema
   - Used in: aiextract project
   - Best for: Known fields and structured output

2. **PARSE_DOCUMENT**
   - Layout-aware document parsing
   - Modes: LAYOUT, OCR
   - Used in: search project
   - Best for: Full-text extraction

### Snowflake Cortex Services

3. **Cortex Search Service**
   - Semantic search on text data
   - Used in: search project
   - Best for: Finding documents by content

4. **Semantic Views**
   - Schema with descriptions and synonyms
   - Used in: search project
   - Best for: Natural language understanding

5. **Cortex Agent**
   - Conversational AI interface
   - Combines search + structured queries
   - Used in: search project
   - Best for: Natural language queries

## Common Use Cases

### Use Case 1: Monthly Financial Reporting
**Solution:** aiextract → BI tool integration

```sql
SELECT 
    DATE_TRUNC('MONTH', invoice_date) as month,
    SUM(total_amount) as total,
    COUNT(*) as invoice_count
FROM invoice_pipeline.invoice
GROUP BY month;
```

### Use Case 2: Find All Invoices Mentioning Specific Items
**Solution:** search → Full-text search

```sql
SELECT * FROM TABLE(
    invoice_search.invoice_search_service.SEARCH(
        'laptop computer equipment',
        20
    )
);
```

### Use Case 3: Expense Analysis by Vendor
**Solution:** aiextract → Structured queries

```sql
SELECT 
    vendor_name,
    COUNT(*) as invoice_count,
    SUM(total_amount) as total_spent
FROM invoice_pipeline.invoice
GROUP BY vendor_name
ORDER BY total_spent DESC;
```

### Use Case 4: Ad-hoc Conversational Queries
**Solution:** search → Cortex Agent

```sql
SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
    'invoice_agent',
    'What were our top 3 expenses last quarter?'
);
```

## Requirements

### Snowflake Account
- Cortex AI features enabled
- Enterprise edition or higher (for some features)
- Supported region for Cortex AI

### Permissions
- CREATE DATABASE, SCHEMA, TABLE, VIEW
- CREATE STAGE, STREAM, TASK
- CREATE CORTEX SEARCH SERVICE
- CREATE CORTEX AGENT
- USAGE on WAREHOUSE

### Warehouse
- Minimum: SMALL
- Recommended: MEDIUM for production
- Can be adjusted based on volume

## Best Practices

### 1. Start with aiextract
If you're new to invoice processing, start with the aiextract project to understand the data structure.

### 2. Add search for Scale
Once you have structured data, add the search project for powerful query capabilities.

### 3. Use Consistent File Names
Name your PDFs consistently: `invoice_vendor_YYYYMMDD.pdf`

### 4. Monitor Both Pipelines
- Check task execution history
- Review processing success rates
- Monitor search service performance

### 5. Iterate on Schemas
- Update AI_EXTRACT schema based on your invoice formats
- Refine agent instructions based on common queries
- Add synonyms to semantic view for better matching

## Troubleshooting

### Problem: Extraction/Parsing Failures

**aiextract:**
```sql
SELECT * FROM invoice_pipeline.raw_json 
WHERE processing_status = 'ERROR';
```

**search:**
```sql
SELECT * FROM invoice_search.parsed_invoices 
WHERE processing_status != 'SUCCESS';
```

### Problem: Tasks Not Running

```sql
-- Check task status
SHOW TASKS;

-- Check execution history
SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name ILIKE '%invoice%'
ORDER BY scheduled_time DESC;
```

### Problem: Search Not Working

```sql
-- Verify documents are indexed
SELECT * FROM invoice_search.search_service_stats;

-- Refresh search service
ALTER CORTEX SEARCH SERVICE invoice_search.invoice_search_service REFRESH;
```

## Contributing

When adding new features or improvements:

1. Test with sample invoices first
2. Update documentation
3. Add examples to quick start guides
4. Consider compatibility between projects

## License

[Add your license information here]

## Support

For questions or issues:
1. Check the project-specific documentation
2. Review troubleshooting sections
3. Test with sample PDFs in docs/

---

## Quick Links

- [aiextract Documentation](./aiextract/README.md)
- [aiextract Quick Start](./aiextract/QUICK_START.md)
- [search Documentation](./search/README.md)
- [search Quick Start](./search/QUICK_START.md)

---

**Ready to process invoices with AI? Pick a project and get started! 🚀**

