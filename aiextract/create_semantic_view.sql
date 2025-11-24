-- ============================================================================
-- Create Semantic View from YAML Definition
-- ============================================================================
-- This script creates a semantic view in Snowflake using a YAML definition file
-- The semantic view provides a business-friendly interface with descriptions
-- and aliases for natural language queries
-- ============================================================================

USE DATABASE invoice_processing_poc;
USE SCHEMA invoice_pipeline;

-- ============================================================================
-- Create Semantic View from YAML
-- ============================================================================

CREATE OR REPLACE SEMANTIC VIEW invoice_semantic_view
    COMMENT = 'Semantic view of invoice data for natural language queries. Includes invoice headers and line items with comprehensive descriptions and synonyms for enhanced discoverability.'
    TABLES (
        invoice AS invoice_processing_poc.invoice_pipeline.invoice
            PRIMARY KEY (invoice_id)
            WITH SYNONYMS ('invoices', 'bills', 'sales invoices', 'accounts receivable')
            COMMENT = 'Invoice header information including vendor, customer, dates, and financial totals',
        
        invoice_detail AS invoice_processing_poc.invoice_pipeline.invoice_detail
            PRIMARY KEY (invoice_detail_id)
            WITH SYNONYMS ('line items', 'invoice lines', 'detail lines', 'invoice items')
            COMMENT = 'Individual line items on invoices showing products or services purchased'
    )
    
    RELATIONSHIPS (
        invoice_to_details AS
            invoice_detail (invoice_id) REFERENCES invoice
            COMMENT = 'One-to-many relationship from invoice header to line items'
    )
    
    FACTS (
        -- Invoice Financial Facts
        invoice.subtotal AS subtotal_amount
            WITH SYNONYMS ('subtotal', 'pre-tax total', 'base amount')
            COMMENT = 'Subtotal amount before taxes and shipping',
        
        invoice.tax_amount AS tax_amount
            WITH SYNONYMS ('tax', 'sales tax', 'vat', 'tax total')
            COMMENT = 'Total tax amount charged on the invoice',
        
        invoice.tax_rate AS tax_rate
            WITH SYNONYMS ('tax percentage', 'sales tax rate', 'vat rate')
            COMMENT = 'Tax rate percentage applied',
        
        invoice.shipping_amount AS shipping_amount
            WITH SYNONYMS ('shipping', 'freight', 'delivery charges', 'shipping cost')
            COMMENT = 'Shipping or freight charges',
        
        invoice.discount_amount AS discount_amount
            WITH SYNONYMS ('discount', 'discount total', 'rebate', 'price reduction')
            COMMENT = 'Total discount amount applied',
        
        invoice.total_amount AS total_amount
            WITH SYNONYMS ('total', 'grand total', 'amount due', 'invoice total', 'final amount')
            COMMENT = 'Final total amount including all charges',
        
        -- Line Item Facts
        invoice_detail.quantity AS quantity
            WITH SYNONYMS ('qty', 'amount', 'count', 'number of units')
            COMMENT = 'Quantity of items ordered',
        
        invoice_detail.unit_price AS unit_price
            WITH SYNONYMS ('price per unit', 'unit cost', 'price each', 'rate')
            COMMENT = 'Price per unit',
        
        invoice_detail.line_amount AS line_amount
            WITH SYNONYMS ('line total', 'extended price', 'item total', 'line item amount')
            COMMENT = 'Total line amount (quantity × unit price)',
        
        invoice_detail.tax_amount AS line_tax_amount
            WITH SYNONYMS ('line tax', 'item tax', 'line item tax')
            COMMENT = 'Tax amount for this line item'
    )
    
    DIMENSIONS (
        -- Invoice Header Dimensions
        invoice.invoice_number AS invoice_number
            WITH SYNONYMS ('invoice num', 'invoice id', 'bill number', 'receipt number', 'document number')
            COMMENT = 'Invoice number or identifier from the source document',
        
        invoice.invoice_date AS invoice_date
            WITH SYNONYMS ('issue date', 'billing date', 'date issued', 'invoice dt')
            COMMENT = 'Date the invoice was issued',
        
        invoice.due_date AS due_date
            WITH SYNONYMS ('payment due date', 'deadline', 'pay by date', 'maturity date')
            COMMENT = 'Payment due date',
        
        -- Vendor Information
        invoice.vendor_name AS vendor_name
            WITH SYNONYMS ('seller', 'supplier', 'provider', 'merchant', 'from company', 'seller name')
            COMMENT = 'Name of the vendor or seller company',
        
        invoice.vendor_address AS vendor_address
            WITH SYNONYMS ('seller address', 'vendor street address', 'from address')
            COMMENT = 'Complete vendor street address',
        
        invoice.vendor_city AS vendor_city
            WITH SYNONYMS ('seller city', 'vendor town')
            COMMENT = 'Vendor city',
        
        invoice.vendor_state AS vendor_state
            WITH SYNONYMS ('seller state', 'vendor province')
            COMMENT = 'Vendor state or province',
        
        invoice.vendor_zip AS vendor_zip
            WITH SYNONYMS ('seller zip', 'vendor postal code', 'vendor zipcode')
            COMMENT = 'Vendor postal code or ZIP code',
        
        invoice.vendor_country AS vendor_country
            WITH SYNONYMS ('seller country')
            COMMENT = 'Vendor country',
        
        invoice.vendor_phone AS vendor_phone
            WITH SYNONYMS ('seller phone', 'vendor telephone', 'vendor contact number')
            COMMENT = 'Vendor phone number',
        
        invoice.vendor_email AS vendor_email
            WITH SYNONYMS ('seller email', 'vendor contact email')
            COMMENT = 'Vendor email address',
        
        invoice.vendor_tax_id AS vendor_tax_id
            WITH SYNONYMS ('seller tax id', 'vendor ein', 'vendor tax number', 'federal id')
            COMMENT = 'Vendor tax ID or EIN',
        
        -- Customer Information
        invoice.customer_name AS customer_name
            WITH SYNONYMS ('buyer', 'client', 'purchaser', 'bill to', 'to company', 'customer')
            COMMENT = 'Name of the customer or buyer company',
        
        invoice.customer_address AS customer_address
            WITH SYNONYMS ('buyer address', 'customer street address', 'bill to address')
            COMMENT = 'Complete customer street address',
        
        invoice.customer_city AS customer_city
            WITH SYNONYMS ('buyer city', 'customer town')
            COMMENT = 'Customer city',
        
        invoice.customer_state AS customer_state
            WITH SYNONYMS ('seller state', 'customer province')
            COMMENT = 'Customer state or province',
        
        invoice.customer_zip AS customer_zip
            WITH SYNONYMS ('buyer zip', 'customer postal code', 'customer zipcode')
            COMMENT = 'Customer postal code or ZIP code',
        
        invoice.customer_country AS customer_country
            WITH SYNONYMS ('buyer country')
            COMMENT = 'Customer country',
        
        invoice.customer_phone AS customer_phone
            WITH SYNONYMS ('buyer phone', 'customer telephone', 'customer contact number')
            COMMENT = 'Customer phone number',
        
        invoice.customer_email AS customer_email
            WITH SYNONYMS ('buyer email', 'customer contact email')
            COMMENT = 'Customer email address',
        
        -- Additional Invoice Dimensions
        invoice.currency AS currency
            WITH SYNONYMS ('currency code', 'money type', 'denomination')
            COMMENT = 'Currency code (e.g., USD, EUR, GBP)',
        
        invoice.payment_terms AS payment_terms
            WITH SYNONYMS ('terms', 'payment conditions', 'net terms', 'payment agreement')
            COMMENT = 'Payment terms and conditions',
        
        invoice.po_number AS po_number
            WITH SYNONYMS ('po', 'purchase order', 'po num', 'order number')
            COMMENT = 'Purchase order number',
        
        invoice.notes AS invoice_notes
            WITH SYNONYMS ('comments', 'remarks', 'additional info', 'memo')
            COMMENT = 'Additional notes or comments on the invoice',
        
        -- Line Item Dimensions
        invoice_detail.line_number AS line_number
            WITH SYNONYMS ('line num', 'item number', 'row number', 'sequence number')
            COMMENT = 'Line item sequence number on the invoice',
        
        invoice_detail.item_description AS item_description
            WITH SYNONYMS ('description', 'item desc', 'product description', 'service description', 'product name')
            COMMENT = 'Description of the product or service',
        
        invoice_detail.item_code AS item_code
            WITH SYNONYMS ('sku', 'product code', 'part number', 'item id', 'product sku')
            COMMENT = 'Item code, SKU, or product ID',
        
        invoice_detail.unit_of_measure AS unit_of_measure
            WITH SYNONYMS ('uom', 'unit', 'measure', 'measurement unit')
            COMMENT = 'Unit of measure (e.g., EA, HR, BOX, LB)',
        
        invoice_detail.notes AS line_notes
            WITH SYNONYMS ('line notes', 'item notes', 'comments', 'remarks')
            COMMENT = 'Additional notes for this line item',
        
        -- Metadata
        invoice.created_timestamp AS created_timestamp
            WITH SYNONYMS ('created at', 'creation time', 'inserted at')
            COMMENT = 'Timestamp when the invoice record was created in the database'
    )
    
    METRICS (
        total_invoices AS COUNT(DISTINCT invoice.invoice_id)
            COMMENT = 'Total count of invoices',
        
        total_revenue AS SUM(invoice.total_amount)
            COMMENT = 'Total revenue across all invoices',
        
        average_invoice_value AS AVG(invoice.total_amount)
            COMMENT = 'Average value of an invoice',
        
        total_line_items AS COUNT(invoice_detail.invoice_detail_id)
            COMMENT = 'Total count of all line items across all invoices',
        
        total_tax_collected AS SUM(invoice.tax_amount)
            COMMENT = 'Total tax amount collected across all invoices',
        
        total_shipping_charges AS SUM(invoice.shipping_amount)
            COMMENT = 'Total shipping charges across all invoices',
        
        total_discounts_given AS SUM(invoice.discount_amount)
            COMMENT = 'Total discount amount given across all invoices'
    );

