resource "aws_security_group" "ecs_tasks" {
  name        = "${var.ecs_service_name}-ecs-tasks-sg"
  description = "Security group for ECS tasks in the ${var.ecs_service_name} service"
  vpc_id      = var.vpc_id

  # No inline egress — rules created via aws_vpc_security_group_egress_rule (supports tags, no default allow-all)
  tags = merge(
    var.tags,
    { Name = "${var.ecs_service_name}-ecs-tasks-sg" }
  )
}

resource "aws_vpc_security_group_egress_rule" "egress" {
  for_each = {
    for idx, r in local.effective_egress_rules : try(r.tags.Name, r.name, "egress-${idx}") => r
    if(r.security_group_id != null && r.security_group_id != "") || try(length(r.cidr_blocks), 0) > 0 || try(length(r.ipv6_cidr_blocks), 0) > 0 || try(length(r.prefix_list_ids), 0) > 0
  }

  security_group_id = aws_security_group.ecs_tasks.id
  from_port         = lookup(each.value, "protocol", "tcp") == "-1" ? null : lookup(each.value, "from_port", 0)
  to_port           = lookup(each.value, "protocol", "tcp") == "-1" ? null : lookup(each.value, "to_port", 0)
  ip_protocol       = lookup(each.value, "protocol", "tcp")
  description       = lookup(each.value, "description", "Egress rule")

  cidr_ipv4                    = try(length(each.value.prefix_list_ids), 0) > 0 ? null : (try(length(each.value.cidr_blocks), 0) > 0 ? each.value.cidr_blocks[0] : null)
  cidr_ipv6                    = try(length(each.value.prefix_list_ids), 0) > 0 ? null : (try(length(each.value.ipv6_cidr_blocks), 0) > 0 ? each.value.ipv6_cidr_blocks[0] : null)
  prefix_list_id               = try(length(each.value.prefix_list_ids), 0) > 0 ? each.value.prefix_list_ids[0] : null
  referenced_security_group_id = (try(length(each.value.cidr_blocks), 0) > 0 || try(length(each.value.ipv6_cidr_blocks), 0) > 0 || try(length(each.value.prefix_list_ids), 0) > 0) ? null : lookup(each.value, "security_group_id", null)

  # Name tag from caller (sg.tf tags = { Name = "to-xxx" }) — used for rule name in AWS console
  tags = merge(
    var.tags,
    { Name = try(lookup(each.value, "tags", {}).Name, lookup(each.value, "name", "egress-${each.key}")) }
  )
}

locals {
  # When enable_external_lb=true, auto-add ALB ingress rule
  alb_ingress_rule = var.enable_external_lb && var.external_alb_sg_id != null ? [{
    security_group_id = var.external_alb_sg_id
    from_port         = local.effective_alb_container_port
    to_port           = local.effective_alb_container_port
    protocol          = "tcp"
    name              = "from-external-lb"
    description       = "Allow inbound from external ALB"
  }] : []

  effective_ingress_rules = concat(local.alb_ingress_rule, var.ingress_rules)
  effective_egress_rules  = var.egress_rules
}

# Dynamic ingress rules
resource "aws_vpc_security_group_ingress_rule" "ingress" {
  for_each = {
    for idx, rule in local.effective_ingress_rules :
    idx => rule
    if(rule.security_group_id != null && rule.security_group_id != "") || (try(length(rule.cidr_blocks), 0) > 0) || (try(length(rule.ipv6_cidr_blocks), 0) > 0)
  }

  security_group_id = aws_security_group.ecs_tasks.id
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = lookup(each.value, "protocol", "tcp")
  description       = lookup(each.value, "description", "Ingress rule")

  cidr_ipv4                    = try(length(each.value.cidr_blocks), 0) > 0 ? each.value.cidr_blocks[0] : null
  cidr_ipv6                    = try(length(each.value.ipv6_cidr_blocks), 0) > 0 ? each.value.ipv6_cidr_blocks[0] : null
  referenced_security_group_id = (try(length(each.value.cidr_blocks), 0) > 0 || try(length(each.value.ipv6_cidr_blocks), 0) > 0) ? null : lookup(each.value, "security_group_id", null)

  tags = merge(
    var.tags,
    { Name = lookup(each.value, "name", "ingress-${each.key}") }
  )
}

# From self: only when enable_service_connect=true — needed for Service Connect proxy (tasks in same service talk to each other)
resource "aws_vpc_security_group_ingress_rule" "allow_service_connect" {
  count                        = var.enable_service_connect ? 1 : 0
  security_group_id            = aws_security_group.ecs_tasks.id
  referenced_security_group_id = aws_security_group.ecs_tasks.id
  from_port                    = local.effective_primary_container_port
  to_port                      = local.effective_primary_container_port
  ip_protocol                  = "tcp"
  description                  = "Allow inter-service communication for Service Connect"

  tags = merge(
    var.tags,
    { Name = "from-service-connect" }
  )
}
