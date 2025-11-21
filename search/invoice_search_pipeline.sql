-- ============================================================================
-- Snowflake Invoice Search Pipeline using AI_PARSE_DOCUMENT and Cortex Search
-- ============================================================================
-- This pipeline creates a searchable invoice repository using:
-- - AI_PARSE_DOCUMENT for layout-aware extraction
-- - Cortex Search Service for semantic search
-- - Semantic views for structured queries
-- - Cortex Agent for conversational interaction
-- ============================================================================

-- ============================================================================
-- STEP 1: SETUP DATABASE AND SCHEMA
-- ============================================================================

CREATE DATABASE IF NOT EXISTS invoice_processing_poc;
USE DATABASE invoice_processing_poc;

CREATE SCHEMA IF NOT EXISTS invoice_search;
USE SCHEMA invoice_search;

-- ============================================================================
-- STEP 2: CREATE STAGE FOR PDF INVOICES
-- ============================================================================

CREATE OR REPLACE STAGE invoice_search_stage
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for storing PDF invoice files for search indexing';

-- ============================================================================
-- STEP 3: CREATE STREAM ON STAGE DIRECTORY
-- ============================================================================

-- Stream to capture new files added to the stage
-- Note: Directory streams cannot be APPEND_ONLY since they track both additions and deletions
CREATE OR REPLACE STREAM invoice_search_stream 
ON STAGE invoice_search_stage
COMMENT = 'Stream to track new PDF files for search indexing';

-- ============================================================================
-- STEP 4: CREATE TABLE FOR PARSED INVOICE DATA
-- ============================================================================

CREATE OR REPLACE TABLE parsed_invoices (
    parsed_id NUMBER AUTOINCREMENT PRIMARY KEY,
    file_name VARCHAR(500) NOT NULL,
    file_url VARCHAR(1000) NOT NULL,
    file_size NUMBER,
    last_modified TIMESTAMP_NTZ,
    parsed_content VARIANT NOT NULL,
    extracted_text VARCHAR,
    parse_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    processing_status VARCHAR(50) DEFAULT 'SUCCESS',
    error_message VARCHAR(5000)
);

-- ============================================================================
-- STEP 5: CREATE TASK TO PARSE DOCUMENTS USING AI_PARSE_DOCUMENT
-- ============================================================================

CREATE OR REPLACE TASK task_parse_invoices
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('invoice_search_stream')
AS
INSERT INTO parsed_invoices (
    file_name,
    file_url,
    file_size,
    last_modified,
    parsed_content,
    extracted_text,
    processing_status
)
SELECT 
    s.RELATIVE_PATH as file_name,
    BUILD_SCOPED_FILE_URL(@invoice_search_stage, s.RELATIVE_PATH) as file_url,
    s.SIZE as file_size,
    s.LAST_MODIFIED,
    SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
        TO_FILE(@invoice_search_stage, s.RELATIVE_PATH),
        {'mode': 'LAYOUT'}
    ) as parsed_content,
    SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
        TO_FILE(@invoice_search_stage, s.RELATIVE_PATH),
        {'mode': 'LAYOUT'}
    ):content::VARCHAR as extracted_text,
    'SUCCESS' as processing_status
FROM invoice_search_stream s
WHERE s.RELATIVE_PATH ILIKE '%.pdf';

-- ============================================================================
-- STEP 6: CREATE CORTEX SEARCH SERVICE
-- ============================================================================

-- Create search service on parsed invoice data
CREATE OR REPLACE CORTEX SEARCH SERVICE invoice_search_service
ON extracted_text
ATTRIBUTES file_name, file_size, last_modified, parse_timestamp
WAREHOUSE = COMPUTE_WH
TARGET_LAG = '1 minute'
AS (
    SELECT 
        parsed_id,
        file_name,
        file_size,
        last_modified,
        parse_timestamp,
        extracted_text
    FROM parsed_invoices
    WHERE processing_status = 'SUCCESS'
);

-- ============================================================================
-- STEP 7: CREATE SEMANTIC VIEW
-- ============================================================================

-- Create semantic view joining invoice header and line items from aiextract project
CREATE OR REPLACE VIEW invoice_semantic_view
    COMMENT = 'Semantic view of invoice data for natural language queries'
AS
SELECT 
    i.invoice_id,
    i.extraction_id,
    i.invoice_number AS invoice_number,
    i.invoice_date AS invoice_date,
    i.due_date AS due_date,
    i.vendor_name AS vendor_name,
    i.vendor_address AS vendor_address,
    i.vendor_phone AS vendor_phone,
    i.vendor_email AS vendor_email,
    i.customer_name AS customer_name,
    i.customer_address AS customer_address,
    i.customer_phone AS customer_phone,
    i.customer_email AS customer_email,
    i.subtotal AS subtotal_amount,
    i.tax_amount AS tax_amount,
    i.total_amount AS total_amount,
    i.currency AS currency_code,
    i.payment_terms AS payment_terms,
    i.po_number AS purchase_order_number,
    d.invoice_detail_id,
    d.line_number AS line_item_number,
    d.item_description AS line_item_description,
    d.item_code AS product_sku,
    d.quantity AS line_item_quantity,
    d.unit_of_measure AS unit_measure,
    d.unit_price AS unit_price,
    d.line_amount AS line_item_amount,
    d.tax_amount AS line_item_tax
