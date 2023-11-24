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

  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/32"]
  }

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
  username                    = "foo"
  parameter_group_name        = "default.postgres15"
  publicly_accessible         = true
}

# data "aws_db_instance" "db" {}

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
  filename      = "my_deployment_package.zip"
  function_name = "lambda_sm_rds"
  role          = aws_iam_role.role_for_lambda.arn
  handler       = "lambda_function.lambda_handler"
  # source_code_hash = data.archive_file.lambda.output_base64sha256
  runtime = "python3.10"
  timeout = 10

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







# resource "aws_iam_policy" "policy" {
#   name        = "data_bucket_policy"
#   description = "Deny access to my bucket"
#   policy = jsonencode({
#     "Version" : "2012-10-17",
#     "Statement" : [
#       {
#         "Effect" : "Allow",
#         "Action" : [
#           "s3:Get*",
#           "s3:List*"
#         ],
#         "Resource" : "${data.aws_s3_bucket.data_bucket.arn}"
#       }
#     ]
#   })
# }

# #Local vars
# locals {
#   team        = "api_management_dev"
#   application = "api"
#   server_name = "ec2-${var.environment}-api-${var.variables_sub_az}"
# }

# locals {
#   service_name = "Automation"
#   app_team     = "Cloud Team"
#   createdby    = "terraform"
# }

# locals {
#   # Common tags to be assigned to all resources
#   common_tags = {
#     Name      = join("-", [local.application, data.aws_region.current.name, local.createdby])
#     Owner     = local.team
#     App       = local.application
#     Service   = local.service_name
#     AppTeam   = local.app_team
#     CreatedBy = local.createdby
#   }
# }

# #Define the VPC
# resource "aws_vpc" "vpc" {
#   cidr_block = var.vpc_cidr
#   tags = {
#     Name        = var.vpc_name
#     Environment = var.environment
#     Terraform   = "true"
#     Region      = data.aws_region.current.name
#   }
# }
# #Deploy the private subnets
# resource "aws_subnet" "private_subnets" {
#   for_each   = var.private_subnets
#   vpc_id     = aws_vpc.vpc.id
#   cidr_block = cidrsubnet(var.vpc_cidr, 8, each.value)
#   availability_zone = tolist(data.aws_availability_zones.available.names)[
#   each.value]
#   tags = {
#     Name      = each.key
#     Terraform = "true"
#   }
# }
# #Deploy the public subnets
# resource "aws_subnet" "public_subnets" {
#   for_each   = var.public_subnets
#   vpc_id     = aws_vpc.vpc.id
#   cidr_block = cidrsubnet(var.vpc_cidr, 8, each.value + 100)
#   availability_zone = tolist(data.aws_availability_zones.available.
#   names)[each.value]
#   map_public_ip_on_launch = true
#   tags = {
#     Name      = each.key
#     Terraform = "true"
#   }
# }
# #Create route tables for public and private subnets
# resource "aws_route_table" "public_route_table" {
#   vpc_id = aws_vpc.vpc.id
#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_internet_gateway.internet_gateway.id
#     #nat_gateway_id = aws_nat_gateway.nat_gateway.id
#   }
#   tags = {
#     Name      = "demo_public_rtb"
#     Terraform = "true"
#   }
# }
# resource "aws_route_table" "private_route_table" {
#   vpc_id = aws_vpc.vpc.id
#   route {
#     cidr_block = "0.0.0.0/0"
#     # gateway_id = aws_internet_gateway.internet_gateway.id
#     nat_gateway_id = aws_nat_gateway.nat_gateway.id
#   }
#   tags = {
#     Name      = "demo_private_rtb"
#     Terraform = "true"
#   }
# }
# #Create route table associations
# resource "aws_route_table_association" "public" {
#   depends_on     = [aws_subnet.public_subnets]
#   route_table_id = aws_route_table.public_route_table.id
#   for_each       = aws_subnet.public_subnets
#   subnet_id      = each.value.id
# }
# resource "aws_route_table_association" "private" {
#   depends_on     = [aws_subnet.private_subnets]
#   route_table_id = aws_route_table.private_route_table.id
#   for_each       = aws_subnet.private_subnets
#   subnet_id      = each.value.id
# }
# #Create Internet Gateway
# resource "aws_internet_gateway" "internet_gateway" {
#   vpc_id = aws_vpc.vpc.id
#   tags = {
#     Name = "demo_igw"
#   }
# }
# #Create EIP for NAT Gateway
# resource "aws_eip" "nat_gateway_eip" {
#   domain     = "vpc"
#   depends_on = [aws_internet_gateway.internet_gateway]
#   tags = {
#     Name = "demo_igw_eip"
#   }
# }
# #Create NAT Gateway
# resource "aws_nat_gateway" "nat_gateway" {
#   depends_on    = [aws_subnet.public_subnets]
#   allocation_id = aws_eip.nat_gateway_eip.id
#   subnet_id     = aws_subnet.public_subnets["public_subnet_1"].id
#   tags = {
#     Name = "demo_nat_gateway"
#   }
# }
# # Terraform Data Block - To Lookup Latest Ubuntu 20.04 AMI Image
# data "aws_ami" "ubuntu" {
#   most_recent = true
#   filter {
#     name   = "name"
#     values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
#   }
#   filter {
#     name   = "virtualization-type"
#     values = ["hvm"]
#   }
#   owners = ["099720109477"]
# }

