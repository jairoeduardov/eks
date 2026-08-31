# Un repositorio ECR por aplicación (var.app_names). Todas las imágenes se
# construyen exclusivamente para linux/amd64 (ver .github/workflows/app-build-deploy.yml).

resource "aws_ecr_repository" "app" {
  for_each = toset(var.app_names)

  name                 = each.value
  # MUTABLE: el workflow re-etiqueta "main-latest" en cada deploy (tag
  # flotante por diseño) y un rerun del mismo commit debe poder
  # sobrescribir su tag de SHA sin fallar.
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Purgar imagenes sin tag despues de 1 dia"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Retener solo las ultimas 10 imagenes etiquetadas"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["main-", "dev-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

output "ecr_repository_urls" {
  value = { for k, v in aws_ecr_repository.app : k => v.repository_url }
}
