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
# from aws_xray_sdk.core import xray_recorder
from unittest.mock import MagicMock, patch

logger = logging.getLogger()
# xray_recorder.configure(
#   context_missing='LOG_ERROR'
# )

# xray_recorder.begin_segment('test_init')
# function = __import__('lambda_function')
# handler = function.lambda_handler
# xray_recorder.end_segment()


def _process_lambda(func_str):
    zip_output = io.BytesIO()
    zip_file = zipfile.ZipFile(zip_output, "w", zipfile.ZIP_DEFLATED)
    zip_file.writestr("lambda_function.py", func_str)
    zip_file.close()
    zip_output.seek(0)
    return zip_output.read()


def get_test_zip_file2():
    pfunc = """
import os
import sys
import logging
import boto3
# import psycopg2
import json
# from aws_xray_sdk.core import patch_all
# from botocore.exceptions import ClientError
# Set up logger and aws xray
logger = logging.getLogger()
logger.setLevel(logging.INFO)
# patch_all()

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
os.environ['AWS_ACCESS_KEY_ID'] = 'testing'
os.environ['AWS_SECRET_ACCESS_KEY'] = 'testing'
os.environ['AWS_SECURITY_TOKEN'] = 'testing'
os.environ['AWS_SESSION_TOKEN'] = 'testing'


params = {'SecretId': SECRET_ID, 'VersionId': VERSION_ID, 'VersionStage': VERSION_STAGE}
secrets_not_none_params = {k:v for k, v in params.items() if v is not None}

def lambda_handler(event, context):

    AWS_ACCESS_KEY_ID = os.environ['AWS_ACCESS_KEY_ID']
    AWS_SECRET_ACCESS_KEY = os.environ['AWS_SECRET_ACCESS_KEY']
    AWS_SECURITY_TOKEN = os.environ['AWS_SECURITY_TOKEN']
    AWS_SESSION_TOKEN = os.environ['AWS_SESSION_TOKEN']
    
    full_url = os.environ.get("MOTO_HTTP_ENDPOINT")
    # full_url = 'http://192.168.1.84:5000'
    
    secrets = boto3.client('secretsmanager', endpoint_url=full_url)
    # response = secrets.create_secret(Name='test', SecretString='test')
    secret = secrets.list_secrets().get('SecretList')
    secret_response = secrets.get_secret_value(SecretId='test2')


    return f"This is the secret {secret_response.get('SecretString')}"
    # return secret
"""
    return _process_lambda(pfunc)



@moto.mock_rds
@moto.mock_secretsmanager
@moto.mock_lambda
# @moto.mock_lambda_simple
@moto.mock_iam
class TestFunction(unittest.TestCase):

    def get_role_name(self):
        with moto.mock_iam():
            iam = boto3.client("iam")
            return iam.create_role(
                RoleName="role",
                AssumeRolePolicyDocument="some policy",
                Path="/test/",
            )["Role"]["Arn"]


     # Test Setup
    def setUp(self) -> None:
        """
        Create mocked resources for use during tests
        """
        # Mock RDS postgresql
        rds_client = boto3.client('rds')
        res = rds_client.create_db_instance(DBInstanceIdentifier='testdb', DBInstanceClass='db.t3.micro',
                                     Engine='postgres', EngineVersion='15.4',
                                     ManageMasterUserPassword=True, MasterUsername='postgres')
        # print(res)
        # logger.info(res)
        self.endpoint = res['DBInstance']['Endpoint']['Address']

        secrets_client = boto3.client('secretsmanager', endpoint_url='http://127.0.0.1:5000')
        # response = secrets_client.create_secret(Name='test2', SecretString='test')
        # logger.warning(response)
        # self.secret = 'test2'
        self.secret = secrets_client.list_secrets().get('SecretList')[0].get('ARN')
        logger.warning(self.secret)

        # Mock environment
        os.environ["HOST"] = self.endpoint
        os.environ["SECRET_ID"] = self.secret
        os.environ['AWS_ACCESS_KEY_ID'] = 'testing'
        os.environ['AWS_SECRET_ACCESS_KEY'] = 'testing'
        os.environ['AWS_SECURITY_TOKEN'] = 'testing'
        os.environ['AWS_SESSION_TOKEN'] = 'testing'

    def test_function(self):
        pass
        # event = jsonpickle.decode(ba)

        # result = handler(event="", context="")

        # xray_recorder.begin_segment('test_function')
        # file = open('event.json', 'rb')
        # try:
        #     ba = bytearray(file.read())
        #     event = jsonpickle.decode(ba)
        #     # logger.warning('## EVENT')
        #     # logger.warning(jsonpickle.encode(event))
        #     context = {'requestid' : '1234'}
        #     result = handler(event, context)
        #     self.assertRegex(str(result), '[(1,)]', 'Should match')
        # except Exception as e:
        #     logger.error(str(e))
        #     sys.exit(1)
        # finally:
        #     file.close()
        # file.close()
        # xray_recorder.end_segment()

    def test_invoke_requestresponse_function(self):
        conn = boto3.client("lambda")
        function_name = str(uuid4())[0:6]
        file1 = open("my_deployment_package.zip", "rb")

        logging.warning(self.secret)

        fxn = conn.create_function(
            FunctionName=function_name,
            Runtime="python3.10",
            Role=self.get_role_name(),
            Handler="lambda_function.lambda_handler",
            Code={"ZipFile": get_test_zip_file2()},
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
        file1.close()
        in_data = {"msg": "So long and thanks for all the fish"}
        success_result = conn.invoke(
            FunctionName=function_name, InvocationType="Event", Payload=json.dumps(in_data)
        )
        res = json.loads(success_result["Payload"].read().decode("utf-8"))
        logging.warning(res)


    def tearDown(self) -> None:

        # Delete database
        rds_client = boto3.client("rds")
        rds_client.delete_db_instance(DBInstanceIdentifier='testdb', SkipFinalSnapshot=True)

if __name__ == '__main__':
    unittest.main()