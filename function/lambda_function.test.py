import unittest
import logging
import jsonpickle
import sys
import boto3
import moto
import os
import io
import zipfile
import json
from uuid import uuid4
from aws_xray_sdk.core import xray_recorder
from botocore.exceptions import ClientError

logger = logging.getLogger()
endpoint_url='http://127.0.0.1:5000'


def _process_lambda(func_str):
    """Creates a ZIP out of the given function"""
    zip_output = io.BytesIO()
    zip_file = zipfile.ZipFile(zip_output, "w", zipfile.ZIP_DEFLATED)
    zip_file.writestr("lambda_function.py", func_str)
    zip_file.close()
    zip_output.seek(0)
    return zip_output.read()

def get_test_zip_file():
    pfunc = """
import os
import sys
import logging
import boto3
import json

# Set up logger
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Read the enviromental variables
try:
    SECRET_ID = os.environ["SECRET_ID"]
    logger.warning(SECRET_ID)
except KeyError:
    logger.error('"SECRET_ID" environment variable is required')
    sys.exit(1)
try:
    HOST = os.environ["HOST"]
    logger.warning(HOST)
except KeyError:
    logger.error('"HOST" environment variable is required')
    sys.exit(1)

VERSION_ID = os.environ.get('VERSION_ID')
VERSION_STAGE = os.environ.get('VERSION_STAGE')
params = {'SecretId': SECRET_ID, 'VersionId': VERSION_ID, 'VersionStage': VERSION_STAGE}
secrets_not_none_params = {k:v for k, v in params.items() if v is not None}

def lambda_handler(event, context):
    
    full_url = os.environ.get("MOTO_HTTP_ENDPOINT")
    secrets = boto3.client('secretsmanager', endpoint_url=full_url)
    secret_response = secrets.get_secret_value(**secrets_not_none_params)
    secret = json.loads(secret_response['SecretString'])
    return secret
"""
    return _process_lambda(pfunc)


@moto.mock_rds
@moto.mock_secretsmanager
@moto.mock_lambda
@moto.mock_iam
class TestFunction(unittest.TestCase):

    def get_role_name(self):
        """Creates a dummy role"""
        with moto.mock_iam():
            iam = boto3.client("iam")
            return iam.create_role(
                RoleName="role",
                AssumeRolePolicyDocument="some policy",
                Path="/test/",
            )["Role"]["Arn"]


     # Test Setup
    def setUp(self):
        """Create mocked resources for use during tests"""

        # Mock RDS postgresql
        rds_client = boto3.client('rds', endpoint_url=endpoint_url)
        res = rds_client.create_db_instance(DBInstanceIdentifier='testdb', DBInstanceClass='db.t3.micro',
                                     Engine='postgres', EngineVersion='15.4',
                                     ManageMasterUserPassword=True, MasterUsername='postgres')

        self.endpoint = res['DBInstance']['Endpoint']['Address']
        logging.warning(self.endpoint)
        secrets_client = boto3.client('secretsmanager', endpoint_url=endpoint_url)
        try:
            response = secrets_client.create_secret(Name='test', 
                                                    SecretString=json.dumps({'username':'postgres', 'password' :'test1234'}),
                                                    ForceOverwriteReplicaSecret=True)
        except ClientError:
            pass
        self.secret = response['ARN']
        logger.warning(self.secret)

        # Mock environment
        os.environ["HOST"] = self.endpoint
        os.environ["SECRET_ID"] = self.secret
        os.environ['AWS_ACCESS_KEY_ID'] = 'testing'
        os.environ['AWS_SECRET_ACCESS_KEY'] = 'testing'
        os.environ['AWS_SECURITY_TOKEN'] = 'testing'
        os.environ['AWS_SESSION_TOKEN'] = 'testing'

    def test_invoke_requestresponse_function(self):
        conn = boto3.client("lambda")
        function_name = str(uuid4())[0:6]

        fxn = conn.create_function(
            FunctionName=function_name,
            Runtime="python3.10",
            Role=self.get_role_name(),
            Handler="lambda_function.lambda_handler",
            Code={"ZipFile": get_test_zip_file()},
            Description="test lambda function",
            Timeout=10,
            MemorySize=128,
            Publish=True,
            Environment={
                'Variables': {
                    'SECRET_ID': self.secret,
                    'HOST': self.endpoint,
                    'AWS_ACCESS_KEY_ID': 'testing',
                    'AWS_SECRET_ACCESS_KEY': 'testing',
                    'AWS_SECURITY_TOKEN': 'testing',
                    'AWS_SESSION_TOKEN': 'testing'
                }
            })
        in_data = {"msg": "This is a test!"}
        success_result = conn.invoke(
            FunctionName=function_name, InvocationType="Event", Payload=json.dumps(in_data)
        )
        res = json.loads(success_result["Payload"].read().decode("utf-8"))
        self.assertDictEqual(res, {'username': 'postgres', 'password': 'test1234'})

    def tearDown(self):
        """Delete resources after each test"""

        # Delete database
        rds_client = boto3.client("rds", endpoint_url=endpoint_url)
        rds_client.delete_db_instance(DBInstanceIdentifier='testdb', SkipFinalSnapshot=True)
        # Delete the secret
        secret_client = boto3.client("secretsmanager", endpoint_url=endpoint_url)
        secret_client.delete_secret(SecretId=self.secret, ForceDeleteWithoutRecovery=True)

if __name__ == '__main__':
    unittest.main()