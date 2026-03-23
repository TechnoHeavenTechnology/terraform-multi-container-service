# Target group - created only when enable_external_lb. ALB listener rules are created in root (e.g. lb_rules.tf).
resource "aws_lb_target_group" "external_tg" {
  count       = var.enable_external_lb ? 1 : 0
  name_prefix = substr("${var.ecs_service_name}-", 0, 6)
  port        = local.effective_alb_container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    matcher             = var.health_check_matcher
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.ecs_service_name}-ext"
    }
  )

  lifecycle {
    create_before_destroy = true
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = var.target_group_stickiness_duration
    enabled         = var.target_group_stickiness_enabled
  }
}
