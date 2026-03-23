# ──────────────────────────────────────────────────────────────────────────────
# Service identity
# ──────────────────────────────────────────────────────────────────────────────
variable "application" {
  description = "Name of the application this service belongs to"
  type        = string
}

variable "ecs_service_name" {
  description = "Name of the ECS service (must be unique within the cluster)"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, test, prod)"
  type        = string
}

variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-southeast-1"
}

variable "iam_role_name_prefix" {
  description = "Prefix for IAM role names (e.g. 'ap' for ap-southeast-1 to avoid conflict with roles in other regions)"
  type        = string
  default     = "ap"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ──────────────────────────────────────────────────────────────────────────────
# Containers
# ──────────────────────────────────────────────────────────────────────────────
variable "containers" {
  description = "List of container definitions. Exactly one must have is_primary=true. At most one can have is_lb_target=true."
  type = list(object({
    name         = string
    image        = string
    port         = number
    essential    = optional(bool, true)
    is_primary   = optional(bool, false)
    is_lb_target = optional(bool, false)
    environment  = optional(map(string), {})
    secrets      = optional(map(string), {})
    health_check = optional(object({
      command     = string
      interval    = optional(number, 30)
      timeout     = optional(number, 5)
      retries     = optional(number, 3)
      startPeriod = optional(number, 60)
    }))
    depends_on_containers = optional(list(object({
      container = string
      condition = string
    })), [])
    command    = optional(list(string))
    entrypoint = optional(list(string))
  }))

  validation {
    condition     = length([for c in var.containers : c if c.is_primary]) == 1
    error_message = "Exactly one container must have is_primary = true."
  }

  validation {
    condition     = length([for c in var.containers : c if c.is_lb_target]) <= 1
    error_message = "At most one container can have is_lb_target = true."
  }

  validation {
    condition     = length(distinct([for c in var.containers : c.name])) == length(var.containers)
    error_message = "All container names must be unique."
  }

  validation {
    condition     = length(distinct([for c in var.containers : c.port])) == length(var.containers)
    error_message = "All container ports must be unique."
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# ECS cluster & networking
# ──────────────────────────────────────────────────────────────────────────────
variable "ecs_cluster_id" {
  description = "The ID of the ECS cluster where the service will be deployed"
  type        = string
}

variable "ecs_cluster_name" {
  description = "The name of the ECS cluster where the service will be deployed"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the ECS tasks"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Whether to assign a public IP to the task"
  type        = bool
  default     = false
}

# ──────────────────────────────────────────────────────────────────────────────
# Task resources
# ──────────────────────────────────────────────────────────────────────────────
variable "task_cpu" {
  description = "CPU units for the task"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memory (MiB) for the task"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of task instances"
  type        = number
  default     = 1
}

variable "volumes" {
  description = "A list of volume blocks that containers in your task may use"
  type        = any
  default     = []
}

# ──────────────────────────────────────────────────────────────────────────────
# Load balancer
# ──────────────────────────────────────────────────────────────────────────────
variable "enable_external_lb" {
  description = "Enable external ALB (target group + load_balancer block). When false, ECS service runs without ALB."
  type        = bool
  default     = false
}

variable "external_alb_sg_id" {
  description = "Security group ID of the external ALB. When enable_external_lb=true, ingress from this SG is auto-added."
  type        = string
  default     = null
}

variable "external_lb_arn_suffix" {
  description = "ALB ARN suffix (e.g. app/alb-name/id) for request count scaling. When set, resource_label is computed from target group."
  type        = string
  default     = null
}

variable "health_check_path" {
  description = "Path for ALB target group health checks"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Interval for health checks (seconds)"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Timeout for health checks (seconds)"
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  type        = number
  description = "The number of consecutive health checks successes required before considering an unhealthy target healthy."
  default     = 3
}

variable "health_check_unhealthy_threshold" {
  type        = number
  description = "The number of consecutive health check failures required before considering the target unhealthy."
  default     = 3
}

variable "health_check_matcher" {
  type        = string
  description = "The HTTP codes to use when checking for a successful response from a target."
  default     = "200-299"
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 120
}

variable "target_group_stickiness_enabled" {
  type        = bool
  description = "Indicates whether target group stickiness is enabled."
  default     = false
}

variable "target_group_stickiness_duration" {
  type        = number
  description = "Target group stickiness duration (seconds)"
  default     = 86400
}

# ──────────────────────────────────────────────────────────────────────────────
# Service Connect & Service Discovery
# ──────────────────────────────────────────────────────────────────────────────
variable "enable_service_connect" {
  description = "Whether to enable service connect for the service"
  type        = bool
  default     = false
}

variable "service_connect_port" {
  description = "Port to use for service connect"
  type        = number
  default     = null
}

variable "service_connect_namespace" {
  description = "ARN of the service connect namespace"
  type        = string
  default     = null
}

variable "enable_service_discovery" {
  description = "Whether to enable service discovery for the service"
  type        = bool
  default     = false
}

variable "service_discovery_namespace_id" {
  description = "ID of the service discovery namespace"
  type        = string
  default     = null
}

# ──────────────────────────────────────────────────────────────────────────────
# Security groups
# ──────────────────────────────────────────────────────────────────────────────
variable "ingress_rules" {
  description = "Dynamic ingress rules. Each rule uses security_group_id OR cidr_blocks OR ipv6_cidr_blocks (exactly one)"
  type = list(object({
    security_group_id = optional(string)
    cidr_blocks       = optional(list(string))
    ipv6_cidr_blocks  = optional(list(string))
    from_port         = number
    to_port           = number
    protocol          = optional(string, "tcp")
    name              = optional(string)
    description       = optional(string)
  }))
  default = []
}

variable "egress_rules" {
  description = "Dynamic egress rules. Each rule uses security_group_id OR cidr_blocks OR ipv6_cidr_blocks OR prefix_list_ids (exactly one). Pass tags = { Name = \"to-xxx\" } for rule name in AWS console."
  type = list(object({
    security_group_id = optional(string)
    cidr_blocks       = optional(list(string))
    ipv6_cidr_blocks  = optional(list(string))
    prefix_list_ids   = optional(list(string))
    from_port         = optional(number)
    to_port           = optional(number)
    protocol          = optional(string, "tcp")
    name              = optional(string)
    description       = optional(string)
    tags              = optional(map(string))
  }))
  default = []
}

# ──────────────────────────────────────────────────────────────────────────────
# IAM
# ──────────────────────────────────────────────────────────────────────────────
variable "existing_task_role_arn" {
  description = "ARN of an existing IAM task role to use instead of creating a new one"
  type        = string
  default     = null
}

variable "execution_role_custom_policy_document" {
  description = "Custom policy document for the ECS task execution role"
  type        = string
  default     = null
}

variable "ssm_resource_path" {
  description = "Path prefix for SSM parameters that the execution role can access"
  type        = string
  default     = null
}

variable "task_role_custom_policy_document" {
  description = "Custom policy document for the ECS task role"
  type        = string
  default     = null
}

variable "task_role_policy_arns" {
  description = "List of IAM policy ARNs to attach to the task role"
  type        = list(string)
  default     = []
}

variable "execution_role_policy_arns" {
  description = "List of IAM policy ARNs to attach to the execution role"
  type        = list(string)
  default     = []
}

variable "task_role_policy_documents" {
  description = "List of inline policy documents to attach to the task role (from root/caller)"
  type = list(object({
    name   = string
    policy = string
  }))
  default = []
}

# ──────────────────────────────────────────────────────────────────────────────
# CloudWatch & Alarms
# ──────────────────────────────────────────────────────────────────────────────
variable "cloudwatch_log_retention" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encrypting SSM Parameters and CloudWatch logs"
  default     = ""
}

variable "enable_alarms" {
  description = "Whether to enable CloudWatch alarms"
  type        = bool
  default     = true
}

variable "enable_cpu_alarm" {
  description = "Enable CloudWatch alarm for high CPU utilization"
  type        = bool
  default     = true
}

variable "enable_memory_alarm" {
  description = "Enable CloudWatch alarm for high memory utilization"
  type        = bool
  default     = true
}

variable "cpu_scale_up_threshold" {
  type        = number
  description = "CPU utilization percentage threshold for scaling up"
  default     = 75
}

variable "memory_scale_up_threshold" {
  type        = number
  description = "Memory utilization percentage threshold for scaling up"
  default     = 75
}

variable "alarm_actions" {
  type        = list(string)
  description = "The list of actions to execute when Cloudwatch alarm transitions to OK or ERROR state."
  default     = []
}

# ──────────────────────────────────────────────────────────────────────────────
# Autoscaling
# ──────────────────────────────────────────────────────────────────────────────
variable "enable_autoscaling" {
  description = "Whether to enable autoscaling for the ECS service"
  type        = bool
  default     = false
}

variable "task_count_min" {
  description = "Minimum number of tasks for auto scaling"
  type        = string
  default     = "1"
}

variable "task_count_max" {
  description = "Maximum number of tasks for auto scaling"
  type        = string
  default     = "2"
}

variable "enable_cpu_scaling" {
  description = "Whether to enable CPU-based autoscaling for the ECS service"
  type        = bool
  default     = false
}

variable "enable_memory_scaling" {
  description = "Whether to enable memory-based autoscaling for the ECS service"
  type        = bool
  default     = false
}

variable "autoscaling_cpu_target" {
  description = "CPU utilization target for auto scaling"
  type        = string
  default     = "70"
}

variable "autoscaling_memory_target" {
  description = "Memory utilization target for auto scaling"
  type        = number
  default     = 70
}

variable "autoscaling_in_cooldown" {
  type        = string
  description = "Cooldown time period after scaling in."
  default     = "120"
}

variable "autoscaling_out_cooldown" {
  type        = string
  description = "Cooldown time period after scaling out."
  default     = "60"
}

variable "enable_request_count_scaling" {
  description = "Whether to enable request count-based autoscaling for the ECS service"
  type        = bool
  default     = false
}

variable "request_count_target_group_resource_label" {
  description = "Resource label for ALBRequestCountPerTarget (deprecated: use external_lb_arn_suffix to compute internally)"
  type        = string
  default     = ""
}

variable "autoscaling_request_count_target" {
  description = "Target value for request count-based autoscaling"
  type        = number
  default     = 1000
}

# ──────────────────────────────────────────────────────────────────────────────
# SSM
# ──────────────────────────────────────────────────────────────────────────────
variable "create" {
  type        = string
  description = "Create, or not, resources defined by this module."
  default     = "true"
}

variable "parameter_store_path_prefix" {
  description = "Override SSM parameter path prefix. Default: /app-infra/{application}/{environment}"
  type        = string
  default     = null
}
