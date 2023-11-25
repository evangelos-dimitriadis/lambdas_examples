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
output "ip" {
  description = "Public IP of this machine"
  value       = data.http.ip.response_body
}
