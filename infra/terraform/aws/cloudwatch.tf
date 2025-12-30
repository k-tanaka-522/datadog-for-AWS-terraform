# ECS Task Logs
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/demo-api"
  retention_in_days = 7

  tags = {
    Name = "demo-api-logs"
  }
}
