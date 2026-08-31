region      = "us-east-1"
project     = "eks-lab"
environment = "lab"

enable_nat_gateway = false

node_instance_types = ["t3.medium", "t3a.medium", "t2.medium"]
node_min_size       = 2
# 4, no 2: con 2 nodos t3.medium la plataforma (ArgoCD + external-secrets +
# ALB controller + kube-prometheus-stack + Loki) choca con el limite de pods
# por nodo de t3.medium (ENI/IP) y con memoria disponible -- "Insufficient
# memory" + "Too many pods" en el scheduler. Dentro del max_size ya aprobado.
node_desired_size = 4
node_max_size     = 4

app_names = ["quiz", "invoicing-service", "invoicing-app"]

# invoicing-service e invoicing-app comparten namespace: son una sola solucion
namespace_overrides = {
  "invoicing-service" = "invoicing"
  "invoicing-app"     = "invoicing"
}

# Fase 1: apps desplegadas, ALB en HTTP publico directo.
# Fase 2: ALB ya validado (invoicing-service/invoicing-app healthy), CloudFront delante.
enable_cloudfront = true

cognito_user_pool_id = "us-east-1_CJr63ssKa"

# TODO: restringir a la IP publica del operador antes de aplicar en un entorno real
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
