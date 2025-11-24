# Streamlit on SPCS: end‑to‑end deployment and access
## Overview
This guide packages your Streamlit app into a container, pushes it to Snowflake’s image repository, deploys it in a compute pool as a long‑running service, exposes a public HTTP endpoint, and grants Snowflake users access via role-based controls. SPCS endpoints use Snowflake OAuth, so users authenticate with their Snowflake credentials at the app URL.
## Prerequisites
* Ensure SPCS is enabled and your admin role can create compute pools, image repositories, and services, and bind public endpoints (requires the account-level privilege BIND SERVICE ENDPOINT).
* Create or identify a warehouse that the app will use for queries; grant USAGE to the service owner role.
* Use a dedicated service owner role to own the service and hold BIND SERVICE ENDPOINT for public endpoints.
* Keep public Internet egress disabled unless needed; if needed, configure External Access Integration and allowInternetEgress in the service spec.
### Step 0 — Bootstrap Snowflake objects (one-time)
Use an admin role to set up roles, a database/schema, a compute pool, and an image repository.

```
sql
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


-- Create stage and tables for app
USE ROLE STREAMLIT_SERVICE_ADMIN;
USE SCHEMA INVOICE_PROCESSING_POC.APP_SCHEMA;
CREATE STAGE IF NOT EXISTS INVOICE_UPLOADS
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for storing PDF invoice files for invoice processing';

CREATE OR REPLACE TABLE INVOICE_PROCESSING_POC.APP_SCHEMA.INVOICE_HEADER (
	INVOICE_ID varchar(50) primary key,
	VENDOR_NAME VARCHAR(500),
	INVOICE_NO VARCHAR(100),
	PURCHASE_ORDER_NO VARCHAR(100),
	INVOICE_DATE DATE,
	INVOICE_SUBTOTAL NUMBER(18,2),
	INVOICE_TAX_AMOUNT NUMBER(18,2),
	INVOICE_TOTAL NUMBER(18,2),
	DEPOSIT_CREDIT_AMOUNT NUMBER(18,2),
	UPLOADED_FILE_PATH  VARCHAR(1000)
    )
;

CREATE OR REPLACE TABLE INVOICE_PROCESSING_POC.APP_SCHEMA.INVOICE_DETAIL (
    DETAIL_ID varchar(50) primary key,
	INVOICE_ID varchar(50),
    LINE_ITEM_NUMBER INTEGER,
    ITEM_DESCRIPTION VARCHAR(1000),
    QUANTITY INTEGER,
    LINE_TOTAL  NUMBER(38,0),
	constraint fk_invoice_id foreign key (INVOICE_ID) references INVOICE_HEADER (INVOICE_ID)
);


-- Image repository for your app image
USE ROLE STREAMLIT_SERVICE_ADMIN;
USE SCHEMA INVOICE_PROCESSING_POC.APP_SCHEMA;
CREATE IMAGE REPOSITORY IF NOT EXISTS STREAMLIT_REPO;
SHOW IMAGE REPOSITORIES IN SCHEMA INVOICE_PROCESSING_POC.APP_SCHEMA;

-- Verify after deploying container
USE ROLE STREAMLIT_SERVICE_ADMIN;
CALL SYSTEM$REGISTRY_LIST_IMAGES('/INVOICE_PROCESSING_POC/APP_SCHEMA/STREAMLIT_REPO');

USE SCHEMA INVOICE_PROCESSING_POC.APP_SCHEMA;
```

### Step 1 — Containerize your Streamlit app
Create a Dockerfile that exposes Streamlit on 0.0.0.0:8501 and install your dependencies.
```
dockerfile
FROM python:3.11-slim

# Optional: system build deps
RUN apt-get update && apt-get install -y build-essential && rm -rf /var/lib/apt/lists/*

# Copy app
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

# Streamlit settings for container
ENV STREAMLIT_SERVER_ADDRESS=0.0.0.0
ENV STREAMLIT_SERVER_PORT=8501

EXPOSE 8501
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]
```
Notes:
* Specify container CPU/memory via the service spec (below). Omitting resource requests/limits can leave you with defaults that are too small for Streamlit + data workloads; set explicit values to avoid slowdowns/timeouts.
### Step 2 — Push the image to Snowflake’s image repository
Build for linux/amd64, tag with the repository_url from SHOW IMAGE REPOSITORIES, login to the registry, and push.
```
bash
# Build for linux/amd64
docker build --platform=linux/amd64 -t streamlit:latest .

# Tag with your Snowflake image repository
docker tag streamlit:latest <org_name>-<acct_name>.registry.snowflakecomputing.com/invoice_processing_poc/app_schema/streamlit_repo/streamlit:latest

# Login and push
docker login <org_name>-<acct_name>.registry.snowflakecomputing.com -u <user>
docker push <org_name>-<acct_name>.registry.snowflakecomputing.com/invoice_processing_poc/app_schema/streamlit_repo/streamlit:latest
```
Verify in Snowflake:
```
sql
CALL SYSTEM$REGISTRY_LIST_IMAGES('/INVOICE_PROCESSING_POC/APP_SCHEMA/STREAMLIT_REPO');
```
Tip: A 401 Unauthorized when the service pulls the image usually means the service role lacks READ on the image repository (or a registry/network policy issue). Fix the grants for the service owner role and verify the repository URL/tag.
### Step 3 — Create the Service and expose a public endpoint
Deploy the Streamlit container as a long‑running service in your compute pool and expose port 8501 as a public HTTP endpoint.