FROM invoice_processing_poc.invoice_pipeline.invoice i
LEFT JOIN invoice_processing_poc.invoice_pipeline.invoice_detail d 
    ON i.invoice_id = d.invoice_id;

-- Add semantic model metadata
ALTER VIEW invoice_semantic_view SET 
    SEMANTIC_MODEL = '{
        "table_description": "Invoice data including header information and detailed line items. Contains vendor details, customer information, financial totals, and itemized product/service lines.",
        "tables": [
            {
                "name": "invoice",
                "description": "Invoice header information including vendor, customer, dates, and financial totals",
                "columns": [
                    {
                        "name": "invoice_number",
                        "description": "Unique invoice identifier or invoice number",
                        "synonyms": ["invoice id", "invoice num", "bill number", "receipt number"]
                    },
                    {
                        "name": "invoice_date",
                        "description": "Date the invoice was issued",
                        "synonyms": ["issue date", "billing date", "date issued"]
                    },
                    {
                        "name": "due_date",
                        "description": "Payment due date",
                        "synonyms": ["payment due date", "deadline", "pay by date"]
                    },
                    {
                        "name": "vendor_name",
                        "description": "Name of the vendor or seller company",
                        "synonyms": ["seller", "supplier", "provider", "merchant", "from company"]
                    },
                    {
                        "name": "customer_name",
                        "description": "Name of the customer or buyer company",
                        "synonyms": ["buyer", "client", "purchaser", "bill to", "to company"]
                    },
                    {
                        "name": "subtotal_amount",
                        "description": "Subtotal amount before taxes",
                        "synonyms": ["subtotal", "amount before tax", "pre-tax amount"]
                    },
                    {
                        "name": "tax_amount",
                        "description": "Total tax amount charged",
                        "synonyms": ["tax", "sales tax", "vat"]
                    },
                    {
                        "name": "total_amount",
                        "description": "Final total amount including all charges",
                        "synonyms": ["total", "grand total", "amount due", "balance due"]
                    },
                    {
                        "name": "payment_terms",
                        "description": "Payment terms and conditions",
                        "synonyms": ["terms", "payment conditions", "net terms"]
                    },
                    {
                        "name": "purchase_order_number",
                        "description": "Associated purchase order number",
                        "synonyms": ["po number", "po #", "order number"]
                    }
                ]
            },
            {
                "name": "invoice_detail",
                "description": "Individual line items on the invoice showing products or services purchased",
                "columns": [
                    {
                        "name": "line_item_number",
                        "description": "Line item sequence number",
                        "synonyms": ["line number", "item number", "row number"]
                    },
                    {
                        "name": "line_item_description",
                        "description": "Description of the product or service",
                        "synonyms": ["item description", "product name", "service description"]
                    },
                    {
                        "name": "product_sku",
                        "description": "Product SKU or item code",
                        "synonyms": ["sku", "item code", "product code", "part number"]
                    },
                    {
                        "name": "line_item_quantity",
                        "description": "Quantity of items ordered",
                        "synonyms": ["quantity", "qty", "amount ordered"]
                    },
                    {
                        "name": "unit_price",
                        "description": "Price per unit",
                        "synonyms": ["price per unit", "unit cost", "price each"]
                    },
                    {
                        "name": "line_item_amount",
                        "description": "Total amount for this line item",
                        "synonyms": ["line total", "extended amount", "line amount"]
                    }
                ]
            }
        ],
        "joins": [
            {
                "type": "left",
                "left_table": "invoice",
                "right_table": "invoice_detail",
                "condition": "invoice.invoice_id = invoice_detail.invoice_id",
                "description": "Join invoice header with its line items"
            }
        ]
    }';

-- ============================================================================
-- STEP 8: CREATE CORTEX AGENT
-- ============================================================================

CREATE OR REPLACE CORTEX AGENT invoice_agent
    WAREHOUSE = COMPUTE_WH
    DESCRIPTION = 'Invoice Agent - Your intelligent assistant for invoice data queries and search. I can help you find invoices, analyze spending patterns, answer questions about vendors and customers, search invoice content, and provide insights from your invoice data.'
    ORCHESTRATION_INSTRUCTIONS = '
You are an intelligent invoice assistant with access to both structured invoice data and full-text search capabilities.

