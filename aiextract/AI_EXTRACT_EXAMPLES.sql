-- ============================================================================
-- SNOWFLAKE.CORTEX.AI_EXTRACT Function Examples
-- ============================================================================
-- This file demonstrates how to use AI_EXTRACT for invoice processing
-- ============================================================================

USE DATABASE invoice_processing_poc;
USE SCHEMA invoice_pipeline;

-- ============================================================================
-- EXAMPLE 1: Basic AI_EXTRACT Usage
-- ============================================================================

-- Extract just the invoice number and total amount
SELECT 
    RELATIVE_PATH as filename,
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        file => TO_FILE(@invoice_stage, RELATIVE_PATH),
        responseFormat => {
            'schema': {
                'type': 'object',
                'properties': {
                    'invoice_number': 'Invoice number or invoice ID',
                    'total_amount': 'Total amount to be paid'
                }
            }
        }
    ) as extracted_data
FROM DIRECTORY(@invoice_stage)
WHERE RELATIVE_PATH ILIKE '%.pdf'
LIMIT 1;

-- ============================================================================
-- EXAMPLE 2: Extract Vendor Information
-- ============================================================================

SELECT 
    RELATIVE_PATH as filename,
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        TO_FILE(@invoice_stage, RELATIVE_PATH),
        {
            'vendor_name': 'Name of the company or person issuing the invoice',
            'vendor_address': 'Full mailing address of the vendor',
            'vendor_phone': 'Contact phone number',
            'vendor_email': 'Contact email address'
        }
    ) as vendor_info
FROM DIRECTORY(@invoice_stage)
WHERE RELATIVE_PATH ILIKE '%.pdf'
LIMIT 1;

-- ============================================================================
-- EXAMPLE 3: Extract Financial Details
-- ============================================================================

SELECT 
    RELATIVE_PATH as filename,
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        TO_FILE(@invoice_stage, RELATIVE_PATH),
        {
            'subtotal': 'Subtotal before tax and shipping',
            'tax_amount': 'Total tax charged',
            'tax_rate': 'Tax rate as a percentage',
            'shipping': 'Shipping or delivery charges',
            'total': 'Final total amount including all charges',
            'currency': 'Currency code such as USD, EUR, GBP'
        }
    ) as financial_details
FROM DIRECTORY(@invoice_stage)
WHERE RELATIVE_PATH ILIKE '%.pdf'
LIMIT 1;

-- ============================================================================
-- EXAMPLE 4: Extract Dates
-- ============================================================================

SELECT 
    RELATIVE_PATH as filename,
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        TO_FILE(@invoice_stage, RELATIVE_PATH),
        {
            'invoice_date': 'Date the invoice was issued, in YYYY-MM-DD format',
            'due_date': 'Payment due date, in YYYY-MM-DD format',
            'service_period_start': 'Start date of service period if applicable',
            'service_period_end': 'End date of service period if applicable'
        }
    ) as date_info
FROM DIRECTORY(@invoice_stage)
WHERE RELATIVE_PATH ILIKE '%.pdf'
LIMIT 1;

-- ============================================================================
-- EXAMPLE 5: Extract Line Items (Array)
-- ============================================================================

SELECT 
    RELATIVE_PATH as filename,
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        TO_FILE(@invoice_stage, RELATIVE_PATH),
        {
            'line_items': [
                {
                    'description': 'Description of the product or service',
                    'quantity': 'Quantity purchased',
                    'unit_price': 'Price per unit',
                    'total': 'Total for this line item'
                }
            ]
        }
    ) as line_items
FROM DIRECTORY(@invoice_stage)
WHERE RELATIVE_PATH ILIKE '%.pdf'
LIMIT 1;

-- ============================================================================
-- EXAMPLE 6: Complete Invoice Extraction (Full Schema)
-- ============================================================================

