resource "aws_s3_bucket" "loki" {
  bucket = "${local.name}-loki-logs-${data.aws_caller_identity.current.account_id}"
  tags   = local.tags
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 14
    }
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket                  = aws_s3_bucket.loki.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "kubernetes_service_account" "loki" {
  metadata {
    name      = "loki"
    namespace = "monitoring"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.loki_irsa.iam_role_arn
    }
  }
  depends_on = [kubernetes_namespace.platform]
}

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  namespace  = "monitoring"
  version    = "6.18.0"
  timeout    = 600 # default 300s se queda corto si el scheduler tarda en ubicar pods

  values = [yamlencode({
    deploymentMode = "SingleBinary"
    loki = {
      auth_enabled = false
      commonConfig = { replication_factor = 1 }
      storage = {
        type = "s3"
        bucketNames = {
          chunks = aws_s3_bucket.loki.bucket
          ruler  = aws_s3_bucket.loki.bucket
          admin  = aws_s3_bucket.loki.bucket
        }
        s3 = { region = var.region }
      }
      schemaConfig = {
        configs = [{
          from         = "2024-01-01"
          store        = "tsdb"
          object_store = "s3"
          schema       = "v13"
          index        = { prefix = "loki_index_", period = "24h" }
        }]
      }
    }
    singleBinary = {
      replicas = 1
      extraEnv = []
    }
    serviceAccount = {
      create = false
      name   = kubernetes_service_account.loki.metadata[0].name
    }
    # Sin componentes distribuidos: perfil lab, un solo binario cubre lectura+escritura
    write   = { replicas = 0 }
    read    = { replicas = 0 }
    backend = { replicas = 0 }

    # Los defaults del chart piden ~9.8Gi de memoria para chunksCache --
    # dimensionado para multi-tenant en produccion, imposible en t3.medium
    # (4Gi total). Tamano de laboratorio explicito.
    chunksCache = {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }
    resultsCache = {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }
  })]

  depends_on = [
    kubernetes_service_account.loki,
    helm_release.alb_controller,  # ver comentario en 60-platform.tf
    kubernetes_storage_class.gp3, # ver comentario en 20-cluster.tf
  ]
}

resource "helm_release" "alloy" {
  name       = "grafana-alloy"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  namespace  = "monitoring"
  version    = "0.11.0"

  depends_on = [helm_release.loki]
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"
  version    = "66.3.1"
  timeout    = 600

  values = [yamlencode({
    prometheus = {
      prometheusSpec = {
        retention = "7d"
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              accessModes      = ["ReadWriteOnce"]
              storageClassName = "gp3"
              resources        = { requests = { storage = "10Gi" } }
            }
          }
        }
        # Descubre ServiceMonitors creados por charts/app en cualquier namespace de app
        serviceMonitorSelectorNilUsesHelmValues = false
      }
    }
    grafana = {
      # Sin dominio: acceso por `kubectl port-forward`, no expuesto en el ALB (sin ingress).
      additionalDataSources = [{
        name = "Loki"
        type = "loki"
        url  = "http://loki.monitoring.svc.cluster.local:3100"
      }]
    }
  })]

  depends_on = [
    kubernetes_namespace.platform,
    helm_release.alb_controller,  # ver comentario en 60-platform.tf
    kubernetes_storage_class.gp3, # ver comentario en 20-cluster.tf
  ]
}
