data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ECS Task Execution Role
resource "aws_iam_role" "execution" {
  name = "${var.iam_role_name_prefix}-${var.ecs_service_name}-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

# Task Execution Policy
resource "aws_iam_role_policy_attachment" "execution_policy" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "task_execution_ssm" {
  name = "${var.ecs_service_name}-ssm-access"
  role = aws_iam_role.execution.id

  policy = var.execution_role_custom_policy_document != null ? var.execution_role_custom_policy_document : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "secretsmanager:GetSecretValue",
          "kms:Decrypt"
        ]
        Resource = var.ssm_resource_path != null ? [
          "arn:aws:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_resource_path}/*",
          "arn:aws:kms:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:key/*"
        ] : ["*"]
      }
    ]
  })
}

# Create a new task role only if no existing role ARN is provided
resource "aws_iam_role" "new_task" {
  count = var.existing_task_role_arn == null ? 1 : 0
  name  = "${var.iam_role_name_prefix}-${var.ecs_service_name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

# Task Policies - Only attach if we created a new role
resource "aws_iam_role_policy" "task_cloudwatch_access" {
  count = var.existing_task_role_arn == null ? 1 : 0
  name  = "${var.ecs_service_name}-cloudwatch-access"
  role  = aws_iam_role.new_task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ecs/${var.ecs_service_name}*:*"
        ]
      }
    ]
  })
}

# ECS Exec (aws ecs execute-command) needs the task role — not the execution role — to be able
# to open the SSM Session Manager channel. Only attached when enable_execute_command is true and
# only to a role this module created; a caller supplying existing_task_role_arn owns that role
# and must grant these permissions themselves if they also want exec enabled.
resource "aws_iam_role_policy" "task_execute_command" {
  count = var.existing_task_role_arn == null && var.enable_execute_command ? 1 : 0
  name  = "${var.ecs_service_name}-execute-command"
  role  = aws_iam_role.new_task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Custom policy for task role if provided (fallback when task_role_policy_documents is empty)
resource "aws_iam_role_policy" "task_custom_policy" {
  count  = var.existing_task_role_arn == null && var.task_role_custom_policy_document != null && length(var.task_role_policy_documents) == 0 ? 1 : 0
  name   = "${var.ecs_service_name}-custom-policy"
  role   = aws_iam_role.new_task[0].id
  policy = var.task_role_custom_policy_document
}

# Custom inline policies from root (task_role_policy_documents)
resource "aws_iam_role_policy" "task_policy_documents" {
  for_each = var.existing_task_role_arn == null ? { for idx, doc in var.task_role_policy_documents : "${idx}-${doc.name}" => doc } : {}

  name   = "${var.ecs_service_name}-${each.value.name}"
  role   = aws_iam_role.new_task[0].id
  policy = each.value.policy
}

# Attach additional policy ARNs if provided
resource "aws_iam_role_policy_attachment" "task_additional_policies" {
  count      = var.existing_task_role_arn == null ? length(var.task_role_policy_arns) : 0
  role       = aws_iam_role.new_task[0].name
  policy_arn = var.task_role_policy_arns[count.index]
}

# Attach additional policy ARNs to execution role if provided
resource "aws_iam_role_policy_attachment" "execution_additional_policies" {
  count      = length(var.execution_role_policy_arns)
  role       = aws_iam_role.execution.name
  policy_arn = var.execution_role_policy_arns[count.index]
}