SELECT 
    RELATIVE_PATH as filename,
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        file => TO_FILE(@invoice_stage, RELATIVE_PATH),
        responseFormat => {
            'schema': {
                'type': 'object',
                'properties': {
                    'invoice_number': 'Invoice number',
                    'order_number': 'Order number',
                    'invoice_date': 'Invoice date in YYYY-MM-DD format',
                    'due_date': 'Payment due date in YYYY-MM-DD format',
                    'vendor': 'Vendor or seller company name',
                    'vendor_address': 'Complete vendor address',
                    'vendor_phone': 'Vendor phone number',
                    'vendor_email': 'Vendor email address',
                    'vendor_tax_id': 'Vendor tax ID or EIN',
                    'customer': 'Customer or buyer company name',
                    'customer_address': 'Complete customer address',
                    'customer_phone': 'Customer phone number',
                    'customer_email': 'Customer email address',
                    'subtotal': 'Subtotal amount before tax',
                    'tax_amount': 'Total tax amount',
                    'tax_rate': 'Tax rate percentage',
                    'shipping_amount': 'Shipping or freight charges',
                    'discount_amount': 'Total discount amount',
                    'total_amount': 'Final total amount',
                    'currency': 'Currency code (e.g., USD, EUR)',
                    'payment_terms': 'Payment terms (e.g., Net 30, Due on Receipt)',
                    'po_number': 'Purchase order number',
                    'notes': 'Additional notes or comments on the invoice',
                    'line_items': {
                        'description': 'Invoice line item details',
                        'type': 'object',
                        'properties': {
                            'line_number': {
                                'description': 'Line item number',
                                'type': 'array'
                            },
                            'line_description': {
                                'description': 'Item or service description',
                                'type': 'array'
                            },
                            'item_code': {
                                'description': 'Item code, SKU, or product ID',
                                'type': 'array'
                            },
                            'quantity': {
                                'description': 'Quantity ordered',
                                'type': 'array'
                            },
                            'unit_of_measure': {
                                'description': 'Unit of measure (e.g., EA, HR, BOX)',
                                'type': 'array'
                            },
                            'unit_price': {
                                'description': 'Price per unit',
                                'type': 'array'
                            },
                            'line_amount': {
                                'description': 'Total line amount (quantity × unit price)',
                                'type': 'array'
                            },
                            'tax_amount': {
                                'description': 'Tax amount for this line',
                                'type': 'array'
                            },
                            'line_note': {
                                'description': 'Custom notes entry for each line item',
                                'type': 'array'
                            }
                        }
                    }
                }
            }
        }
    ) as complete_invoice
FROM DIRECTORY(@invoice_stage)
WHERE RELATIVE_PATH ILIKE '%.pdf'
LIMIT 1;

-- ============================================================================
-- EXAMPLE 7: Parse and Flatten Extracted Data
-- ============================================================================

-- Extract the data and immediately parse it into columns
WITH extracted AS (
    SELECT 
        RELATIVE_PATH as filename,
        SNOWFLAKE.CORTEX.AI_EXTRACT(
            TO_FILE(@invoice_stage, RELATIVE_PATH),
            {
                'invoice_number': 'Invoice number',
                'invoice_date': 'Invoice date',
                'vendor_name': 'Vendor company name',
                'total_amount': 'Total amount'
            }
        ) as invoice_data
    FROM DIRECTORY(@invoice_stage)
    WHERE RELATIVE_PATH ILIKE '%.pdf'
    LIMIT 1
)
SELECT 
    filename,
    invoice_data:invoice_number::VARCHAR as invoice_number,
    TRY_TO_DATE(invoice_data:invoice_date::VARCHAR) as invoice_date,
    invoice_data:vendor_name::VARCHAR as vendor_name,
    TRY_TO_NUMBER(invoice_data:total_amount) as total_amount
FROM extracted;

-- ============================================================================
-- EXAMPLE 8: Extract and Flatten Line Items
-- ============================================================================

WITH extracted AS (
    SELECT 
        RELATIVE_PATH as filename,
        SNOWFLAKE.CORTEX.AI_EXTRACT(
            TO_FILE(@invoice_stage, RELATIVE_PATH),
            {
                'invoice_number': 'Invoice number',
                'line_items': [
                    {
                        'description': 'Item description',
                        'quantity': 'Quantity',
                        'unit_price': 'Unit price',
                        'line_amount': 'Line total'
                    }
                ]
            }
        ) as invoice_data
    FROM DIRECTORY(@invoice_stage)
    WHERE RELATIVE_PATH ILIKE '%.pdf'
    LIMIT 1
)
SELECT 
    filename,
    invoice_data:invoice_number::VARCHAR as invoice_number,
    line_item.value:description::VARCHAR as item_description,
    TRY_TO_NUMBER(line_item.value:quantity) as quantity,
    TRY_TO_NUMBER(line_item.value:unit_price) as unit_price,
    TRY_TO_NUMBER(line_item.value:line_amount) as line_amount
FROM extracted,
LATERAL FLATTEN(input => invoice_data:line_items) line_item;

-- ============================================================================
-- EXAMPLE 9: Handling Errors with TRY_CAST
-- ============================================================================

-- Safely handle extraction errors
SELECT 
    RELATIVE_PATH as filename,
    TRY_CAST(
        SNOWFLAKE.CORTEX.AI_EXTRACT(
            TO_FILE(@invoice_stage, RELATIVE_PATH),
            {'invoice_number': 'Invoice number'}
        ) AS VARIANT
    ) as extracted_data,
    CASE 
        WHEN TRY_CAST(
            SNOWFLAKE.CORTEX.AI_EXTRACT(
                TO_FILE(@invoice_stage, RELATIVE_PATH),
                {'invoice_number': 'Invoice number'}
            ) AS VARIANT
        ) IS NULL THEN 'Extraction failed'
        ELSE 'Success'
    END as extraction_status
FROM DIRECTORY(@invoice_stage)
WHERE RELATIVE_PATH ILIKE '%.pdf'
LIMIT 1;

