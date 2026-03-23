resource "aws_appautoscaling_target" "ecs_service" {
  count = var.enable_autoscaling && var.task_count_max != var.task_count_min ? 1 : 0

  max_capacity       = var.task_count_max
  min_capacity       = var.task_count_min
  resource_id        = "service/${var.ecs_cluster_name}/${var.ecs_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CPU-based autoscaling
resource "aws_appautoscaling_policy" "cpu_targettracking" {
  count = var.enable_autoscaling && var.enable_cpu_scaling && var.task_count_max != var.task_count_min ? 1 : 0

  name               = "${var.ecs_service_name}-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value = var.autoscaling_cpu_target

    scale_in_cooldown  = var.autoscaling_in_cooldown
    scale_out_cooldown = var.autoscaling_out_cooldown
  }
}

# Memory-based autoscaling
resource "aws_appautoscaling_policy" "memory_targettracking" {
  count = var.enable_autoscaling && var.enable_memory_scaling && var.task_count_max != var.task_count_min ? 1 : 0

  name               = "${var.ecs_service_name}-memory-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value = var.autoscaling_memory_target

    scale_in_cooldown  = var.autoscaling_in_cooldown
    scale_out_cooldown = var.autoscaling_out_cooldown
  }
}

# Request count-based autoscaling (requires enable_external_lb and external_lb_arn_suffix or request_count_target_group_resource_label)
locals {
  request_count_resource_label = var.external_lb_arn_suffix != null && var.enable_external_lb ? "${var.external_lb_arn_suffix}/targetgroup/${substr("${var.ecs_service_name}-ext", 0, 32)}/${substr(aws_lb_target_group.external_tg[0].arn, -17, 17)}" : var.request_count_target_group_resource_label
}

resource "aws_appautoscaling_policy" "request_count_targettracking" {
  count = var.enable_autoscaling && var.enable_request_count_scaling && var.enable_external_lb && var.task_count_max != var.task_count_min && local.request_count_resource_label != "" ? 1 : 0

  name               = "${var.ecs_service_name}-request-count-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = local.request_count_resource_label
    }

    target_value = var.autoscaling_request_count_target

    scale_in_cooldown  = var.autoscaling_in_cooldown
    scale_out_cooldown = var.autoscaling_out_cooldown
  }
}
