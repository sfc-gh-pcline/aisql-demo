# Deployment Checklist - Invoice Processing Pipeline

Use this checklist to deploy the Snowflake AI Invoice Processing Pipeline step-by-step.

---

##  Pre-Deployment

### Environment Verification

- [ ] **Snowflake Account Access**
  - [ ] Login credentials verified
  - [ ] Appropriate role assigned (ACCOUNTADMIN or similar)
  - [ ] Access to create databases, schemas, and tasks

- [ ] **Snowflake Cortex AI Enabled**
  - [ ] Verify Cortex AI is available in your account
  - [ ] Test access to AI_EXTRACT function:
    ```sql
    -- This will fail if you don't have a file yet, but verifies function exists
    SELECT SNOWFLAKE.CORTEX.AI_EXTRACT;
    ```
  - [ ] If error: Contact Snowflake support to enable Cortex AI and AI_EXTRACT

- [ ] **Warehouse Available**
  - [ ] Warehouse exists (e.g., COMPUTE_WH)
  - [ ] Warehouse can be used by your role
  - [ ] Auto-resume is enabled
  - [ ] Test warehouse:
    ```sql
    USE WAREHOUSE COMPUTE_WH;
    SELECT CURRENT_WAREHOUSE();
    ```

- [ ] **Cost Approval**
  - [ ] Estimated costs reviewed with stakeholders
  - [ ] Budget allocated for AI function usage
  - [ ] Warehouse compute costs approved

### Files Prepared

- [ ] **SQL Scripts Downloaded**
  - [ ] `snowflake_invoice_pipeline_v2.sql` (main script)
  - [ ] `testing_validation.sql` (test script)

- [ ] **Sample Invoices Ready**
  - [ ] Test PDF invoices collected
  - [ ] Files are valid, non-corrupted PDFs
  - [ ] Files are not password-protected
  - [ ] Files represent typical invoice formats

- [ ] **Documentation Reviewed**
  - [ ] `QUICK_START.md` read
  - [ ] `README_INVOICE_PIPELINE.md` reviewed
  - [ ] `TROUBLESHOOTING.md` bookmarked

---

##  Deployment Steps

### Step 1: Create Database Objects

- [ ] **Connect to Snowflake**
  ```
  Method:  Web UI   SnowSQL   Other: ____________
  ```

- [ ] **Execute Main Script**
  - [ ] Open `snowflake_invoice_pipeline_v2.sql`
  - [ ] Execute entire script in Snowflake
  - [ ] Verify no errors in execution
  - [ ] Script execution time: ________ seconds

- [ ] **Verify Database Created**
  ```sql
  SHOW DATABASES LIKE 'INVOICE_PROCESSING_POC';
  ```
  - [ ] Database exists: 

- [ ] **Verify Schema Created**
  ```sql
  USE DATABASE invoice_processing_poc;
  SHOW SCHEMAS LIKE 'INVOICE_PIPELINE';
  ```
  - [ ] Schema exists: 

### Step 2: Verify Objects Created

- [ ] **Check Tables**
  ```sql
  USE SCHEMA invoice_pipeline;
  SHOW TABLES;
  ```
  - [ ] raw_json
  - [ ] invoice
  - [ ] invoice_detail
  - [ ] Total tables: 4 

- [ ] **Check Views**
  ```sql
  SHOW VIEWS;
  ```
  - [ ] pipeline_monitoring
  - [ ] invoice_summary
  - [ ] invoice_detail_view
  - [ ] Total views: 3 

- [ ] **Check Streams**
  ```sql
  SHOW STREAMS;
  ```
  - [ ] invoice_stage_stream
  - [ ] raw_json_stream
  - [ ] Total streams: 2 

- [ ] **Check Tasks**
  ```sql
  SHOW TASKS;
  ```
  - [ ] task_extract_invoices (state: suspended)
  - [ ] task_parse_json_to_tables (state: suspended)
  - [ ] Total tasks: 2 

- [ ] **Check Procedures**
  ```sql
  SHOW PROCEDURES;
  ```
  - [ ] refresh_and_process()
  - [ ] get_pipeline_stats()
  - [ ] Total procedures: 2 

- [ ] **Check Stage**
  ```sql
  SHOW STAGES;
  ```
  - [ ] invoice_stage (with directory enabled)
  - [ ] Total stages: 1 

### Step 3: Upload Test Files

- [ ] **Upload via SnowSQL** (Option A)
  ```bash
  snowsql -a <account> -u <user>
  
  PUT file:///path/to/invoice.pdf 
      @invoice_processing_poc.invoice_pipeline.invoice_stage 
      AUTO_COMPRESS=FALSE;
  ```
  - [ ] Files uploaded successfully
  - [ ] Number of files: ________

- [ ] **Upload via Web UI** (Option B)
  - [ ] Navigate to: Data → Databases → invoice_processing_poc → invoice_pipeline → Stages
  - [ ] Click on invoice_stage
  - [ ] Click "+ Files" button
  - [ ] Select and upload PDF files
  - [ ] Files uploaded successfully
  - [ ] Number of files: ________

