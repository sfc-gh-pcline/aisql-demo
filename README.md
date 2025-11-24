# Snowflake Invoice Processing - AI Powered Solutions

This repository contains a complete suite of invoice processing solutions using Snowflake's Cortex AI capabilities, including backend data extraction, semantic search, and a web-based user interface.

## Project Structure

```
aisql-demo/
├── aiextract/          # Structured data extraction pipeline
│   ├── snowflake_invoice_pipeline_v2.sql
│   ├── snowflake_invoice_pipeline.sql
│   ├── create_semantic_view.sql
│   ├── invoice_semantic_model.yaml
│   ├── AI_EXTRACT_EXAMPLES.sql
│   ├── testing_validation.sql
│   └── Documentation...
│
├── search/             # Full-text search pipeline
│   ├── invoice_search_pipeline.sql
│   ├── README.md
│   └── QUICK_START.md
│
├── streamlit/          # Web-based UI application
│   ├── app.py
│   ├── InvoiceExtraction_AI_Extract.py
│   ├── streamlit_setup.sql
│   ├── dockerfile
│   ├── requirements.txt
│   └── README.md
│
└── docs/               # Sample invoice PDFs
    ├── MB66680464.pdf
    └── B20277431.pdf
```

## Three Solutions

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

### 🔍 search - Full-Text Search with Cortex Search

**Purpose:** Enable full-text semantic search across invoice content

**Best for:**
- Finding invoices by content
- Searching for specific terms or phrases
- Discovering documents with similar content
- Content-based retrieval

**Technology:**
- `SNOWFLAKE.CORTEX.AI_PARSE_DOCUMENT` - Layout-aware parsing
- Cortex Search Service - Semantic search

**Output:**
```
Invoice Files → Parse → parsed_invoices → Cortex Search Service
                                                ↓
                                        Semantic Search
```

[📖 Full Documentation →](./search/README.md)

---

### 🖥️ streamlit - Web-Based User Interface

**Purpose:** Provide an interactive web application for invoice processing and review

**Best for:**
- User-friendly invoice upload and processing
- Interactive invoice review and editing
- Visual validation of extracted data
- Business user access (no SQL required)
- Demonstration and proof-of-concept

**Technology:**
- Streamlit web framework
- Snowpark for Python integration
- Snowflake Container Services (SPCS) deployment
- OAuth authentication via Snowflake

**Features:**
```
Web Interface
├── Upload invoices via drag-and-drop
├── Process using AI_EXTRACT
├── Review extracted data in tables
├── Edit and correct extracted values
└── Save to Snowflake database
```

[📖 Full Documentation →](./streamlit/README.md)

---

## Quick Comparison

| Feature | aiextract | search | streamlit |
|---------|-----------|--------|-----------|
| **Type** | Backend pipeline | Backend pipeline | Frontend UI |
| **Extraction** | AI_EXTRACT | AI_PARSE_DOCUMENT | AI_EXTRACT |
| **Mode** | Structured schema | Layout-aware | User-driven |
| **Output** | Normalized tables | Full text document | Interactive web UI |
| **Query Style** | SQL only | SQL with semantic search | Web forms & tables |
| **Search** | ❌ | ✅ Cortex Search Service | ❌ |
| **User Interface** | ❌ | ❌ | ✅ Web application |
| **Best for** | Automation & ETL | Content discovery | Manual review & correction |
| **Deployment** | SQL scripts | SQL scripts | Container on SPCS |
| **Authentication** | Snowflake roles | Snowflake roles | Snowflake OAuth |
| **Schema** | invoice_pipeline | invoice_pipeline (shared) | APP_SCHEMA (separate) |

## Which One Should You Use?

### Use **aiextract** if you need:
- ✅ Automated backend processing
- ✅ Structured data in relational tables
- ✅ Integration with BI tools and downstream systems
- ✅ Predefined schema and fields
- ✅ High-volume batch processing
- ✅ Traditional SQL queries and analytics