-- ============================================================================
-- Verify Semantic View Creation
-- ============================================================================

-- Show the semantic view
SHOW SEMANTIC VIEWS LIKE 'invoice_semantic_view';

-- Test basic query
SELECT 
    invoice_number,
    vendor_name,
    customer_name,
    invoice_date,
    total_amount,
    currency
FROM invoice_semantic_view
LIMIT 5;

-- Test aggregation with metrics
SELECT 
    COUNT(DISTINCT invoice_number) as invoice_count,
    SUM(total_amount) as total_revenue,
    AVG(total_amount) as avg_invoice_value
FROM invoice_semantic_view;

-- Test join between invoice and line items
SELECT 
    i.invoice_number,
    i.vendor_name,
    COUNT(d.line_number) as line_count,
    SUM(d.line_amount) as total_line_amount
FROM invoice_semantic_view i
LEFT JOIN invoice_semantic_view d ON i.invoice_id = d.invoice_id
GROUP BY i.invoice_number, i.vendor_name
LIMIT 10;

-- ============================================================================
-- Query Examples for Natural Language Use
-- ============================================================================

/*
The semantic view enables natural language queries through Snowflake Cortex.
Here are some example questions that could be asked:

1. "Show me all invoices from last month"
2. "What is the total revenue from vendor X?"
3. "Which customers have the highest invoice totals?"
4. "Show me invoices that are overdue"
5. "What are the most common items purchased?"
6. "Calculate average invoice value by vendor"
7. "Show me all line items for invoice number ABC123"
8. "What is the total tax collected this quarter?"
9. "Which vendors do we purchase from the most?"
10. "Show me invoices with shipping charges greater than $100"

These queries can be executed through:
- Snowflake Cortex Analyst
- Cortex Agent (if configured)
- Traditional SQL with the semantic view
*/

