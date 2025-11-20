-- ============================================================================
-- Snowflake AI Invoice Processing Pipeline POC - Version 2
-- Using Snowflake's CORTEX.AI_EXTRACT Function
-- ============================================================================

-- ============================================================================
-- STEP 1: SETUP DATABASE AND SCHEMA
-- ============================================================================

CREATE DATABASE IF NOT EXISTS invoice_processing_poc;
USE DATABASE invoice_processing_poc;

CREATE SCHEMA IF NOT EXISTS invoice_pipeline;
USE SCHEMA invoice_pipeline;

-- ============================================================================
-- STEP 2: CREATE STAGE FOR PDF INVOICES
-- ============================================================================

CREATE OR REPLACE STAGE invoice_stage
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for storing PDF invoice files';

-- ============================================================================
-- STEP 3: CREATE STREAM ON STAGE DIRECTORY
-- ============================================================================

-- Stream to capture new files added to the stage
-- Note: The stage already has an implicit directory table (DIRECTORY = ENABLE = TRUE)
-- We can create a stream directly on the stage to monitor file changes
CREATE OR REPLACE STREAM invoice_stage_stream 
ON STAGE invoice_stage
APPEND_ONLY = TRUE
COMMENT = 'Stream to track new PDF files in invoice stage';

-- ============================================================================
-- STEP 4: CREATE RAW_JSON TABLE AND STREAM
-- ============================================================================

CREATE OR REPLACE TABLE raw_json (
    extraction_id NUMBER AUTOINCREMENT PRIMARY KEY,
    file_name VARCHAR(500) NOT NULL,
    file_url VARCHAR(1000) NOT NULL,
    file_size NUMBER,
    last_modified TIMESTAMP_NTZ,
    extracted_json VARIANT NOT NULL,
    extraction_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    processing_status VARCHAR(50) DEFAULT 'SUCCESS',
    error_message VARCHAR(5000)
);

CREATE OR REPLACE STREAM raw_json_stream 
ON TABLE raw_json
APPEND_ONLY = TRUE
COMMENT = 'Stream to track new JSON extractions for parsing';

-- ============================================================================
-- STEP 5: CREATE INVOICE AND INVOICE_DETAIL TABLES
-- ============================================================================

CREATE OR REPLACE TABLE invoice (
    invoice_id NUMBER AUTOINCREMENT PRIMARY KEY,
    extraction_id NUMBER NOT NULL,
    
    -- Invoice Header
    invoice_number VARCHAR(100),
    invoice_date DATE,
    due_date DATE,
    
    -- Vendor/Seller Information
    vendor_name VARCHAR(500),
    vendor_address VARCHAR(1000),
    vendor_city VARCHAR(100),
    vendor_state VARCHAR(50),
    vendor_zip VARCHAR(20),
    vendor_country VARCHAR(100),
    vendor_phone VARCHAR(50),
    vendor_email VARCHAR(100),
    vendor_tax_id VARCHAR(100),
    
    -- Customer/Buyer Information
    customer_name VARCHAR(500),
    customer_address VARCHAR(1000),
    customer_city VARCHAR(100),
    customer_state VARCHAR(50),
    customer_zip VARCHAR(20),
    customer_country VARCHAR(100),
    customer_phone VARCHAR(50),
    customer_email VARCHAR(100),
    
    -- Financial Information
    subtotal DECIMAL(18,2),
    tax_amount DECIMAL(18,2),
    tax_rate DECIMAL(5,2),
    shipping_amount DECIMAL(18,2),
    discount_amount DECIMAL(18,2),
    total_amount DECIMAL(18,2),
    
    -- Additional Fields
    currency VARCHAR(10),
    payment_terms VARCHAR(200),
    po_number VARCHAR(100),
    notes VARCHAR(5000),
    
    -- Metadata
    created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    FOREIGN KEY (extraction_id) REFERENCES raw_json(extraction_id)
);

CREATE OR REPLACE TABLE invoice_detail (
    invoice_detail_id NUMBER AUTOINCREMENT PRIMARY KEY,
    invoice_id NUMBER NOT NULL,
    line_number NUMBER,
    
    -- Line Item Information
    item_description VARCHAR(1000),
    item_code VARCHAR(100),
    quantity DECIMAL(18,4),
    unit_of_measure VARCHAR(50),
    unit_price DECIMAL(18,4),
    line_amount DECIMAL(18,2),
    discount_percent DECIMAL(5,2),
    discount_amount DECIMAL(18,2),
    tax_amount DECIMAL(18,2),
    
    -- Additional Fields
    category VARCHAR(200),
    notes VARCHAR(1000),
    
    -- Metadata
    created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    FOREIGN KEY (invoice_id) REFERENCES invoice(invoice_id)
);

