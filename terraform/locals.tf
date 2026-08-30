locals {
  name = "${var.project}-${var.environment}"

  tags = {
    Project     = var.project
    Environment = var.environment
  }

  # Namespaces reales del cluster: cada app_name resuelve a su namespace
  # (por defecto, su propio nombre) via namespace_overrides, y se deduplica
  # -- invoicing-service e invoicing-app comparten namespace "invoicing".
  app_namespaces = toset([
    for a in var.app_names : lookup(var.namespace_overrides, a, a)
  ])
}
