# Roles IRSA: cada controlador de la plataforma asume un rol de IAM acotado
# vía su ServiceAccount, sin llaves estáticas ni permisos de nodo compartidos.

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.52"

  role_name             = "${local.name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.52"

  role_name                              = "${local.name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.tags
}

# External Secrets Operator: lectura de los secretos eks/<app> y eks/postgres-master
data "aws_iam_policy_document" "external_secrets" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = ["arn:aws:secretsmanager:${var.region}:*:secret:eks/*"]
  }
}

module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.52"

  role_name = "${local.name}-external-secrets"

  role_policy_arns = {
    secrets_read = aws_iam_policy.external_secrets_read.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "external_secrets_read" {
  name   = "${local.name}-external-secrets-read"
  policy = data.aws_iam_policy_document.external_secrets.json
}

# Loki: lectura/escritura del bucket de logs (creado en 70-observability.tf)
module "loki_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.52"

  role_name = "${local.name}-loki"

  role_policy_arns = {
    s3_logs = aws_iam_policy.loki_s3.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["monitoring:loki"]
    }
  }

  tags = local.tags
}

data "aws_iam_policy_document" "loki_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.loki.arn,
      "${aws_s3_bucket.loki.arn}/*",
    ]
  }
}

resource "aws_iam_policy" "loki_s3" {
  name   = "${local.name}-loki-s3"
  policy = data.aws_iam_policy_document.loki_s3.json
}

# ---------------------------------------------------------------------------
# invoicing-service: S3 (uploads + certificados), Secrets Manager y la
# politica COMPLETA de Cognito que el codigo realmente invoca (verificado
# contra CognitoAdminConfig.java y los servicios que llaman al SDK, no contra
# la lista de invoicing-service/docs/EKS_DEPLOYMENT_PLAN.md, que omite
# AdminDisableUser/AdminEnableUser).
# ---------------------------------------------------------------------------

module "invoicing_service_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.52"

  role_name = "${local.name}-invoicing-service"

  role_policy_arns = {
    s3      = aws_iam_policy.invoicing_service_s3.arn
    cognito = aws_iam_policy.invoicing_service_cognito.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["invoicing:invoicing-service"]
    }
  }

  tags = local.tags
}

data "aws_iam_policy_document" "invoicing_service_s3" {
  statement {
    sid    = "Uploads"
    effect = "Allow"
    actions = [
      "s3:PutObject", "s3:GetObject", "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.invoicing_uploads.arn}/*"]
  }

  statement {
    sid       = "CertsRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.invoicing_certs.arn}/*"]
  }
}

resource "aws_iam_policy" "invoicing_service_s3" {
  name   = "${local.name}-invoicing-service-s3"
  policy = data.aws_iam_policy_document.invoicing_service_s3.json
}

data "aws_iam_policy_document" "invoicing_service_cognito" {
  # El pool de Cognito ("User pool - Loroko", COGNITO_USER_POOL_ID) vive en la
  # cuenta 610550203411, no en esta (var.cognito_cross_account_role_arn). La
  # API de Cognito no admite políticas basadas en recursos ni acceso
  # cross-account directo vía IAM: el único camino es que este rol asuma un
  # rol EN esa cuenta (creado manualmente, ver eks-lab-invoicing-cognito-cross-account)
  # que sí tiene permisos sobre el pool. Sin este statement, CognitoAdminConfig
  # obtiene AccessDenied o ResourceNotFoundException según lo que intente.
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [var.cognito_cross_account_role_arn]
  }
}

resource "aws_iam_policy" "invoicing_service_cognito" {
  name   = "${local.name}-invoicing-service-cognito"
  policy = data.aws_iam_policy_document.invoicing_service_cognito.json
}

output "invoicing_service_irsa_role_arn" {
  value       = module.invoicing_service_irsa.iam_role_arn
  description = "Pegar en invoicing-service/deploy/values.yaml -> serviceAccount.annotations"
}