Your primary responsibilities:
1. Help users find specific invoices by number, vendor, customer, date, or amount
2. Search invoice content using the search service for text-based queries
3. Analyze spending patterns and trends across invoices
4. Answer questions about vendors, customers, and payment terms
5. Provide summaries and insights from invoice line items
6. Calculate totals, averages, and aggregations as requested

Guidelines:
- When users ask about finding or searching for text content, use the invoice_search_service
- When users need structured data queries (totals, specific fields, aggregations), use the invoice_semantic_view
- Always provide clear, concise answers with relevant invoice numbers and amounts
- When showing amounts, include the currency
- For date-based queries, be flexible with date formats
- If multiple invoices match a query, summarize the results and offer to show details
- Proactively suggest related insights when appropriate
- If data is not available, explain what information you have access to

Search Service Usage:
- Use invoice_search_service for: "find invoices containing...", "search for...", "show me invoices with text..."
- The search service has access to the full text content of parsed invoices

Semantic View Usage:
- Use invoice_semantic_view for: structured queries, aggregations, filtering by specific fields
- Available fields include invoice numbers, dates, vendor/customer names, amounts, line items, and more
- The view joins invoice headers with line items for comprehensive queries

Response Format:
- Be conversational but professional
- Use tables for multiple results
- Include invoice numbers as references
- Highlight key findings
- Offer follow-up suggestions when relevant
'
AS
BEGIN
    -- Add search service
    ADD SEARCH invoice_search_service;
    
    -- Add semantic view
    ADD VIEW invoice_semantic_view;
END;

-- ============================================================================
-- STEP 9: HELPER PROCEDURES AND VIEWS
-- ============================================================================

-- Procedure to manually refresh directory and process files
CREATE OR REPLACE PROCEDURE refresh_and_parse()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    -- Refresh the stage directory (updates the implicit directory table)
    ALTER STAGE invoice_search_stage REFRESH;
    
    -- Execute task manually (for testing)
    EXECUTE TASK task_parse_invoices;
    
    RETURN 'Processing initiated successfully';
END;
$$;

-- View to monitor pipeline status
CREATE OR REPLACE VIEW search_pipeline_monitoring AS
SELECT 
    parsed_id,
    file_name,
    file_size,
    parse_timestamp,
    processing_status,
    error_message,
    CASE 
        WHEN processing_status = 'SUCCESS' THEN '✓'
        ELSE '✗'
    END as status_icon
FROM parsed_invoices
ORDER BY parse_timestamp DESC;

-- View to get search service statistics
CREATE OR REPLACE VIEW search_service_stats AS
SELECT 
    COUNT(*) as total_documents_indexed,
    COUNT(DISTINCT file_name) as unique_files,
    MIN(parse_timestamp) as first_indexed,
    MAX(parse_timestamp) as last_indexed,
    AVG(file_size) as avg_file_size,
    SUM(file_size) as total_size_bytes
FROM parsed_invoices
WHERE processing_status = 'SUCCESS';

-- ============================================================================
-- STEP 10: RESUME TASKS (Execute after setup complete)
-- ============================================================================

-- Uncomment to start the pipeline:
-- ALTER TASK task_parse_invoices RESUME;

-- ============================================================================
-- TESTING QUERIES
-- ============================================================================

-- 1. Upload a file to the stage
-- PUT file:///path/to/docs/MB66680464.pdf @invoice_search_stage AUTO_COMPRESS=FALSE;

-- 2. Refresh directory and check
-- ALTER STAGE invoice_search_stage REFRESH;
-- SELECT * FROM DIRECTORY(@invoice_search_stage);

-- 3. Check stream for new files
-- SELECT * FROM invoice_search_stream;

-- 4. Manually execute parsing task
-- CALL refresh_and_parse();

-- 5. Check parsed results
-- SELECT * FROM parsed_invoices ORDER BY parse_timestamp DESC;

-- 6. View extracted text
-- SELECT file_name, extracted_text FROM parsed_invoices LIMIT 1;

-- 7. Test search service
-- SELECT * FROM TABLE(
--     invoice_search_service.SEARCH(
--         'invoice',
--         10
--     )
-- );

-- 8. Query semantic view
-- SELECT 
--     invoice_number,
--     vendor_name,
--     total_amount,
--     COUNT(line_item_number) as item_count
-- FROM invoice_semantic_view
-- GROUP BY invoice_number, vendor_name, total_amount
-- ORDER BY total_amount DESC;

-- 9. Test Cortex Agent
-- SELECT SNOWFLAKE.CORTEX.COMPLETE_AGENT(
--     'invoice_agent',
--     'Show me all invoices from last month'
-- );

-- 10. Monitor pipeline
-- SELECT * FROM search_pipeline_monitoring;

-- 11. View search service stats
-- SELECT * FROM search_service_stats;

-- ============================================================================
-- CLEANUP
-- ============================================================================

/*
-- To suspend task:
ALTER TASK task_parse_invoices SUSPEND;

-- To drop everything:
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
*/

