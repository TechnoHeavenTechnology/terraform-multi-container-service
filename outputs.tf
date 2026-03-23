output "external_target_group_arn" {
  description = "ARN of the external ALB target group (null when enable_external_lb=false)"
  value       = try(aws_lb_target_group.external_tg[0].arn, null)
}

output "security_group_id" {
  description = "ID of the task security group"
  value       = aws_security_group.ecs_tasks.id
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.fargate_service.name
}

output "container_port" {
  description = "Port exposed by the primary container"
  value       = local.effective_primary_container_port
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for the ECS service"
  value       = aws_cloudwatch_log_group.ecs_service_logs.name
}
