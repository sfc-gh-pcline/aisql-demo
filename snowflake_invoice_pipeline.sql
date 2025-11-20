-- ============================================================================
-- Snowflake AI Invoice Processing Pipeline POC
-- ============================================================================
-- This pipeline demonstrates using Snowflake AI_EXTRACT function to parse
-- PDF invoices into structured data using Streams and Tasks
-- ============================================================================

-- ============================================================================
-- STEP 1: SETUP DATABASE AND SCHEMA
-- ============================================================================

-- Create database and schema for the POC
CREATE DATABASE IF NOT EXISTS invoice_processing_poc;
USE DATABASE invoice_processing_poc;

CREATE SCHEMA IF NOT EXISTS invoice_pipeline;
USE SCHEMA invoice_pipeline;

-- ============================================================================
-- STEP 2: CREATE STAGE FOR PDF INVOICES
-- ============================================================================

-- Create internal stage for storing PDF invoice files
CREATE OR REPLACE STAGE invoice_stage
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for storing PDF invoice files';

-- Upload files to stage using:
-- PUT file:///path/to/docs/MB66680464.pdf @invoice_stage AUTO_COMPRESS=FALSE;

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

-- Refresh directory when files are uploaded
-- ALTER STAGE invoice_stage REFRESH;

-- ============================================================================
-- STEP 4: CREATE RAW_JSON TABLE
-- ============================================================================

-- Table to store raw JSON extraction results from AI_EXTRACT
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

-- ============================================================================
-- STEP 5: CREATE STREAM ON RAW_JSON TABLE
-- ============================================================================

-- Stream to capture new extractions that need to be parsed
CREATE OR REPLACE STREAM raw_json_stream 
ON TABLE raw_json
APPEND_ONLY = TRUE
COMMENT = 'Stream to track new JSON extractions for parsing';

-- ============================================================================
-- STEP 6: CREATE INVOICE AND INVOICE_DETAIL TABLES
-- ============================================================================

-- Main invoice header table
CREATE OR REPLACE TABLE invoice (
    invoice_id NUMBER AUTOINCREMENT PRIMARY KEY,
    extraction_id NUMBER NOT NULL,
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
    
    -- Foreign key reference
    FOREIGN KEY (extraction_id) REFERENCES raw_json(extraction_id)
);

-- Invoice line items detail table
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
    
    -- Foreign key reference
    FOREIGN KEY (invoice_id) REFERENCES invoice(invoice_id)
);

-- ============================================================================
-- STEP 7: CREATE TASK TO EXTRACT PDFs USING AI_EXTRACT
-- ============================================================================

-- Task 1: Extract PDF content to JSON using AI_EXTRACT
CREATE OR REPLACE TASK task_extract_invoices
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('invoice_stage_stream')
AS
DECLARE
    v_file_name VARCHAR;
    v_file_url VARCHAR;
    v_file_size NUMBER;
    v_last_modified TIMESTAMP_NTZ;
    v_extracted_json VARIANT;
    v_error_msg VARCHAR;
    
    -- Cursor to process files from stream
    c_files CURSOR FOR 
        SELECT RELATIVE_PATH as file_name,
               '@invoice_stage/' || RELATIVE_PATH as file_url,
               SIZE as file_size,
               LAST_MODIFIED
        FROM invoice_stage_stream
        WHERE RELATIVE_PATH ILIKE '%.pdf';
