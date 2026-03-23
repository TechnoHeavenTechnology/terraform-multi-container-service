# CloudWatch Log Group for container logs
resource "aws_cloudwatch_log_group" "ecs_service_logs" {
  name              = "/ecs/${var.application}/${var.ecs_service_name}/${var.environment}"
  retention_in_days = var.cloudwatch_log_retention
  kms_key_id        = var.kms_key_arn != "" ? var.kms_key_arn : null

  tags = merge(
    var.tags,
    {
      Name = "${var.ecs_service_name}-logs"
    }
  )
}

# CloudWatch Alarm for high CPU utilization
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.enable_alarms && var.enable_cpu_alarm ? 1 : 0

  alarm_name          = "${var.ecs_service_name}-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_scale_up_threshold
  alarm_description   = "This alarm monitors for high CPU utilization of the ${var.ecs_service_name} service"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  tags = var.tags
}

# CloudWatch Alarm for memory utilization
resource "aws_cloudwatch_metric_alarm" "memory_high" {
  count = var.enable_alarms && var.enable_memory_alarm ? 1 : 0

  alarm_name          = "${var.ecs_service_name}-memory-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = var.memory_scale_up_threshold
  alarm_description   = "This alarm monitors for high memory utilization of the ${var.ecs_service_name} service"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  tags = var.tags
}

# Basic health alarms
resource "aws_cloudwatch_metric_alarm" "running_tasks" {
  count = var.enable_alarms ? 1 : 0

  alarm_name        = "${var.ecs_service_name}-running-tasks"
  alarm_description = "Number of running tasks is less than minimum configured."

  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "SampleCount"
  threshold           = var.task_count_min
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}
