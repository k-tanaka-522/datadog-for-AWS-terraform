# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "datadog-poc-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "datadog-poc-cluster"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "demo_api" {
  family                   = "demo-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "demo-api"
      image     = "${aws_ecr_repository.demo_api.repository_url}:latest"
      cpu       = 128
      memory    = 256
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "DB_HOST"
          value = aws_db_instance.main.address
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_NAME"
          value = "demo"
        },
        {
          name  = "DB_USER"
          value = "postgres"
        },
        {
          name  = "DD_AGENT_HOST"
          value = "localhost"
        },
        {
          name  = "DD_TRACE_ENABLED"
          value = "true"
        }
      ]
      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = aws_ssm_parameter.db_password.arn
        }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "demo-api"
        }
      }
    },
    {
      name      = "datadog-agent"
      image     = "public.ecr.aws/datadog/agent:latest"
      cpu       = 128
      memory    = 256
      essential = false
      environment = [
        {
          name  = "DD_API_KEY"
          value = var.dd_api_key
        },
        {
          name  = "DD_SITE"
          value = "datadoghq.com"
        },
        {
          name  = "DD_APM_ENABLED"
          value = "true"
        },
        {
          name  = "DD_LOGS_ENABLED"
          value = "true"
        },
        {
          name  = "ECS_FARGATE"
          value = "true"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "datadog-agent"
        }
      }
    }
  ])

  tags = {
    Name = "demo-api"
  }
}

# ECS Service (per tenant)
resource "aws_ecs_service" "demo_api" {
  for_each = var.tenants

  name            = "demo-api-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.demo_api.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets = [
      aws_subnet.public_1a.id,
      aws_subnet.public_1c.id
    ]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.demo_api[each.key].arn
    container_name   = "demo-api"
    container_port   = 8080
  }

  health_check_grace_period_seconds = 60

  depends_on = [
    aws_lb_listener.http
  ]

  tags = {
    Name     = "demo-api-${each.key}"
    TenantID = each.key
  }
}
