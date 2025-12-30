# AWS Infrastructure - Terraform

This directory contains Terraform configuration for AWS infrastructure.

## Directory Structure

```
aws/
├── main.tf              # Main configuration
├── variables.tf         # Variable definitions
├── providers.tf         # AWS provider configuration
├── backend.tf           # S3 backend configuration
├── outputs.tf           # Output values
├── vpc.tf               # VPC, Subnets, Route Tables, Security Groups
├── ecs.tf               # ECS Cluster, Service, Task Definition
├── alb.tf               # ALB, Target Groups, Listeners
├── rds.tf               # RDS PostgreSQL
├── ecr.tf               # ECR Repository
├── iam.tf               # ECS Task Role, Execution Role
└── cloudwatch.tf        # CloudWatch Logs
```

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform >= 1.5
3. S3 bucket and DynamoDB table for state management

## Backend Initialization (First Time Only)

```bash
# Create S3 bucket and DynamoDB table
./scripts/setup-backend.sh datadog-poc-terraform-state
```

## Deployment Steps

### 1. Initialize Terraform

```bash
cd infra/terraform/aws
terraform init
```

### 2. Plan (Dry-Run)

```bash
terraform plan \
  -var-file=../shared/tenants.tfvars \
  -var="dd_api_key=${DD_API_KEY}" \
  -out=tfplan
```

### 3. Apply

```bash
terraform apply tfplan
```

### 4. Verify Outputs

```bash
terraform output alb_dns_name
terraform output ecr_repository_url
terraform output rds_endpoint
```

## Environment Variables

Set the following environment variables before deployment:

```bash
export DD_API_KEY="your-datadog-api-key"
export AWS_PROFILE="your-aws-profile"
export AWS_REGION="ap-northeast-1"
```

## Adding a New Tenant

1. Edit `../shared/tenants.tfvars`:

```hcl
tenants = {
  tenant-a = { name = "tenant-a", cpu = 256, memory = 512, priority = 100, environment = "poc" }
  tenant-b = { name = "tenant-b", cpu = 256, memory = 512, priority = 101, environment = "poc" }
  tenant-c = { name = "tenant-c", cpu = 256, memory = 512, priority = 102, environment = "poc" }
  tenant-d = { name = "tenant-d", cpu = 256, memory = 512, priority = 103, environment = "poc" }  # NEW
}
```

2. Run `terraform plan` and `terraform apply`:

```bash
terraform plan -var-file=../shared/tenants.tfvars -var="dd_api_key=${DD_API_KEY}"
terraform apply -var-file=../shared/tenants.tfvars -var="dd_api_key=${DD_API_KEY}"
```

## Important Notes

### Security Group Circular Dependency

Security groups are defined separately from their rules to avoid circular dependencies:
- `aws_security_group`: Defines the security group
- `aws_security_group_rule`: Defines ingress/egress rules

### RDS Password Management

- RDS password is randomly generated and stored in SSM Parameter Store (`/datadog-poc/db-password`)
- `lifecycle { ignore_changes = all }` is set to prevent password regeneration on `terraform destroy`

### ALB Listener Rule Priority

- Priority is explicitly defined in `tenants.tfvars` to avoid non-deterministic ordering
- Each tenant has a unique priority value

## Resources Created

- VPC (10.0.0.0/16)
- Public Subnets (2 AZs)
- DB Subnets (2 AZs)
- Internet Gateway
- Route Tables
- Security Groups (ALB, ECS, RDS)
- ECS Cluster
- ECS Task Definition (with Datadog Agent sidecar)
- ECS Services (per tenant)
- ALB
- Target Groups (per tenant)
- Listener Rules (path-based routing)
- RDS PostgreSQL (Multi-AZ)
- ECR Repository
- IAM Roles (Task Role, Execution Role)
- CloudWatch Log Groups
- VPC Flow Logs

## Cost Estimate (Monthly)

| Resource | Cost (USD) |
|----------|-----------|
| ECS Fargate (6 tasks) | $54.06 |
| RDS t4g.micro (Multi-AZ) | $57.06 |
| ALB | $76.14 |
| CloudWatch Logs | $1.06 |
| ECR | $0.46 |
| VPC Flow Logs | $0.50 |
| **Total** | **$189.28** |

## Cleanup

```bash
terraform destroy \
  -var-file=../shared/tenants.tfvars \
  -var="dd_api_key=${DD_API_KEY}"
```

## Troubleshooting

### Issue: `terraform validate` fails with cycle error

**Solution**: Security groups are now defined with separate `aws_security_group_rule` resources.

### Issue: RDS password changes on every apply

**Solution**: `lifecycle { ignore_changes = all }` is set on `random_password.db_password`.

### Issue: ALB listener rule priority conflict

**Solution**: Priority is explicitly set in `tenants.tfvars`.

## Related Documentation

- Design Document: [docs/04_インフラ設計/02_詳細設計/aws/INDEX.md](../../../docs/04_インフラ設計/02_詳細設計/aws/INDEX.md)
- Terraform Standards: [.claude/docs/40_standards/42_infra/iac/terraform.md](../../../.claude/docs/40_standards/42_infra/iac/terraform.md)