### Use **search** if you need:
- ✅ Full-text search capabilities
- ✅ Finding invoices by content or keywords
- ✅ Exploratory analysis across documents
- ✅ Semantic search and similarity matching
- ✅ Content discovery

### Use **streamlit** if you need:
- ✅ User-friendly web interface
- ✅ Interactive invoice upload and processing
- ✅ Manual review and data correction
- ✅ Business user access (no SQL knowledge required)
- ✅ Quick proof-of-concept demonstrations
- ✅ Hybrid automated + manual workflows

### Use **all three** for:
- ✅ Complete end-to-end invoice processing solution
- ✅ Automated processing (aiextract) + Search (search) + User interface (streamlit)
- ✅ Support for both automated and manual workflows
- ✅ Maximum flexibility and capability

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

### Option 2: Full-Text Search (search)

```sql
-- Run the search pipeline (uses same schema as aiextract)
@search/invoice_search_pipeline.sql

-- Upload invoices (uses same stage as aiextract)
PUT file:///path/to/invoices/* @invoice_stage AUTO_COMPRESS=FALSE;

-- Process
CALL refresh_and_parse();

-- Search
SELECT * FROM TABLE(invoice_search_service.SEARCH('medical supplies', 10));
```

[📖 search Quick Start →](./search/QUICK_START.md)

---

### Option 3: Web-Based UI (streamlit)

```bash
# 1. Bootstrap Snowflake objects (one-time)
# Run streamlit_setup.sql in Snowflake

# 2. Build and push Docker image
docker build --rm --platform linux/amd64 -t invoice_streamlit_app .
docker tag invoice_streamlit_app \
    <orgname>-<account>.registry.snowflakecomputing.com/invoice_processing_poc/app_schema/invoice_repo/invoice_streamlit_app

docker push <orgname>-<account>.registry.snowflakecomputing.com/invoice_processing_poc/app_schema/invoice_repo/invoice_streamlit_app

# 3. Create and start the service
# See streamlit/README.md for complete deployment steps
```

Access via: `https://<service-endpoint>.snowflakecomputing.app`

[📖 streamlit Setup Guide →](./streamlit/README.md)

---

### Option 4: Complete Solution (Recommended for Production)

Deploy all three projects for a comprehensive invoice processing platform:

1. **aiextract** - Automated backend processing and structured data
2. **search** - Full-text search across all invoices
3. **streamlit** - Web UI for manual processing and review

```sql
-- 1. Set up aiextract pipeline
@aiextract/snowflake_invoice_pipeline_v2.sql

-- 2. Set up search pipeline
@search/invoice_search_pipeline.sql

-- 3. Set up streamlit infrastructure
@streamlit/streamlit_setup.sql

-- 4. Deploy streamlit container (see streamlit/README.md)
-- Build and push Docker image, create SPCS service

-- 5. Upload invoices to shared stage
PUT file:///path/to/invoices/* @invoice_stage AUTO_COMPRESS=FALSE;

-- 6. Automated processing (backend)
CALL refresh_and_process();  -- aiextract: AI_EXTRACT
CALL refresh_and_parse();     -- search: AI_PARSE_DOCUMENT

-- 7. Or use web UI (frontend)
-- Navigate to streamlit app URL, upload and process interactively

-- 8. Query using any method:
-- SQL on structured data
SELECT * FROM invoice_pipeline.invoice;

-- Full-text search
SELECT * FROM TABLE(invoice_search_service.SEARCH('medical supplies', 10));

-- Web interface
-- Use streamlit app for visual review and editing
```

**Benefits of Complete Solution:**
- ✅ Automated high-volume processing (aiextract)
- ✅ Powerful search capabilities (search)
- ✅ User-friendly interface for exceptions (streamlit)
- ✅ Flexible workflow: automated + manual as needed
- ✅ Single source of truth in Snowflake

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
Invoice Files → Stream → AI_PARSE_DOCUMENT → parsed_invoices
                              ↓
                        (Full text)
                              ↓
                      Cortex Search Service
                              ↓
                      Semantic Search
