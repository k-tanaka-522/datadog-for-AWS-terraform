# ALB
resource "aws_lb" "main" {
  name               = "datadog-poc-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets = [
    aws_subnet.public_1a.id,
    aws_subnet.public_1c.id
  ]

  enable_deletion_protection = false

  tags = {
    Name = "datadog-poc-alb"
  }
}

# Target Groups (per tenant)
resource "aws_lb_target_group" "demo_api" {
  for_each = var.tenants

  name        = "demo-api-${each.key}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/${each.key}/health"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name     = "demo-api-${each.key}-tg"
    TenantID = each.key
  }
}

# HTTP Listener (Port 80)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404 Not Found: Invalid tenant path"
      status_code  = "404"
    }
  }
}

# Listener Rules (Path-based routing per tenant)
resource "aws_lb_listener_rule" "demo_api" {
  for_each = var.tenants

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo_api[each.key].arn
  }

  condition {
    path_pattern {
      values = ["/${each.key}/*"]
    }
  }
}