-- ============================================================================
-- STEP 6: CREATE TASK TO EXTRACT PDFs USING AI_EXTRACT
-- ============================================================================

CREATE OR REPLACE TASK task_extract_invoices
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('invoice_stage_stream')
AS
INSERT INTO raw_json (
    file_name,
    file_url,
    file_size,
    last_modified,
    extracted_json,
    processing_status
)
SELECT 
    s.RELATIVE_PATH as file_name,
    BUILD_SCOPED_FILE_URL(@invoice_stage, s.RELATIVE_PATH) as file_url,
    s.SIZE as file_size,
    s.LAST_MODIFIED,
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        BUILD_SCOPED_FILE_URL(@invoice_stage, s.RELATIVE_PATH),
        {
            'invoice_number': 'Invoice number',
            'invoice_date': 'Invoice date in YYYY-MM-DD format',
            'due_date': 'Payment due date in YYYY-MM-DD format',
            'vendor': {
                'name': 'Vendor or seller company name',
                'address': 'Vendor street address',
                'city': 'Vendor city',
                'state': 'Vendor state or province',
                'zip': 'Vendor postal code',
                'country': 'Vendor country',
                'phone': 'Vendor phone number',
                'email': 'Vendor email address',
                'tax_id': 'Vendor tax ID or EIN'
            },
            'customer': {
                'name': 'Customer or buyer company name',
                'address': 'Customer street address',
                'city': 'Customer city',
                'state': 'Customer state or province',
                'zip': 'Customer postal code',
                'country': 'Customer country',
                'phone': 'Customer phone number',
                'email': 'Customer email address'
            },
            'financial': {
                'subtotal': 'Subtotal amount before tax',
                'tax_amount': 'Total tax amount',
                'tax_rate': 'Tax rate percentage',
                'shipping_amount': 'Shipping or freight charges',
                'discount_amount': 'Total discount amount',
                'total_amount': 'Final total amount',
                'currency': 'Currency code (e.g., USD, EUR)'
            },
            'payment_terms': 'Payment terms (e.g., Net 30, Due on Receipt)',
            'po_number': 'Purchase order number',
            'notes': 'Additional notes or comments on the invoice',
            'line_items': [
                {
                    'line_number': 'Line item number',
                    'description': 'Item or service description',
                    'item_code': 'Item code, SKU, or product ID',
                    'quantity': 'Quantity ordered',
                    'unit_of_measure': 'Unit of measure (e.g., EA, HR, BOX)',
                    'unit_price': 'Price per unit',
                    'line_amount': 'Total line amount (quantity × unit price)',
                    'discount_percent': 'Discount percentage for this line',
                    'discount_amount': 'Discount amount for this line',
                    'tax_amount': 'Tax amount for this line',
                    'category': 'Item category or type',
                    'notes': 'Additional line item notes'
                }
            ]
        }
    ) as extracted_json,
    'SUCCESS' as processing_status
FROM invoice_stage_stream s
WHERE s.RELATIVE_PATH ILIKE '%.pdf';

-- ============================================================================
-- STEP 7: CREATE TASK TO PARSE JSON INTO INVOICE TABLES
-- ============================================================================

CREATE OR REPLACE TASK task_parse_json_to_tables
    WAREHOUSE = COMPUTE_WH
    AFTER task_extract_invoices
    WHEN SYSTEM$STREAM_HAS_DATA('raw_json_stream')
