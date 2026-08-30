# RDS PostgreSQL único, compartido por las apps que usan Postgres.
# invoicing-service usa MySQL (multi-tenancy schema-per-tenant) y NO cabe aquí;
# cuando entre al cluster, se añade una segunda instancia MySQL en este mismo archivo.
#
# Las bases de datos y usuarios por aplicación (CREATE DATABASE / CREATE USER) se
# crean a mano, documentado en docs/onboarding-app.md — no vía Terraform, para no
# depender de conectividad de red desde donde corre `terraform apply`.

resource "random_password" "postgres_master" {
  length  = 32
  special = false # evita caracteres que rompan connection strings sin escapar
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db"
  subnet_ids = module.vpc.private_subnets
  tags       = local.tags
}

resource "aws_security_group" "postgres" {
  name        = "${local.name}-postgres"
  description = "Solo acepta 5432 desde los nodos del cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Postgres desde los nodos EKS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-postgres" })
}

resource "aws_db_instance" "postgres" {
  identifier     = "${local.name}-postgres"
  engine         = "postgres"
  engine_version = var.postgres_engine_version

  instance_class    = var.postgres_instance_class
  allocated_storage = var.postgres_allocated_storage
  storage_type      = "gp3"

  db_name  = "platform"
  username = "postgres"
  password = random_password.postgres_master.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period   = 7
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-postgres-final"

  tags = local.tags
}

resource "aws_secretsmanager_secret" "postgres_master" {
  name = "eks/postgres-master"
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "postgres_master" {
  secret_id = aws_secretsmanager_secret.postgres_master.id
  secret_string = jsonencode({
    host     = aws_db_instance.postgres.address
    port     = aws_db_instance.postgres.port
    username = aws_db_instance.postgres.username
    password = random_password.postgres_master.result
  })
}

output "postgres_endpoint" {
  value = aws_db_instance.postgres.address
}

# ---------------------------------------------------------------------------
# MySQL: instancia dedicada para invoicing-service (multi-tenancy schema-per-
# tenant vía TenantFlywayRunner). El Postgres compartido de arriba no le sirve.
# ---------------------------------------------------------------------------

resource "random_password" "mysql_master" {
  length  = 32
  special = false
}

resource "aws_security_group" "mysql" {
  name        = "${local.name}-mysql"
  description = "Solo acepta 3306 desde los nodos del cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "MySQL desde los nodos EKS"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-mysql" })
}

resource "aws_db_instance" "mysql" {
  identifier     = "${local.name}-mysql"
  engine         = "mysql"
  engine_version = "8.0"

  instance_class    = var.mysql_instance_class
  allocated_storage = var.mysql_allocated_storage
  storage_type      = "gp3"

  username = "admin"
  password = random_password.mysql_master.result

  # Sin db_name: invoicing-service crea sus propios schemas (invoicing_mgmt,
  # invoicing_<tenant>) via Flyway con privilegio CREATE, igual que en prd
  # (application-prd.yml usa createDatabaseIfNotExist=false).

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.mysql.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period   = 7
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-mysql-final"

  tags = local.tags
}

resource "aws_secretsmanager_secret" "mysql_master" {
  name = "eks/mysql-master"
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "mysql_master" {
  secret_id = aws_secretsmanager_secret.mysql_master.id
  secret_string = jsonencode({
    host     = aws_db_instance.mysql.address
    port     = aws_db_instance.mysql.port
    username = aws_db_instance.mysql.username
    password = random_password.mysql_master.result
  })
}

output "mysql_endpoint" {
  value = aws_db_instance.mysql.address
}
