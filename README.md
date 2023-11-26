# An example of AWS Lambdas with Python, Terraform and Unittests

## Prerequisites and Assumptions

- The Terraform has been tested assuming that there are credentials at `~/.aws` that will include all the needed permissions
- The VPC for this assignment is the `default` VPC
- The security group that Terraform uses is also the `default`
- Python3.10 is used both locally and for the lambda function in AWS

## Lambda function

In this example the lambda function gets the secret created by the database and will query the database.
The lambda function is added to the VPC and there is an endpoint from that VPC to the secret manager of the region,
thus the secret is not being transferred through the internet, but only internally, in the AWS network.

## What is included

Terraform will set up:
- The default VPC and security group, which will NOT get overwritten
- Add the public IP of the local machine to the ingress of the default security group, for accessing the database
- VPC Interface Enpoint to allow access to secret manager without internet connection 
- RDS PostgreSQL database in a very small machine, internet facing.
- Describe and upload the lambda function
- IAM policy and roles for the lambda function
- Adds lambda to the VPC

Terraform uses `eu-central-1` as `aws_region`. This can be set in `variables.tf` or overwritten by a `TF_VAR`. 

## How to run the project

The code of the lambda function along with the libraries is zipped to `my_deployment_package.zip` at the main folder of the project.
To create the infrastructure:

`terraform init`
`terraform plan`
`terraform apply`

## Future improvements

IAM policies are very relaxed. Localstack PRO version can be used to ease the testing of this project.
Another lambda function can be added to rotate the secret of the database.
A proxy between the database and the lambda function, which will simplify connection management and make applications more resilient to database failures. 

## Testing

Testing requires some more libraries that are included in the `my_deployment_package.zip` to save some space uploading the file to AWS.
Install the libraries from `requirements.txt`. It is strongly recommended to use a virtual environment.
Moto is being used to mock the AWS services. Before running the tests make sure that you also have installed:

`pip install moto[server]`

1. Moto will run the lambda function inside a docker container. To access the mocked `secretsmanager` service locally and inside the docker set the docker network as "host mode": `export MOTO_DOCKER_NETWORK_MODE='host moto_server'`
2. Start the moto server: `moto_server -H 0.0.0.0`
3. Run the tests: `python3 function/lambda_function.test.py`

More info:
`http://docs.getmoto.org/en/latest/docs/server_mode.html#run-using-docker`
Examples of Unittests lambda functions with moto:
`https://github.com/getmoto/moto/tree/29d01c35bc06d5a8462487d614e33b9e8416ba96/tests/test_awslambda`