AS
BEGIN
    -- Insert invoice headers
    INSERT INTO invoice (
        extraction_id,
        invoice_number,
        invoice_date,
        due_date,
        vendor_name,
        vendor_address,
        vendor_city,
        vendor_state,
        vendor_zip,
        vendor_country,
        vendor_phone,
        vendor_email,
        vendor_tax_id,
        customer_name,
        customer_address,
        customer_city,
        customer_state,
        customer_zip,
        customer_country,
        customer_phone,
        customer_email,
        subtotal,
        tax_amount,
        tax_rate,
        shipping_amount,
        discount_amount,
        total_amount,
        currency,
        payment_terms,
        po_number,
        notes
    )
    SELECT
        s.extraction_id,
        s.extracted_json:invoice_number::VARCHAR,
        TRY_TO_DATE(s.extracted_json:invoice_date::VARCHAR),
        TRY_TO_DATE(s.extracted_json:due_date::VARCHAR),
        s.extracted_json:vendor.name::VARCHAR,
        s.extracted_json:vendor.address::VARCHAR,
        s.extracted_json:vendor.city::VARCHAR,
        s.extracted_json:vendor.state::VARCHAR,
        s.extracted_json:vendor.zip::VARCHAR,
        s.extracted_json:vendor.country::VARCHAR,
        s.extracted_json:vendor.phone::VARCHAR,
        s.extracted_json:vendor.email::VARCHAR,
        s.extracted_json:vendor.tax_id::VARCHAR,
        s.extracted_json:customer.name::VARCHAR,
        s.extracted_json:customer.address::VARCHAR,
        s.extracted_json:customer.city::VARCHAR,
        s.extracted_json:customer.state::VARCHAR,
        s.extracted_json:customer.zip::VARCHAR,
        s.extracted_json:customer.country::VARCHAR,
        s.extracted_json:customer.phone::VARCHAR,
        s.extracted_json:customer.email::VARCHAR,
        TRY_TO_DECIMAL(s.extracted_json:financial.subtotal, 18, 2),
        TRY_TO_DECIMAL(s.extracted_json:financial.tax_amount, 18, 2),
        TRY_TO_DECIMAL(s.extracted_json:financial.tax_rate, 5, 2),
        TRY_TO_DECIMAL(s.extracted_json:financial.shipping_amount, 18, 2),
        TRY_TO_DECIMAL(s.extracted_json:financial.discount_amount, 18, 2),
        TRY_TO_DECIMAL(s.extracted_json:financial.total_amount, 18, 2),
        COALESCE(s.extracted_json:financial.currency::VARCHAR, 'USD'),
        s.extracted_json:payment_terms::VARCHAR,
        s.extracted_json:po_number::VARCHAR,
        s.extracted_json:notes::VARCHAR
    FROM raw_json_stream s
    WHERE s.processing_status = 'SUCCESS';
    
    -- Insert invoice line items
    INSERT INTO invoice_detail (
        invoice_id,
        line_number,
        item_description,
        item_code,
        quantity,
        unit_of_measure,
        unit_price,
        line_amount,
        discount_percent,
        discount_amount,
        tax_amount,
        category,
        notes
    )
    SELECT
        i.invoice_id,
        line_item.value:line_number::NUMBER,
        line_item.value:description::VARCHAR,
        line_item.value:item_code::VARCHAR,
        TRY_TO_DECIMAL(line_item.value:quantity, 18, 4),
        line_item.value:unit_of_measure::VARCHAR,
        TRY_TO_DECIMAL(line_item.value:unit_price, 18, 4),
        TRY_TO_DECIMAL(line_item.value:line_amount, 18, 2),
        TRY_TO_DECIMAL(line_item.value:discount_percent, 5, 2),
        TRY_TO_DECIMAL(line_item.value:discount_amount, 18, 2),
        TRY_TO_DECIMAL(line_item.value:tax_amount, 18, 2),
        line_item.value:category::VARCHAR,
        line_item.value:notes::VARCHAR
    FROM raw_json_stream s
    JOIN invoice i ON s.extraction_id = i.extraction_id
    CROSS JOIN TABLE(FLATTEN(s.extracted_json:line_items)) line_item
    WHERE s.processing_status = 'SUCCESS';
END;

-- ============================================================================
-- STEP 8: CREATE MONITORING VIEWS
-- ============================================================================

CREATE OR REPLACE VIEW pipeline_monitoring AS
SELECT 
    r.extraction_id,
    r.file_name,
    r.extraction_timestamp,
    r.processing_status,
    r.error_message,
    i.invoice_id,
    i.invoice_number,
    i.vendor_name,
    i.customer_name,
    i.invoice_date,
    i.total_amount,
    i.currency,
    COUNT(d.invoice_detail_id) as line_item_count
FROM raw_json r
LEFT JOIN invoice i ON r.extraction_id = i.extraction_id
LEFT JOIN invoice_detail d ON i.invoice_id = d.invoice_id
GROUP BY 
    r.extraction_id,
    r.file_name,
    r.extraction_timestamp,
    r.processing_status,
    r.error_message,
    i.invoice_id,
    i.invoice_number,
    i.vendor_name,
    i.customer_name,
    i.invoice_date,
    i.total_amount,
    i.currency
ORDER BY r.extraction_timestamp DESC;

CREATE OR REPLACE VIEW invoice_summary AS
SELECT 
    i.invoice_id,
    i.invoice_number,
    i.invoice_date,
    i.due_date,
    i.vendor_name,
    i.customer_name,
    i.subtotal,
    i.tax_amount,
    i.shipping_amount,
    i.total_amount,
    i.currency,
    i.payment_terms,
    COUNT(d.invoice_detail_id) as total_line_items,
    SUM(d.line_amount) as line_items_total,
    i.created_timestamp