BEGIN
    -- Process each new file
    FOR record IN c_files DO
        v_file_name := record.file_name;
        v_file_url := record.file_url;
        v_file_size := record.file_size;
        v_last_modified := record.last_modified;
        
        BEGIN
            -- Execute AI_EXTRACT function to parse the PDF
            SELECT SNOWFLAKE.CORTEX.AI_EXTRACT(
                v_file_url,
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
            ) INTO v_extracted_json;
            
            -- Insert extracted JSON into raw_json table
            INSERT INTO raw_json (
                file_name,
                file_url,
                file_size,
                last_modified,
                extracted_json,
                processing_status
            )
            VALUES (
                v_file_name,
                v_file_url,
                v_file_size,
                v_last_modified,
                v_extracted_json,
                'SUCCESS'
            );
            
        EXCEPTION
            WHEN OTHER THEN
                v_error_msg := SQLERRM;
                
                -- Log the error in raw_json table
                INSERT INTO raw_json (
                    file_name,
                    file_url,
                    file_size,
                    last_modified,
                    extracted_json,
                    processing_status,
                    error_message
                )
                VALUES (
                    v_file_name,
                    v_file_url,
                    v_file_size,
                    v_last_modified,
                    OBJECT_CONSTRUCT('error', v_error_msg),
                    'ERROR',
                    v_error_msg
                );
        END;
    END FOR;
END;

-- ============================================================================
-- STEP 8: CREATE TASK TO PARSE JSON INTO INVOICE TABLES
-- ============================================================================

-- Task 2: Parse JSON from raw_json into invoice and invoice_detail tables
CREATE OR REPLACE TASK task_parse_json_to_tables
    WAREHOUSE = COMPUTE_WH
    AFTER task_extract_invoices
    WHEN SYSTEM$STREAM_HAS_DATA('raw_json_stream')
AS
DECLARE
    v_extraction_id NUMBER;
    v_json VARIANT;
    v_invoice_id NUMBER;
    
    -- Cursor to process new JSON extractions
    c_extractions CURSOR FOR 
        SELECT extraction_id, extracted_json
        FROM raw_json_stream
        WHERE processing_status = 'SUCCESS';
BEGIN
    -- Process each new extraction
    FOR record IN c_extractions DO
        v_extraction_id := record.extraction_id;
        v_json := record.extracted_json;
        
        BEGIN
            -- Insert into invoice table (header)
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
                v_extraction_id,
                v_json:invoice_number::VARCHAR,
                TRY_TO_DATE(v_json:invoice_date::VARCHAR),
                TRY_TO_DATE(v_json:due_date::VARCHAR),
                v_json:vendor.name::VARCHAR,
                v_json:vendor.address::VARCHAR,
                v_json:vendor.city::VARCHAR,
                v_json:vendor.state::VARCHAR,
                v_json:vendor.zip::VARCHAR,
                v_json:vendor.country::VARCHAR,
                v_json:vendor.phone::VARCHAR,
                v_json:vendor.email::VARCHAR,
                v_json:vendor.tax_id::VARCHAR,
                v_json:customer.name::VARCHAR,
                v_json:customer.address::VARCHAR,
                v_json:customer.city::VARCHAR,
                v_json:customer.state::VARCHAR,
                v_json:customer.zip::VARCHAR,
                v_json:customer.country::VARCHAR,
                v_json:customer.phone::VARCHAR,
                v_json:customer.email::VARCHAR,
                TRY_TO_DECIMAL(v_json:financial.subtotal, 18, 2),
                TRY_TO_DECIMAL(v_json:financial.tax_amount, 18, 2),
                TRY_TO_DECIMAL(v_json:financial.tax_rate, 5, 2),
                TRY_TO_DECIMAL(v_json:financial.shipping_amount, 18, 2),
                TRY_TO_DECIMAL(v_json:financial.discount_amount, 18, 2),
                TRY_TO_DECIMAL(v_json:financial.total_amount, 18, 2),
                COALESCE(v_json:financial.currency::VARCHAR, 'USD'),
                v_json:payment_terms::VARCHAR,
                v_json:po_number::VARCHAR,
                v_json:notes::VARCHAR;
            
            -- Get the invoice_id that was just inserted
            v_invoice_id := (SELECT MAX(invoice_id) FROM invoice WHERE extraction_id = v_extraction_id);
            
            -- Insert line items into invoice_detail table
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
                v_invoice_id,
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
            FROM TABLE(FLATTEN(v_json:line_items)) line_item;
            
        EXCEPTION
            WHEN OTHER THEN
                -- Log error (you might want to create an error logging table)
                RAISE;
        END;
    END FOR;
END;

