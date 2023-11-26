import os
import sys
import logging
import boto3
import psycopg2
import json
from aws_xray_sdk.core import patch_all
from botocore.exceptions import ClientError

# Set up logger and aws xray
logger = logging.getLogger()
logger.setLevel(logging.INFO)
patch_all()

# Read the enviromental variables
try:
    SECRET_ID = os.environ["SECRET_ID"]
except KeyError:
    logger.error('"SECRET_ID" environment variable is required')
    sys.exit(1)
try:
    HOST = os.environ["HOST"]
except KeyError:
    logger.error('"HOST" environment variable is required')
    sys.exit(1)

VERSION_ID = os.environ.get('VERSION_ID')
VERSION_STAGE = os.environ.get('VERSION_STAGE')
params = {'SecretId': SECRET_ID, 'VersionId': VERSION_ID, 'VersionStage': VERSION_STAGE}
secrets_not_none_params = {k:v for k, v in params.items() if v is not None}

# ENV for moto testing
endpoint_url = os.environ.get("MOTO_HTTP_ENDPOINT")

# Create the secret manager client
secrets = boto3.client('secretsmanager', endpoint_url=endpoint_url)


def lambda_handler(event, context):

    logger.info('Inside lambda function')

    try:
        secret_response = secrets.get_secret_value(**secrets_not_none_params)
    except ClientError as e:
        logger.error(str(e))
        raise e

    logger.info('After secret response')
    # Decrypts secret using the associated KMS key.
    secret = json.loads(secret_response['SecretString'])
    username = secret.get('username')
    password = secret.get('password')

    # Connect to the cluster
    try:
        conn = None
        conn = psycopg2.connect(
            host=HOST,
            port=5432,
            user=username,
            password=password
        )
        # Create a Cursor object
        cursor = conn.cursor()
        # Query using the Cursor
        cursor.execute("select 1")
        #Retrieve the query result set
        result = cursor.fetchall()
    except Exception as e:
        logger.error(str(e))
        sys.exit(1)
    finally:
        if conn:
            conn.close()
    

    return result