FROM invoice i
LEFT JOIN invoice_detail d ON i.invoice_id = d.invoice_id
GROUP BY 
    i.invoice_id,
    i.invoice_number,
    i.invoice_date,
    i.due_date,
    i.vendor_name,
    i.customer_name,
    i.subtotal,
    i.tax_amount,
    i.shipping_amount,
    i.total_amount,
    i.currency,
    i.payment_terms,
    i.created_timestamp;

CREATE OR REPLACE VIEW invoice_detail_view AS
SELECT 
    i.invoice_number,
    i.invoice_date,
    i.vendor_name,
    i.customer_name,
    i.total_amount as invoice_total,
    d.line_number,
    d.item_description,
    d.item_code,
    d.quantity,
    d.unit_of_measure,
    d.unit_price,
    d.line_amount,
    d.category
FROM invoice i
JOIN invoice_detail d ON i.invoice_id = d.invoice_id
ORDER BY i.invoice_number, d.line_number;

-- ============================================================================
-- STEP 9: HELPER PROCEDURES
-- ============================================================================

-- Procedure to manually refresh directory and process files
CREATE OR REPLACE PROCEDURE refresh_and_process()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    -- Refresh the stage directory (updates the implicit directory table)
    ALTER STAGE invoice_stage REFRESH;
    
    -- Execute tasks manually (for testing)
    EXECUTE TASK task_extract_invoices;
    EXECUTE TASK task_parse_json_to_tables;
    
    RETURN 'Processing initiated successfully';
END;
$$;

-- Procedure to get pipeline statistics
CREATE OR REPLACE PROCEDURE get_pipeline_stats()
RETURNS TABLE (metric VARCHAR, value NUMBER)
LANGUAGE SQL
AS
$$
BEGIN
    LET result RESULTSET := (
        SELECT 'Total Files Processed' as metric, COUNT(*) as value FROM raw_json
        UNION ALL
        SELECT 'Successful Extractions', COUNT(*) FROM raw_json WHERE processing_status = 'SUCCESS'
        UNION ALL
        SELECT 'Failed Extractions', COUNT(*) FROM raw_json WHERE processing_status = 'ERROR'
        UNION ALL
        SELECT 'Total Invoices', COUNT(*) FROM invoice
        UNION ALL
        SELECT 'Total Line Items', COUNT(*) FROM invoice_detail
        UNION ALL
        SELECT 'Total Invoice Amount', COALESCE(SUM(total_amount), 0) FROM invoice
    );
    RETURN TABLE(result);
END;
$$;

-- ============================================================================
-- STEP 10: RESUME TASKS (Execute after setup complete)
-- ============================================================================

-- Uncomment these lines to start the pipeline:
-- ALTER TASK task_parse_json_to_tables RESUME;
-- ALTER TASK task_extract_invoices RESUME;

-- ============================================================================
-- TESTING QUERIES
-- ============================================================================

-- 1. Upload a file to the stage
-- PUT file:///path/to/docs/MB66680464.pdf @invoice_stage AUTO_COMPRESS=FALSE;

-- 2. Refresh directory and check
-- ALTER STAGE invoice_stage REFRESH;
-- SELECT * FROM DIRECTORY(@invoice_stage);

-- 3. Check stream for new files
-- SELECT * FROM invoice_stage_stream;

-- 5. Manually execute extraction task
-- EXECUTE TASK task_extract_invoices;

-- 6. Check raw JSON results
-- SELECT * FROM raw_json ORDER BY extraction_timestamp DESC;

-- 7. View extracted JSON (pretty print)
-- SELECT 
--     file_name,
--     extraction_timestamp,
--     TO_JSON(extracted_json) as json_data
-- FROM raw_json 
-- ORDER BY extraction_timestamp DESC;

-- 8. Check raw_json stream
-- SELECT * FROM raw_json_stream;

-- 9. Manually execute parsing task
-- EXECUTE TASK task_parse_json_to_tables;

-- 10. View pipeline monitoring
-- SELECT * FROM pipeline_monitoring;

-- 11. View invoice summary
-- SELECT * FROM invoice_summary;

-- 12. View invoice details
-- SELECT * FROM invoice_detail_view;

-- 13. Get pipeline statistics
-- CALL get_pipeline_stats();

-- 14. Check task execution history
-- SELECT 
--     name,
--     state,
--     scheduled_time,
--     completed_time,
--     return_value,
--     error_code,
--     error_message
-- FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
-- WHERE name IN ('TASK_EXTRACT_INVOICES', 'TASK_PARSE_JSON_TO_TABLES')
-- ORDER BY scheduled_time DESC
-- LIMIT 20;

-- ============================================================================
-- CLEANUP
-- ============================================================================

/*
-- To suspend tasks:
ALTER TASK task_extract_invoices SUSPEND;
ALTER TASK task_parse_json_to_tables SUSPEND;

-- To drop everything:
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
*/