-- ============================================================================
-- EXAMPLE 10: Compare Multiple Extraction Approaches
-- ============================================================================

-- Simple extraction (minimal schema)
SELECT 
    'Simple' as approach,
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        TO_FILE(@invoice_stage, RELATIVE_PATH),
        {
            'invoice_number': 'Invoice number',
            'total': 'Total'
        }
    ) as result
FROM DIRECTORY(@invoice_stage)
WHERE RELATIVE_PATH ILIKE '%.pdf'
LIMIT 1

UNION ALL

-- Detailed extraction (descriptive schema)
SELECT 
    'Detailed' as approach,
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        TO_FILE(@invoice_stage, RELATIVE_PATH),
        {
            'invoice_number': 'Invoice number, typically a unique identifier in the format INV-XXXXX or similar',
            'total': 'Total amount to be paid, including tax and all other charges, usually found at the bottom of the invoice'
        }
    ) as result
FROM DIRECTORY(@invoice_stage)
WHERE RELATIVE_PATH ILIKE '%.pdf'
LIMIT 1;

-- ============================================================================
-- TIPS FOR USING AI_EXTRACT
-- ============================================================================

/*
1. FIELD DESCRIPTIONS MATTER
   - More descriptive field labels = better extraction accuracy
   - Be specific about format (e.g., "YYYY-MM-DD" for dates)
   - Mention typical locations (e.g., "usually in the header")

2. START SIMPLE, THEN EXPAND
   - Begin with key fields (invoice number, date, total)
   - Test and verify accuracy
   - Gradually add more fields

3. HANDLE ARRAYS CAREFULLY
   - Use FLATTEN() to process line items
   - Always include key fields in array schema
   - Test with invoices that have multiple line items

4. USE TRY_TO_* FUNCTIONS
   - TRY_TO_DATE() for dates
   - TRY_TO_NUMBER() for amounts
   - Handles malformed data gracefully

5. NESTED OBJECTS FOR ORGANIZATION
   - Group related fields (vendor info, customer info)
   - Makes JSON cleaner and easier to parse
   - Mirrors typical invoice structure

6. TEST WITH REPRESENTATIVE SAMPLES
   - Use various invoice formats
   - Test with complex and simple invoices
   - Verify extraction accuracy across different vendors

7. MONITOR AND ITERATE
   - Check extracted data quality
   - Refine field descriptions based on results
   - Adjust schema for your specific invoice formats
*/

-- ============================================================================
-- COMMON PATTERNS
-- ============================================================================

-- Pattern 1: Extract with fallback
SELECT 
    COALESCE(
        extracted_data:invoice_number::VARCHAR,
        extracted_data:invoice_id::VARCHAR,
        'UNKNOWN'
    ) as invoice_number
FROM (
    SELECT 
        SNOWFLAKE.CORTEX.AI_EXTRACT(
            TO_FILE(@invoice_stage, RELATIVE_PATH),
            {
                'invoice_number': 'Invoice number',
                'invoice_id': 'Invoice ID if invoice number not found'
            }
        ) as extracted_data
    FROM DIRECTORY(@invoice_stage)
    WHERE RELATIVE_PATH ILIKE '%.pdf'
    LIMIT 1
);

-- Pattern 2: Validate extracted data
SELECT 
    invoice_data,
    CASE 
        WHEN invoice_data:invoice_number IS NULL THEN 'Missing invoice number'
        WHEN invoice_data:total_amount IS NULL THEN 'Missing total'
        WHEN TRY_TO_NUMBER(invoice_data:total_amount) <= 0 THEN 'Invalid total'
        ELSE 'Valid'
    END as validation_status
FROM (
    SELECT 
        SNOWFLAKE.CORTEX.AI_EXTRACT(
            TO_FILE(@invoice_stage, RELATIVE_PATH),
            {
                'invoice_number': 'Invoice number',
                'total_amount': 'Total amount'
            }
        ) as invoice_data
    FROM DIRECTORY(@invoice_stage)
    WHERE RELATIVE_PATH ILIKE '%.pdf'
    LIMIT 1
);

-- Pattern 3: Batch extraction with error handling
SELECT 
    RELATIVE_PATH,
    TRY_CAST(
        SNOWFLAKE.CORTEX.AI_EXTRACT(
            TO_FILE(@invoice_stage, RELATIVE_PATH),
            {'invoice_number': 'Invoice number'}
        ) AS VARIANT
    ) as extracted_data,
    IFF(
        TRY_CAST(
            SNOWFLAKE.CORTEX.AI_EXTRACT(
                TO_FILE(@invoice_stage, RELATIVE_PATH),
                {'invoice_number': 'Invoice number'}
            ) AS VARIANT
        ) IS NOT NULL,
        'SUCCESS',
        'ERROR'
    ) as status
FROM DIRECTORY(@invoice_stage)
WHERE RELATIVE_PATH ILIKE '%.pdf';

