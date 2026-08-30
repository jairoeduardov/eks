# Componentes de plataforma instalados vía Helm, con Terraform como fuente de
# verdad de SU instalación (no de las apps, que gestiona ArgoCD).

resource "kubernetes_namespace" "platform" {
  for_each = toset(["argocd", "external-secrets", "monitoring"])
  metadata {
    name = each.value
  }
}

resource "kubernetes_namespace" "app" {
  for_each = local.app_namespaces
  metadata {
    name = each.value
  }
}

resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.alb_controller_irsa.iam_role_arn
    }
  }
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.11.0"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.alb_controller.metadata[0].name
  }

  depends_on = [kubernetes_service_account.alb_controller]
}

resource "kubernetes_service_account" "external_secrets" {
  metadata {
    name      = "external-secrets"
    namespace = "external-secrets"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.external_secrets_irsa.iam_role_arn
    }
  }
  depends_on = [kubernetes_namespace.platform]
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = "external-secrets"
  version    = "0.10.4"

  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.external_secrets.metadata[0].name
  }

  # alb_controller primero: su webhook mutante intercepta la creacion de
  # CUALQUIER Service del cluster. Sin esta dependencia, helm_release en
  # paralelo revienta con "no endpoints available for service
  # aws-load-balancer-webhook-service" porque el pod del controller aun no
  # esta Ready cuando este chart intenta crear su propio Service.
  depends_on = [kubernetes_service_account.external_secrets, helm_release.alb_controller]
}

# ClusterSecretStore compartido: cada ExternalSecret de cada app referencia
# este store. kubectl_manifest (no kubernetes_manifest): ver providers.tf.
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata   = { name = "aws-secretsmanager" }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = kubernetes_service_account.external_secrets.metadata[0].name
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  })

  depends_on = [helm_release.external_secrets]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.2"

  depends_on = [helm_release.alb_controller] # ver comentario en external_secrets
}

resource "helm_release" "argocd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  version    = "7.7.11"

  # Sin dominio: se accede por `kubectl port-forward`, sin exponer en el ALB.
  values = [yamlencode({
    server = {
      extraArgs = ["--insecure"] # TLS terminado por port-forward local, no expuesto a internet
    }
  })]

  depends_on = [kubernetes_namespace.platform, helm_release.alb_controller] # ver comentario en external_secrets
}