- [ ] **Verify Files in Stage**
  ```sql
  SELECT * FROM DIRECTORY(@invoice_stage);
  ```
  - [ ] Files appear in directory listing
  - [ ] File names correct
  - [ ] File sizes reasonable

### Step 4: Test Manual Processing

- [ ] **Refresh Stage and Process**
  ```sql
  USE DATABASE invoice_processing_poc;
  USE SCHEMA invoice_pipeline;
  
  CALL refresh_and_process();
  ```
  - [ ] Procedure executed successfully
  - [ ] No errors returned

- [ ] **Wait for Processing**
  - [ ] Wait 30-60 seconds for AI extraction
  - [ ] Time waited: ________ seconds

- [ ] **Verify Extraction Results**
  ```sql
  SELECT * FROM raw_json ORDER BY extraction_timestamp DESC;
  ```
  - [ ] Records created in raw_json
  - [ ] processing_status = 'SUCCESS'
  - [ ] extracted_json is not null
  - [ ] Number of successful extractions: ________
  - [ ] Number of failed extractions: ________

- [ ] **View Extracted JSON**
  ```sql
  SELECT 
      file_name,
      TO_JSON(extracted_json) as json_data
  FROM raw_json
  LIMIT 1;
  ```
  - [ ] JSON structure looks correct
  - [ ] invoice_number present
  - [ ] vendor information present
  - [ ] line_items array present

- [ ] **Verify Invoice Records**
  ```sql
  SELECT * FROM invoice ORDER BY created_timestamp DESC;
  ```
  - [ ] Records created in invoice table
  - [ ] Invoice numbers extracted correctly
  - [ ] Vendor names correct
  - [ ] Total amounts reasonable
  - [ ] Number of invoices: ________

- [ ] **Verify Line Item Records**
  ```sql
  SELECT * FROM invoice_detail ORDER BY invoice_id, line_number;
  ```
  - [ ] Line items created
  - [ ] Descriptions present
  - [ ] Quantities and prices reasonable
  - [ ] Number of line items: ________

- [ ] **Check Pipeline Monitoring**
  ```sql
  SELECT * FROM pipeline_monitoring;
  ```
  - [ ] End-to-end trace visible
  - [ ] File → extraction → invoice linkage correct
  - [ ] Line item counts match expectations

### Step 5: Run Comprehensive Tests

- [ ] **Execute Test Suite**
  - [ ] Open `testing_validation.sql`
  - [ ] Execute all test sections
  - [ ] Review output for failures

- [ ] **Test Results Summary**
  - [ ] Pre-deployment validation:  Pass  Fail
  - [ ] Stage testing:  Pass  Fail
  - [ ] AI extraction testing:  Pass  Fail
  - [ ] JSON parsing testing:  Pass  Fail
  - [ ] Monitoring views testing:  Pass  Fail
  - [ ] Data quality validation:  Pass  Fail
  - [ ] End-to-end validation:  Pass  Fail

- [ ] **Address Any Failures**
  - [ ] Review `TROUBLESHOOTING.md`
  - [ ] Fix identified issues
  - [ ] Re-run failed tests
  - [ ] All critical tests passing

### Step 6: Enable Automated Processing (Optional)

 **Note:** Only enable if you want automatic processing. You can always process manually with `CALL refresh_and_process();`

- [ ] **Resume Tasks**
  ```sql
  -- Resume in reverse dependency order
  ALTER TASK task_parse_json_to_tables RESUME;
  ALTER TASK task_extract_invoices RESUME;
  ```

- [ ] **Verify Tasks Running**
  ```sql
  SHOW TASKS;
  ```
  - [ ] task_extract_invoices: state = 'started'
  - [ ] task_parse_json_to_tables: state = 'started'

- [ ] **Test Automatic Processing**
  - [ ] Upload a new test file
  - [ ] Wait 2-3 minutes
  - [ ] Verify file processed automatically:
    ```sql
    SELECT * FROM pipeline_monitoring 
    ORDER BY extraction_timestamp DESC 
    LIMIT 1;
    ```
  - [ ] New file appears in monitoring view

- [ ] **Monitor Task Execution**
  ```sql
  SELECT 
      name,
      state,
      scheduled_time,
      completed_time
  FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
  WHERE name IN ('TASK_EXTRACT_INVOICES', 'TASK_PARSE_JSON_TO_TABLES')
  ORDER BY scheduled_time DESC
  LIMIT 10;
  ```
  - [ ] Tasks executing on schedule
  - [ ] No errors in task history

---

##  Post-Deployment

### Validation

- [ ] **Data Quality Check**
  ```sql
  CALL get_pipeline_stats();
  ```
  - [ ] All metrics look reasonable
  - [ ] Success rate acceptable

- [ ] **Accuracy Validation**
  - [ ] Manually compare 3-5 invoices
  - [ ] Verify extracted data matches PDF
  - [ ] Check invoice totals correct
  - [ ] Verify line items complete
  - [ ] Accuracy rate: ________%

