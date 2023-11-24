output "hello-world" {
  description = "Print a Hello World text output"
  value       = "Hello World"
}
output "vpc_id" {
  description = "Output the ID for the primary VPC"
  value       = aws_default_vpc.default.id
}

output "aws_availability_zones" {
  description = "Subnets"
  value       = data.aws_availability_zones.available.id
}

output "secret" {
  description = "The id of the DB key"
  value       = aws_db_instance.postgres.master_user_secret[0]["secret_arn"]
}

output "db_host" {
  description = "The host of the DB"
  value       = aws_db_instance.postgres.address
}

# output "iam_role" {
#   value = aws_iam_policy.lambda_iam.arn
# }

# output "vpc_information" {
#   description = "VPC Information about Environment"
#   value       = "VPC has an ID of ${aws_vpc.vpc.id}"
# }
# output "public_ip" {
#   value = module.server.public_ip
# }
# output "asg_group_size" {
#   value = module.autoscaling.autoscaling_group_max_size
# }
# output "so_secret" {
#   value     = var.so_secret
#   sensitive = true
# }
