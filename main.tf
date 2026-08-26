locals {
  # ── Find primary and lb_target containers ──
  primary_container = [for c in var.containers : c if c.is_primary][0]
  lb_target_container = (
    length([for c in var.containers : c if c.is_lb_target]) > 0
    ? [for c in var.containers : c if c.is_lb_target][0]
    : local.primary_container
  )

  # ── Effective ALB values (used by lb.tf, sg.tf, service load_balancer block) ──
  effective_alb_container_name = local.lb_target_container.name
  effective_alb_container_port = local.lb_target_container.port

  # ── Effective primary port (used by service_connect) ──
  effective_primary_container_name = local.primary_container.name
  effective_primary_container_port = local.primary_container.port

  # ── Transform each container to ECS JSON format ──
  container_definitions = [
    for c in var.containers : {
      name       = c.name
      image      = c.image
      essential  = c.essential
      entryPoint = c.entrypoint != null ? c.entrypoint : null
      command    = c.command != null ? c.command : null

      portMappings = [
        {
          containerPort = c.port
          hostPort      = c.port
          protocol      = "tcp"
          name          = "${c.name}-port"
          appProtocol   = "http"
        }
      ]

      healthCheck = c.health_check != null ? {
        command     = ["CMD-SHELL", c.health_check.command]
        interval    = c.health_check.interval
        timeout     = c.health_check.timeout
        retries     = c.health_check.retries
        startPeriod = c.health_check.startPeriod
      } : null

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_service_logs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = c.name
        }
      }

      environment = [for k, v in c.environment : { name = k, value = v }]
      secrets     = [for k, v in c.secrets : { name = k, valueFrom = v }]

      dependsOn = length(c.depends_on_containers) > 0 ? [
        for dep in c.depends_on_containers : {
          containerName = dep.container
          condition     = dep.condition
        }
      ] : null
    }
  ]
}

resource "aws_ecs_task_definition" "fargate_task_definition" {
  family                   = var.ecs_service_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = var.existing_task_role_arn != null ? var.existing_task_role_arn : aws_iam_role.new_task[0].arn

  container_definitions = jsonencode(local.container_definitions)

  dynamic "volume" {
    for_each = var.volumes != null && length(var.volumes) > 0 ? var.volumes : []
    content {
      name = volume.value.name

      dynamic "efs_volume_configuration" {
        for_each = lookup(volume.value, "efs_volume_configuration", null) != null ? [volume.value.efs_volume_configuration] : []
        content {
          file_system_id     = efs_volume_configuration.value.file_system_id
          root_directory     = lookup(efs_volume_configuration.value, "root_directory", null)
          transit_encryption = lookup(efs_volume_configuration.value, "transit_encryption", null)
        }
      }
    }
  }

  tags = merge(
    var.tags,
    {
      name        = var.ecs_service_name
      application = var.application
      environment = var.environment
    }
  )
}

resource "aws_ecs_service" "fargate_service" {
  name                              = var.ecs_service_name
  cluster                           = var.ecs_cluster_id
  task_definition                   = aws_ecs_task_definition.fargate_task_definition.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = var.health_check_grace_period
  enable_execute_command            = var.enable_execute_command
  network_configuration {
    subnets          = var.private_subnet_ids
    assign_public_ip = var.assign_public_ip
    security_groups  = [aws_security_group.ecs_tasks.id]
  }

  dynamic "load_balancer" {
    for_each = var.enable_external_lb ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.external_tg[0].arn
      container_name   = local.effective_alb_container_name
      container_port   = local.effective_alb_container_port
    }
  }

  dynamic "service_registries" {
    for_each = var.enable_service_discovery ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.service_sd[0].arn
    }
  }

  dynamic "service_connect_configuration" {
    for_each = var.enable_service_connect ? [1] : []
    content {
      enabled   = true
      namespace = var.service_connect_namespace

      service {
        client_alias {
          port     = var.service_connect_port
          dns_name = var.ecs_service_name
        }
        port_name      = "${local.effective_primary_container_name}-port"
        discovery_name = var.ecs_service_name
      }

      log_configuration {
        log_driver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_service_logs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "${var.ecs_service_name}-connect"
        }
      }
    }
  }

  propagate_tags = "SERVICE"
  tags = merge(
    var.tags,
    {
      name        = var.ecs_service_name
      application = var.application
      environment = var.environment
    }
  )
}

# Service Discovery
resource "aws_service_discovery_service" "service_sd" {
  count = var.enable_service_discovery ? 1 : 0

  name = var.ecs_service_name

  dns_config {
    namespace_id = var.service_discovery_namespace_id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  # An all-default empty block here (`health_check_custom_config {}`) gets
  # silently dropped by the provider's own GetOk-based check - Terraform
  # plans to create it, but the API call never actually includes it,
  # leaving a service with NO health_check_custom_config at all. Confirmed
  # live: next plan then wants to replace the "just created" service to
  # add the very block that was already declared, forever. An explicit
  # non-zero attribute makes the block register as genuinely set.
  health_check_custom_config {
    failure_threshold = 1
  }

  tags = merge(
    var.tags,
    {
      name        = var.ecs_service_name
      application = var.application
      environment = var.environment
    }
  )
}