- [ ] **Performance Check**
  - [ ] Processing time acceptable
  - [ ] No timeouts or errors
  - [ ] Warehouse usage reasonable

### Documentation

- [ ] **Document Customizations**
  - [ ] List any changes made to scripts
  - [ ] Document custom validation rules
  - [ ] Note any special configurations

- [ ] **Create Runbook**
  - [ ] How to monitor the pipeline
  - [ ] How to handle errors
  - [ ] Who to contact for issues
  - [ ] Escalation procedures

- [ ] **Train Team**
  - [ ] Share documentation with team
  - [ ] Demonstrate how to use the pipeline
  - [ ] Show how to monitor and troubleshoot
  - [ ] Establish support procedures

### Monitoring Setup

- [ ] **Create Monitoring Queries**
  - [ ] Save key queries as views or worksheets
  - [ ] Set up scheduled reports (if needed)
  - [ ] Document KPIs to track

- [ ] **Set Up Alerts** (Optional)
  - [ ] Configure email notifications for errors
  - [ ] Set up task failure alerts
  - [ ] Create dashboard for monitoring

- [ ] **Schedule Reviews**
  - [ ] Daily: Check for errors
  - [ ] Weekly: Review accuracy and performance
  - [ ] Monthly: Analyze costs and optimization

### Security Review

- [ ] **Access Control**
  - [ ] Verify role-based access configured
  - [ ] Limit access to sensitive tables
  - [ ] Document who has access

- [ ] **Data Protection**
  - [ ] Verify encryption at rest enabled
  - [ ] Confirm no PII exposure
  - [ ] Review data retention policies

- [ ] **Audit Trail**
  - [ ] Verify query history enabled
  - [ ] Test audit logging working
  - [ ] Document compliance requirements

---

##  Go-Live Checklist

### Before Production

- [ ] **All Tests Pass**
- [ ] **Accuracy Validated**
- [ ] **Performance Acceptable**
- [ ] **Costs Approved**
- [ ] **Team Trained**
- [ ] **Documentation Complete**
- [ ] **Monitoring Set Up**
- [ ] **Backup/Recovery Tested**
- [ ] **Security Review Complete**

### Go-Live Decision

- [ ] **Stakeholder Approval**
  - [ ] Business owner: _________________ Date: _______
  - [ ] Technical lead: _________________ Date: _______
  - [ ] Security team: _________________ Date: _______

- [ ] **Go-Live Plan**
  - [ ] Start date: _________________
  - [ ] Pilot period: _______ days
  - [ ] Full rollout: _________________

### Post-Go-Live

- [ ] **Monitor Closely**
  - [ ] Check daily for first week
  - [ ] Review all errors immediately
  - [ ] Track accuracy metrics

- [ ] **Gather Feedback**
  - [ ] Survey users after 1 week
  - [ ] Document issues and improvements
  - [ ] Plan enhancements

- [ ] **Optimize**
  - [ ] Tune warehouse sizes
  - [ ] Adjust task schedules
  - [ ] Refine AI prompts
  - [ ] Implement quick wins

---

##  Rollback Plan

If critical issues arise:

- [ ] **Immediate Actions**
  ```sql
  -- Suspend tasks to stop processing
  ALTER TASK task_extract_invoices SUSPEND;
  ALTER TASK task_parse_json_to_tables SUSPEND;
  ```

- [ ] **Assess Impact**
  - [ ] Document the issue
  - [ ] Determine scope of problem
  - [ ] Estimate fix time

- [ ] **Communicate**
  - [ ] Notify stakeholders
  - [ ] Provide status updates
  - [ ] Set expectations for resolution

- [ ] **Fix or Revert**
  - [ ] Apply fix if known
  - [ ] Test thoroughly before resuming
  - [ ] Or: Return to manual processing temporarily

---

## 📝 Notes & Comments

### Deployment Date: _________________

### Deployed By: _________________

### Deployment Notes:
```
_____________________________________________________
_____________________________________________________
_____________________________________________________
_____________________________________________________
```

### Issues Encountered:
```
_____________________________________________________
_____________________________________________________
_____________________________________________________
```

### Resolutions Applied:
```
_____________________________________________________
_____________________________________________________
_____________________________________________________
```

### Follow-Up Actions:
```
 _____________________________________________________
 _____________________________________________________
 _____________________________________________________
```

---

##  Deployment Complete!

Congratulations! Your Snowflake AI Invoice Processing Pipeline is now deployed.

**Next Steps:**
1. Process your first production invoices
2. Monitor results closely
3. Gather user feedback
4. Plan improvements and enhancements

**Resources:**
- `README_INVOICE_PIPELINE.md` - Full documentation
- `TROUBLESHOOTING.md` - Issue resolution
- `PROJECT_OVERVIEW.md` - Architecture and overview

**Support:**
- Internal: _________________ (Email: _________________)
- Snowflake: https://support.snowflake.com/

---

*Keep this checklist for future reference and similar deployments*