# # Create an SSH key
# resource "tls_private_key" "generated" {
#   algorithm = "ED25519"
# }
# # resource "local_file" "private_key_pem" {
# #   content  = tls_private_key.generated.private_key_pem
# #   filename = "MyAWSKey.pem"
# # }
# # Add it to aws
# resource "aws_key_pair" "generated" {
#   key_name   = "MyAWSKey${var.environment}"
#   public_key = tls_private_key.generated.public_key_openssh
#   lifecycle {
#     ignore_changes = [key_name]
#   }
# }

# # Security Groups
# resource "aws_security_group" "ingress-ssh" {
#   name   = "allow-all-ssh"
#   vpc_id = aws_vpc.vpc.id
#   ingress {
#     cidr_blocks = [
#       "0.0.0.0/0"
#     ]
#     from_port = 22
#     to_port   = 22
#     protocol  = "tcp"
#   }
#   // Terraform removes the default rule
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# # Create Security Group - Web Traffic
# resource "aws_security_group" "vpc-web" {
#   name        = "vpc-web-${terraform.workspace}"
#   vpc_id      = aws_vpc.vpc.id
#   description = "Web Traffic"
#   ingress {
#     description = "Allow Port 80"
#     from_port   = 80
#     to_port     = 80
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#   ingress {
#     description = "Allow Port 443"
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#   egress {
#     description = "Allow all ip and ports outbound"
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }
# resource "aws_security_group" "vpc-ping" {
#   name        = "vpc-ping"
#   vpc_id      = aws_vpc.vpc.id
#   description = "ICMP for Ping Access"
#   ingress {
#     description = "Allow ICMP Traffic"
#     from_port   = -1
#     to_port     = -1
#     protocol    = "icmp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#   egress {
#     description = "Allow all ip and ports outboun"
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# resource "aws_security_group" "main" {
#   name   = "core-sg"
#   vpc_id = aws_vpc.vpc.id

#   dynamic "ingress" {
#     for_each = var.web_ingress
#     content {
#       description = ingress.value.description
#       from_port   = ingress.value.port
#       to_port     = ingress.value.port
#       protocol    = ingress.value.protocol
#       cidr_blocks = ingress.value.cidr_blocks
#     }
#   }
# }


# module "server" {
#   source    = "./modules/server"
#   ami       = data.aws_ami.ubuntu.id
#   subnet_id = aws_subnet.public_subnets["public_subnet_3"].id
#   security_groups = [
#     aws_security_group.vpc-ping.id,
#     aws_security_group.ingress-ssh.id,
#     aws_security_group.vpc-web.id
#   ]
# }


# module "web_server" {
#   source      = "./modules/web_server"
#   ami         = data.aws_ami.ubuntu.id
#   subnet_id   = aws_subnet.public_subnets["public_subnet_1"].id
#   key_name    = aws_key_pair.generated.key_name
#   user        = "ubuntu"
#   private_key = tls_private_key.generated.private_key_pem
#   security_groups = [
#     aws_security_group.vpc-ping.id,
#     aws_security_group.ingress-ssh.id,
#     aws_security_group.vpc-web.id
#   ]
#   tags = local.common_tags
# }


# module "s3-bucket" {
#   source  = "terraform-aws-modules/s3-bucket/aws"
#   version = "3.11.0"
# }
# output "s3_bucket_name" {
#   value = module.s3-bucket.s3_bucket_bucket_domain_name
# }

# resource "aws_subnet" "list_subnet" {
#   for_each          = var.env
#   vpc_id            = aws_vpc.vpc.id
#   cidr_block        = each.value.ip
#   availability_zone = each.value.az
#   tags = {
#     Name = each.key
#   }
# }


# output "data-bucket-arn" {
#   value = data.aws_s3_bucket.data_bucket.arn
# }
# output "data-bucket-domain-name" {
#   value = data.aws_s3_bucket.data_bucket.bucket_domain_name
# }
# output "data-bucket-region" {
#   value = "The ${data.aws_s3_bucket.data_bucket.id} bucket is located in ${data.aws_s3_bucket.data_bucket.region}"
# }

# module "vpc" {
#   source             = "terraform-aws-modules/vpc/aws"
#   name               = "aws_vpc"
#   cidr               = "10.0.0.0/16"
#   azs                = ["us-east-1a", "us-east-1b", "us-east-1c"]
#   private_subnets    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
#   public_subnets     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
#   enable_nat_gateway = true
#   enable_vpn_gateway = true
#   tags = {
#     Name        = "VPC from Module"
#     Terraform   = "true"
#     Environment = "dev"
#   }
# }


# module "autoscaling" {
#   source  = "terraform-aws-modules/autoscaling/aws"
#   version = "6.10.0"
#   # Autoscaling group
#   name = "myasg"
#   vpc_zone_identifier = [aws_subnet.private_subnets["private_subnet_1"].id, aws_subnet.private_subnets["private_subnet_2"].id,
#   aws_subnet.private_subnets["private_subnet_3"].id]
#   min_size         = 0
#   max_size         = 1
#   desired_capacity = 1
#   # Launch template
#   create_launch_template = true
#   image_id               = data.aws_ami.ubuntu.id
#   instance_type          = "t3.micro"
#   tags = {
#     Name = "Web EC2 Server 2"
#   }
# }

# ----------------------------------------------------------------------
# resource "aws_subnet" "variables-subnet" {
#   vpc_id                  = aws_vpc.vpc.id
#   cidr_block              = var.variables_sub_cidr
#   availability_zone       = var.variables_sub_az
#   map_public_ip_on_launch = var.variables_sub_auto_ip
#   tags = {
#     Name      = "sub-variables-${var.variables_sub_az}"
#     Terraform = "true"
#   }
# }

