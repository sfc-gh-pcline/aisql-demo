-- Example admin bootstrap (adjust names to your standards)
USE ROLE ACCOUNTADMIN;

-- Create a role to own the Streamlit service + endpoints
CREATE ROLE STREAMLIT_SERVICE_ADMIN;

GRANT BIND SERVICE ENDPOINT ON ACCOUNT TO ROLE STREAMLIT_SERVICE_ADMIN;
SET current_user_name = CURRENT_USER();
GRANT ROLE STREAMLIT_SERVICE_ADMIN TO USER IDENTIFIER($current_user_name);

-- Let this role create objects and use SPCS compute
GRANT CREATE DATABASE ON ACCOUNT TO ROLE STREAMLIT_SERVICE_ADMIN;
GRANT USAGE ON DATABASE INVOICE_PROCESSING_POC TO ROLE STREAMLIT_SERVICE_ADMIN;
GRANT CREATE SCHEMA ON DATABASE INVOICE_PROCESSING_POC TO ROLE STREAMLIT_SERVICE_ADMIN;

-- Create compute pool (pick instance family/size for your needs)
CREATE COMPUTE POOL IF NOT EXISTS STREAMLIT_POOL
  MIN_NODES = 1
  MAX_NODES = 2
  INSTANCE_FAMILY = CPU_X64_S
  AUTO_RESUME = TRUE;

GRANT USAGE, MONITOR ON COMPUTE POOL STREAMLIT_POOL TO ROLE STREAMLIT_SERVICE_ADMIN;

-- Use the working database/schema

USE ROLE STREAMLIT_SERVICE_ADMIN;
CREATE DATABASE IF NOT EXISTS INVOICE_PROCESSING_POC;
CREATE SCHEMA IF NOT EXISTS INVOICE_PROCESSING_POC.APP_SCHEMA;


-- Image repository for your app image
USE ROLE STREAMLIT_SERVICE_ADMIN;
USE SCHEMA INVOICE_PROCESSING_POC.APP_SCHEMA;
CREATE IMAGE REPOSITORY IF NOT EXISTS STREAMLIT_REPO;
SHOW IMAGE REPOSITORIES IN SCHEMA INVOICE_PROCESSING_POC.APP_SCHEMA;

-- Verify after deploying container
USE ROLE STREAMLIT_SERVICE_ADMIN;
CALL SYSTEM$REGISTRY_LIST_IMAGES('/INVOICE_PROCESSING_POC/APP_SCHEMA/STREAMLIT_REPO');

USE SCHEMA INVOICE_PROCESSING_POC.APP_SCHEMA;

-- Create service definition
USE ROLE STREAMLIT_SERVICE_ADMIN;
USE SCHEMA INVOICE_PROCESSING_POC.APP_SCHEMA;

CREATE SERVICE INVOICE_PROCESSING_APP
  IN COMPUTE POOL STREAMLIT_POOL
  FROM SPECIFICATION $$
spec:
  containers:
    - name: streamlit
      image: <org_name>-<acct_name>.registry.snowflakecomputing.com/invoice_processing_poc/app_schema/streamlit_repo/streamlit:latest
      env:
        SNOWFLAKE_DATABASE: "INVOICE_PROCESSING_POC"
        SNOWFLAKE_SCHEMA: "APP_SCHEMA"
        SNOWFLAKE_WAREHOUSE: "SNOWFLAKE_INTELLIGENCE_WH"
      resources:
        requests:
          memory: 2Gi
          cpu: 1
        limits:
          memory: 4Gi
          cpu: 2
  endpoints:
    - name: streamlit
      port: 8501
      protocol: HTTP
      public: true
  networkPolicyConfig:
    allowInternetEgress: false
$$
MIN_INSTANCES = 1
MAX_INSTANCES = 1
AUTO_RESUME = TRUE
COMMENT = 'Streamlit Application';

-- Status and endpoint URL
CALL SYSTEM$GET_SERVICE_STATUS('INVOICE_PROCESSING_POC.APP_SCHEMA.INVOICE_PROCESSING_APP');
SHOW ENDPOINTS IN SERVICE INVOICE_PROCESSING_POC.APP_SCHEMA.INVOICE_PROCESSING_APP;

-- Update service with new image
ALTER SERVICE INVOICE_PROCESSING_POC.APP_SCHEMA.INVOICE_PROCESSING_APP
FROM  SPECIFICATION $$
spec:
  containers:
    - name: streamlit
      image: <org_name>-<acct_name>.registry.snowflakecomputing.com/invoice_processing_poc/app_schema/streamlit_repo/streamlit:v2025-11-23-01
      env:
        SNOWFLAKE_DATABASE: "INVOICE_PROCESSING_POC"
        SNOWFLAKE_SCHEMA: "APP_SCHEMA"
        SNOWFLAKE_WAREHOUSE: "SNOWFLAKE_INTELLIGENCE_WH"
      resources:
        requests: { memory: 2Gi, cpu: 1 }
        limits:   { memory: 4Gi, cpu: 2 }
  endpoints:
    - name: streamlit
      port: 8501
      protocol: HTTP
      public: true
$$;