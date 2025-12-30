# Random Password for RDS
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}|:,.<>?"

  lifecycle {
    ignore_changes = all
  }
}

# SSM Parameter for DB Password
resource "aws_ssm_parameter" "db_password" {
  name      = "/datadog-poc/db-password"
  type      = "SecureString"
  value     = random_password.db_password.result
  overwrite = true

  tags = {
    Name = "datadog-poc-db-password"
  }
}

# RDS Parameter Group
resource "aws_db_parameter_group" "main" {
  name   = "datadog-poc-pg16"
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = {
    Name = "datadog-poc-pg16"
  }
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "datadog-poc-db"

  # Engine configuration
  engine                = "postgres"
  engine_version        = "16"
  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database configuration
  db_name  = "demo"
  username = "postgres"
  password = random_password.db_password.result

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Multi-AZ (Important for L0 monitoring verification)
  multi_az = true

  # Backup configuration
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  # Parameter Group
  parameter_group_name = aws_db_parameter_group.main.name

  # CloudWatch Logs
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Deletion protection
  deletion_protection = false
  skip_final_snapshot = true

  # Auto minor version upgrade
  auto_minor_version_upgrade = true

  tags = {
    Name = "datadog-poc-db"
  }
}
