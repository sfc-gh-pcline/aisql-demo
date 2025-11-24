# Get repository URL
# In Snowsight/Worksheet: SHOW IMAGE REPOSITORIES IN SCHEMA APP_DB.APP_SCHEMA;

# Locally (build for linux/amd64)
docker build --platform=linux/amd64 -t streamlit:latest .

# Tag with repository URL
docker tag streamlit:latest <org_name>-<acct_name>.registry.snowflakecomputing.com/invoice_processing_poc/app_schema/streamlit_repo/streamlit:latest

# Login and push
docker login <org_name>-<acct_name>.registry.snowflakecomputing.com -u pcline
docker push <org_name>-<acct_name>.registry.snowflakecomputing.com/invoice_processing_poc/app_schema/streamlit_repo/streamlit:latest