```

### streamlit Architecture

```
User Browser → Streamlit Web App (SPCS)
                    ↓
        ┌───────────┴───────────┐
        ↓                       ↓
   Upload PDF            Display Results
        ↓                       ↓
   AI_EXTRACT              Query Data
        ↓                       ↓
   Save to DB            Edit & Validate
```

### Complete Integrated Architecture

```
                    Invoice Files
                         |
        ┌────────────────┼────────────────┐
        ↓                ↓                ↓
   aiextract        search          streamlit
   (Backend)      (Backend)        (Frontend)
        |                |                |
        ↓                ↓                ↓
  Structured        Full-text         Web UI
   Tables            Index          Interactive
        |                |                |
        └────────────────┼────────────────┘
                         ↓
              Snowflake Data Platform
                         ↓
        ┌────────────────┼────────────────┐
        ↓                ↓                ↓
    SQL Queries    Semantic Search    Web Access
    (Analysts)      (Researchers)     (Business)
```

## Key Technologies

### Snowflake Cortex AI Functions

1. **AI_EXTRACT**
   - Structured extraction with custom schema
   - Used in: aiextract and streamlit projects
   - Best for: Known fields and structured output

2. **AI_PARSE_DOCUMENT**
   - Layout-aware document parsing
   - Modes: LAYOUT, OCR
   - Used in: search project
   - Best for: Full-text extraction and document understanding

### Snowflake Cortex Services

3. **Cortex Search Service**
   - Semantic search on text data
   - Used in: search project
   - Best for: Finding documents by content and meaning

### Snowflake Platform Features

4. **Snowflake Container Services (SPCS)**
   - Run containerized applications in Snowflake
   - Used in: streamlit project
   - Best for: Web applications with Snowflake OAuth

5. **Snowpark Python**
   - Python API for Snowflake
   - Used in: streamlit project
   - Best for: Data processing and integration

6. **Streams and Tasks**
   - Change data capture and automation
   - Used in: aiextract and search projects
   - Best for: Event-driven processing pipelines

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
SELECT 
    file_name,
    parse_timestamp
FROM TABLE(
    invoice_search_service.SEARCH(
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

### Use Case 4: Search for Contract Terms
**Solution:** search → Cortex Search

```sql
SELECT 
    file_name,
    parse_timestamp
FROM TABLE(
    invoice_search_service.SEARCH(
        'net 30 payment terms due on receipt',
        15
    )
);
```

### Use Case 5: Manual Invoice Review and Correction
**Solution:** streamlit → Web UI

1. User uploads invoice PDF through web interface
2. AI_EXTRACT processes and displays extracted data
3. User reviews data in editable tables
4. User corrects any errors or missing values
5. Validated data saves to Snowflake tables
6. Audit trail maintained for all changes

**Perfect for:**
- Low-volume invoices requiring review
- Training and validating AI extraction
- Exception handling in automated workflows
- Demonstrating capabilities to stakeholders

## Requirements

### Snowflake Account
- Cortex AI features enabled
- Enterprise edition or higher (for some features)
- Supported region for Cortex AI
- Snowflake Container Services (SPCS) enabled (for streamlit)

### Permissions

**For aiextract and search:**
- CREATE DATABASE, SCHEMA, TABLE, VIEW
- CREATE STAGE, STREAM, TASK
- CREATE CORTEX SEARCH SERVICE
- CREATE SEMANTIC VIEW
- USAGE on WAREHOUSE

**Additional for streamlit:**
- BIND SERVICE ENDPOINT (account-level privilege)
- CREATE COMPUTE POOL
- CREATE IMAGE REPOSITORY
- CREATE SERVICE
- Docker installed locally (for building container image)

### Warehouse
- Uses: `SNOWFLAKE_INTELLIGENCE_WH`
- This is a specialized warehouse for Cortex AI workloads
- Automatically optimized for AI functions

### Compute Pool (for streamlit)
- CPU_X64_S or larger instance family
- MIN_NODES = 1, MAX_NODES = 2 (adjustable)
- AUTO_RESUME enabled

## Best Practices

### 1. Start with Proof of Concept
- Use **streamlit** for quick demonstrations and to understand AI extraction
- Test with sample invoices before scaling

### 2. Build Backend Infrastructure
- Deploy **aiextract** for automated, high-volume processing
- Use for production ETL and data warehousing

### 3. Add Search Capabilities
- Deploy **search** for content discovery and semantic search
- Enables powerful querying across unstructured content

### 4. Choose the Right Tool for Each Workflow
- **Automated batch processing** → aiextract
- **Content discovery** → search  
- **Manual review/exceptions** → streamlit
- **Hybrid workflows** → all three

### 5. Use Consistent File Names
Name your PDFs consistently: `invoice_vendor_YYYYMMDD.pdf`

### 6. Monitor All Pipelines
- Check task execution history (aiextract, search)
- Review processing success rates
- Monitor search service performance
- Track streamlit service health and usage

### 7. Iterate on Schemas and Models
- Update AI_EXTRACT schema based on your invoice formats
- Add synonyms to semantic view for better matching
- Refine streamlit UI based on user feedback

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

### Problem: Streamlit App Not Accessible

```sql
-- Check service status
SHOW SERVICES IN SCHEMA invoice_processing_poc.app_schema;

