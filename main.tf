# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
  # shared_credentials_files = ["$HOME/.aws/credentials"]
  # profile = "another-personal"
}
#Retrieve the list of AZs in the current AWS region
data "aws_availability_zones" "available" {}
data "aws_region" "current" {}

data "aws_subnets" "example" {
  filter {
    name   = "vpc-id"
    values = [aws_default_vpc.default.id]
  }
}
# Get Public IP of this machine
data "http" "ip" {
  url = "https://ifconfig.me/ip"
}

# Get the default VPC
# (Terraform does not create this resource but adopts it)
resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

# Set up the default security group 
# (Terraform does not create this resource but adopts it)
resource "aws_default_security_group" "default_sg" {
  vpc_id = aws_default_vpc.default.id
  # Allow traffic inside the VPC
  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }
  # Allow Postgres traffic from the IP of this machine
  ingress {
    protocol    = "TCP"
    from_port   = 5432
    to_port     = 5432
    cidr_blocks = ["${data.http.ip.response_body}/32"]
  }
  # Allow traffice from VPC to the Internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# VPC Interface Enpoint to allow access to secret manager without internet connection 
resource "aws_vpc_endpoint" "secretsmanager_endpoint" {
  vpc_id              = aws_default_vpc.default.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  private_dns_enabled = true
  vpc_endpoint_type   = "Interface"
  ip_address_type     = "ipv4"
  subnet_ids          = tolist(data.aws_subnets.example.ids)
}

# Create the RDS Postgres DB
resource "aws_db_instance" "postgres" {
  allocated_storage           = 10
  db_name                     = "mydb"
  engine                      = "postgres"
  engine_version              = "15.4"
  instance_class              = "db.t3.micro"
  manage_master_user_password = true
  username                    = "postgres"
  parameter_group_name        = "default.postgres15"
  publicly_accessible         = true
  skip_final_snapshot         = true
}

# Describe the IAM poilicy for the lambda function 
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}
# Create the role
resource "aws_iam_role" "role_for_lambda" {
  name               = "role_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Describe the IAM policy for the lambda function 
data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid    = "AllowLambdaVPC"
    effect = "Allow"
    actions = ["ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeInstances",
    "ec2:AttachNetworkInterface"]
    resources = ["*"]
  }
  statement {
    sid    = "AllowRDS"
    effect = "Allow"
    actions = [
      "rds:*"
    ]
    resources = ["*"]
  }
  statement {
    sid    = "AllowLambda"
    effect = "Allow"
    actions = ["cloudformation:DescribeStacks",
      "cloudformation:ListStackResources",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "secretsmanager:*",
      "kms:ListAliases",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:ListRoles",
      "lambda:*",
      "logs:DescribeLogGroups",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "states:DescribeStateMachine",
      "states:ListStateMachines",
      "tag:GetResources",
      "xray:GetTraceSummaries",
      "xray:BatchGetTraces",
      "application-autoscaling:DeleteScalingPolicy",
      "application-autoscaling:DeregisterScalableTarget",
      "application-autoscaling:DescribeScalableTargets",
      "application-autoscaling:DescribeScalingActivities",
      "application-autoscaling:DescribeScalingPolicies",
      "application-autoscaling:PutScalingPolicy",
      "application-autoscaling:RegisterScalableTarget",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:ListMetrics",
    "cloudwatch:GetMetricData"]
    resources = ["*"]
  }
}
# Create the policy
resource "aws_iam_policy" "policy_for_lambda" {
  name   = "policy_for_lambda"
  path   = "/"
  policy = data.aws_iam_policy_document.lambda_policy.json
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.role_for_lambda.name
  policy_arn = aws_iam_policy.policy_for_lambda.arn
}

# Upload and set up the lambda function
resource "aws_lambda_function" "test_lambda" {
  # If the file is not in the current working directory you will need to include a
  # path.module in the filename.
  filename         = "my_deployment_package.zip"
  function_name    = "lambda_sm_rds"
  role             = aws_iam_role.role_for_lambda.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = filebase64sha256("my_deployment_package.zip")
  runtime          = "python3.10"
  timeout          = 10

  vpc_config {
    subnet_ids         = tolist(data.aws_subnets.example.ids)
    security_group_ids = [aws_default_security_group.default_sg.id]
  }

  environment {
    variables = {
      SECRET_ID = aws_db_instance.postgres.master_user_secret[0]["secret_arn"],
      HOST      = aws_db_instance.postgres.address
    }
  }
}