```
sql
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
```

Copy the ingress_url from SHOW ENDPOINTS and open it in your browser. You’ll be prompted to sign in with your Snowflake credentials (SPCS uses Snowflake OAuth at public endpoints).

### Step 4 — Allow Snowflake users to access the app
There are two layers to grant:
* Endpoint access: grant the service role to the account role your users will use (as of 2024/04, endpoint usage requires a role with the service role, e.g., ALL_ENDPOINTS_USAGE).
* Data access: grant standard database/schema/warehouse privileges to your user role so app queries succeed.
Example:
```
sql
-- Allow a user role to reach the public endpoint
GRANT SERVICE ROLE INVOICE_PROCESSING_POC.APP_SCHEMA.INVOICE_PROCESSING_APP!ALL_ENDPOINTS_USAGE
  TO ROLE <app_user_role>;

-- Grant data access required by the app
GRANT USAGE ON DATABASE INVOICE_PROCESSING_POC TO ROLE <app_user_role>;
GRANT USAGE ON SCHEMA INVOICE_PROCESSING_POC.APP_SCHEMA TO ROLE <app_user_role>;
GRANT SELECT ON ALL TABLES IN SCHEMA INVOICE_PROCESSING_POC.APP_SCHEMA TO ROLE <app_user_role>;
GRANT USAGE ON WAREHOUSE SNOWFLAKE_INTELLIGENCE_WH TO ROLE <app_user_role>;

-- Optional: allow users to DESCRIBE/SHOW the service
GRANT USAGE ON SERVICE INVOICE_PROCESSING_POC.APP_SCHEMA.INVOICE_PROCESSING_APP TO ROLE <app_user_role>;
```

### Step 5 — Connect securely from Streamlit to Snowflake (in SPCS)
In SPCS, read the Snowflake-provided OAuth token from /snowflake/session/token to avoid storing credentials.

```
python
import os
from snowflake.snowpark import Session

def get_login_token():
    with open('/snowflake/session/token', 'r') as f:
        return f.read()

connection_parameters = {
    "account": os.getenv("SNOWFLAKE_ACCOUNT"),
    "host": os.getenv("SNOWFLAKE_HOST"),
    "token": get_login_token(),
    "authenticator": "oauth",
    "database": os.getenv("SNOWFLAKE_DATABASE"),
    "schema": os.getenv("SNOWFLAKE_SCHEMA"),
    "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE"),
}
session = Session.builder.configs(connection_parameters).create()
```

## Operations and monitoring
```
sql
-- Service health
CALL SYSTEM$GET_SERVICE_STATUS('INVOICE_PROCESSING_POC.APP_SCHEMA.INVOICE_PROCESSING_APP');

-- Container logs (use the container name, e.g., 'streamlit')
CALL SYSTEM$GET_SERVICE_LOGS('INVOICE_PROCESSING_POC.APP_SCHEMA.INVOICE_PROCESSING_APP', 0, 'streamlit', 500);

-- Endpoint URL
SHOW ENDPOINTS IN SERVICE INVOICE_PROCESSING_POC.APP_SCHEMA.INVOICE_PROCESSING_APP;
```

## Updating the service with a new image
When you need to deploy a new version of your application:
```
sql
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
```

## Troubleshooting guide
* Access denied at endpoint: ensure the user’s active role has a granted service role (e.g., <service>!ALL_ENDPOINTS_USAGE). This became required after 2024/04.
* Image pull 401 Unauthorized: typically missing READ on the image repository for the service owner role (or a registry/network policy issue). Verify repository grants and tags.
* App slow or timing out: set explicit CPU/memory requests/limits in the service spec; defaults when omitted can be insufficient.
* Public endpoint CSP restrictions: SPCS public endpoints enforce a CSP you can’t customize; apps relying on inline scripts or external CDNs may need adjustments or an internal reverse proxy pattern.
* Internet egress: keep disabled unless necessary; when needed, use an External Access Integration and/or allowInternetEgress in the spec.

## Minimal working example (MWX)
Create the service, then grab the URL and grant users endpoint access.
```
sql
CREATE SERVICE INVOICE_PROCESSING_APP
  IN COMPUTE POOL STREAMLIT_POOL
  FROM SPECIFICATION $$
spec:
  containers:
    - name: streamlit
      image: <org_name>-<acct_name>.registry.snowflakecomputing.com/invoice_processing_poc/app_schema/streamlit_repo/streamlit:latest
  endpoints:
    - name: streamlit
      port: 8501
      protocol: HTTP
      public: true
$$
MIN_INSTANCES=1
MAX_INSTANCES=1;

SHOW ENDPOINTS IN SERVICE INVOICE_PROCESSING_POC.APP_SCHEMA.INVOICE_PROCESSING_APP;

GRANT SERVICE ROLE INVOICE_PROCESSING_POC.APP_SCHEMA.INVOICE_PROCESSING_APP!ALL_ENDPOINTS_USAGE
  TO ROLE <app_user_role>;
```