-- ============================================================================
-- STEP 9: ENABLE TASK EXECUTION
-- ============================================================================

-- Resume tasks (they start in suspended state)
-- Note: Tasks must be resumed in reverse dependency order
-- ALTER TASK task_parse_json_to_tables RESUME;
-- ALTER TASK task_extract_invoices RESUME;

-- ============================================================================
-- STEP 10: MONITORING AND UTILITY QUERIES
-- ============================================================================

-- View to monitor pipeline status
CREATE OR REPLACE VIEW pipeline_monitoring AS
SELECT 
    r.extraction_id,
    r.file_name,
    r.extraction_timestamp,
    r.processing_status,
    r.error_message,
    i.invoice_id,
    i.invoice_number,
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
    i.total_amount,
    i.currency
ORDER BY r.extraction_timestamp DESC;

-- View to see invoice summary
CREATE OR REPLACE VIEW invoice_summary AS
SELECT 
    i.invoice_id,
    i.invoice_number,
    i.invoice_date,
    i.vendor_name,
    i.customer_name,
    i.subtotal,
    i.tax_amount,
    i.shipping_amount,
    i.total_amount,
    i.currency,
    COUNT(d.invoice_detail_id) as total_line_items,
    SUM(d.line_amount) as line_items_total
FROM invoice i
LEFT JOIN invoice_detail d ON i.invoice_id = d.invoice_id
GROUP BY 
    i.invoice_id,
    i.invoice_number,
    i.invoice_date,
    i.vendor_name,
    i.customer_name,
    i.subtotal,
    i.tax_amount,
    i.shipping_amount,
    i.total_amount,
    i.currency;

-- ============================================================================
-- USEFUL QUERIES FOR TESTING AND MONITORING
-- ============================================================================

-- Check files in stage
-- SELECT * FROM DIRECTORY(@invoice_stage);

-- Check stream for new files
-- SELECT * FROM invoice_stage_stream;

-- Check raw JSON extractions
-- SELECT extraction_id, file_name, extraction_timestamp, processing_status 
-- FROM raw_json 
-- ORDER BY extraction_timestamp DESC;

-- Check stream for new JSON
-- SELECT * FROM raw_json_stream;

-- View parsed invoices
-- SELECT * FROM invoice_summary;

-- View invoice details with line items
-- SELECT 
--     i.invoice_number,
--     i.vendor_name,
--     i.invoice_date,
--     d.line_number,
--     d.item_description,
--     d.quantity,
--     d.unit_price,
--     d.line_amount
-- FROM invoice i
-- JOIN invoice_detail d ON i.invoice_id = d.invoice_id
-- ORDER BY i.invoice_number, d.line_number;

-- Monitor task execution history
-- SELECT 
--     name,
--     state,
--     scheduled_time,
--     completed_time,
--     return_value
-- FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
-- WHERE name IN ('TASK_EXTRACT_INVOICES', 'TASK_PARSE_JSON_TO_TABLES')
-- ORDER BY scheduled_time DESC
-- LIMIT 100;

-- ============================================================================
-- CLEANUP (if needed)
-- ============================================================================

-- To stop the pipeline:
-- ALTER TASK task_extract_invoices SUSPEND;
-- ALTER TASK task_parse_json_to_tables SUSPEND;

-- To drop everything:
-- DROP TASK IF EXISTS task_parse_json_to_tables;
-- DROP TASK IF EXISTS task_extract_invoices;
-- DROP STREAM IF EXISTS raw_json_stream;
-- DROP STREAM IF EXISTS invoice_stage_stream;
-- DROP TABLE IF EXISTS invoice_detail;
-- DROP TABLE IF EXISTS invoice;
-- DROP TABLE IF EXISTS raw_json;
-- DROP STAGE IF EXISTS invoice_stage;
-- DROP VIEW IF EXISTS pipeline_monitoring;
-- DROP VIEW IF EXISTS invoice_summary;
-- DROP SCHEMA IF EXISTS invoice_pipeline;
-- DROP DATABASE IF EXISTS invoice_processing_poc;