-- Check service logs
CALL SYSTEM$GET_SERVICE_LOGS('invoice_processing_poc.app_schema.invoice_streamlit_service', '0', 'invoice-streamlit-container', 100);

-- Check compute pool status
SHOW COMPUTE POOLS;

-- Restart service if needed
ALTER SERVICE invoice_processing_poc.app_schema.invoice_streamlit_service SUSPEND;
ALTER SERVICE invoice_processing_poc.app_schema.invoice_streamlit_service RESUME;
```

### Problem: Streamlit App Loads but Errors

- Check warehouse is running and accessible
- Verify role has access to required schemas and tables
- Check service role grants: `SHOW GRANTS TO SERVICE invoice_streamlit_service;`
- Review Python dependencies in requirements.txt

## Contributing

When adding new features or improvements:

1. Test with sample invoices first
2. Update documentation in relevant project folders
3. Add examples to quick start guides
4. Consider compatibility between projects
5. For streamlit changes:
   - Test locally before building Docker image
   - Update requirements.txt for new dependencies
   - Test authentication and permissions

### Development Workflow

**For Backend (aiextract/search):**
- Develop and test SQL scripts in Snowflake worksheet
- Update documentation and examples
- Test with sample PDFs

**For Frontend (streamlit):**
- Develop locally: `streamlit run app.py`
- Test with Snowflake connection
- Build Docker image and push to SPCS
- Update service definition if needed

## License

[Add your license information here]

## Support

For questions or issues:
1. Check the project-specific documentation
2. Review troubleshooting sections
3. Test with sample PDFs in docs/

---

## Quick Links

### Documentation
- [aiextract Documentation](./aiextract/README.md)
- [search Documentation](./search/README.md)
- [streamlit Documentation](./streamlit/README.md)

### Quick Start Guides
- [aiextract Quick Start](./aiextract/QUICK_START.md)
- [search Quick Start](./search/QUICK_START.md)

### Deployment Files
- [aiextract Main Script](./aiextract/snowflake_invoice_pipeline_v2.sql)
- [search Main Script](./search/invoice_search_pipeline.sql)
- [streamlit Setup Script](./streamlit/streamlit_setup.sql)

---

## Summary

This repository provides three complementary solutions for AI-powered invoice processing:

| Project | Purpose | Deployment | Best For |
|---------|---------|------------|----------|
| **aiextract** | Automated structured data extraction | SQL scripts | High-volume automation |
| **search** | Full-text semantic search | SQL scripts | Content discovery |
| **streamlit** | Interactive web interface | Container (SPCS) | Manual review & demos |

**Ready to process invoices with AI? Pick a project and get started! 🚀**

