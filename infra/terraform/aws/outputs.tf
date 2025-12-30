# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public Subnet IDs"
  value = [
    aws_subnet.public_1a.id,
    aws_subnet.public_1c.id
  ]
}

# RDS Outputs
output "rds_endpoint" {
  description = "RDS Endpoint"
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "RDS Address (hostname only)"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "RDS Port"
  value       = aws_db_instance.main.port
}

# ECR Outputs
output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = aws_ecr_repository.demo_api.repository_url
}

output "ecr_repository_arn" {
  description = "ECR Repository ARN"
  value       = aws_ecr_repository.demo_api.arn
}

# ALB Outputs
output "alb_dns_name" {
  description = "ALB DNS Name"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB Zone ID (for Route53)"
  value       = aws_lb.main.zone_id
}

output "target_group_arns" {
  description = "Target Group ARNs (per tenant)"
  value = {
    for k, tg in aws_lb_target_group.demo_api : k => tg.arn
  }
}

# ECS Outputs
output "ecs_cluster_name" {
  description = "ECS Cluster Name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ECS Cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_service_names" {
  description = "ECS Service Names (per tenant)"
  value = {
    for k, svc in aws_ecs_service.demo_api : k => svc.name
  }
}

# IAM Outputs
output "ecs_task_role_arn" {
  description = "ECS Task Role ARN"
  value       = aws_iam_role.ecs_task_role.arn
}

output "ecs_execution_role_arn" {
  description = "ECS Execution Role ARN"
  value       = aws_iam_role.ecs_execution_role.arn
}
