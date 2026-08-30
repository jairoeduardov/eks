# OIDC provider de GitHub Actions + rol de despliegue asumible sin llaves estáticas.
# Ajustar var.github_org / var.github_repos antes de aplicar.

variable "github_org" {
  description = "Organización o usuario dueño de los repos que despliegan"
  type        = string
  default     = "jairoeduardov"
}

variable "github_repos" {
  description = "Lista de repos (org/repo) autorizados a asumir el rol de despliegue"
  type        = list(string)
  default = [
    "jairoeduardov/eks",
    "jairoeduardov/quiz",
    "jairoeduardov/invoicing-service",
    "jairoeduardov/invoicing-app",
  ]
}

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "github_deploy_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Solo la rama main de cada repo autorizado puede asumir el rol.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for repo in var.github_repos : "repo:${repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "github-actions-eks-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_deploy_trust.json
}

# Permisos mínimos: push a ECR (todos los repos) + lectura de la infraestructura para smoke tests.
# El despliegue en el cluster lo hace ArgoCD, no este rol; por eso NO lleva permisos de EKS.
data "aws_iam_policy_document" "github_deploy_permissions" {
  statement {
    sid    = "EcrAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["arn:aws:ecr:*:*:repository/*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "ecr-push"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy_permissions.json
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}

# Rol separado para `terraform apply` desde CI: necesita permisos amplios
# (VPC, EKS, IAM, RDS, S3, ECR, Secrets Manager) porque crea la plataforma entera.
# Solo el repo eks, y solo desde main, puede asumirlo.
data "aws_iam_policy_document" "terraform_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/eks:ref:refs/heads/main", "repo:${var.github_org}/eks:pull_request"]
    }
  }
}

resource "aws_iam_role" "terraform_apply" {
  name               = "github-actions-eks-terraform"
  assume_role_policy = data.aws_iam_policy_document.terraform_trust.json
}

# PowerUserAccess + IAM limitado: suficiente para crear VPC/EKS/RDS/S3/ECR sin
# otorgar control total de IAM (evita escalado de privilegios trivial).
resource "aws_iam_role_policy_attachment" "terraform_power_user" {
  role       = aws_iam_role.terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "terraform_iam_scoped" {
  statement {
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:ListPolicyVersions",
      "iam:CreateOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
      "iam:PassRole",
    ]
    # Limitado a roles/policies con el prefijo de esta plataforma; nunca al propio rol de CI.
    resources = [
      "arn:aws:iam::*:role/${var.project}*",
      "arn:aws:iam::*:policy/${var.project}*",
      "arn:aws:iam::*:oidc-provider/*",
    ]
  }
}

resource "aws_iam_role_policy" "terraform_iam_scoped" {
  name   = "iam-scoped"
  role   = aws_iam_role.terraform_apply.id
  policy = data.aws_iam_policy_document.terraform_iam_scoped.json
}

output "terraform_apply_role_arn" {
  value = aws_iam_role.terraform_apply.arn
}
