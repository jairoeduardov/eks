# CloudFront delante del ALB compartido: resuelve TLS sin comprar dominio
# (certificado *.cloudfront.net gratuito), requisito para el login vía Cognito
# Hosted UI de invoicing-app (Cognito rechaza redirect_uri http:// salvo
# localhost). De paso quita el HTTP plano de quiz.
#
# count = var.enable_cloudfront: el ALB lo crea el AWS Load Balancer
# Controller al sincronizar el primer Ingress, no Terraform — no hay nada que
# descubrir hasta que la plataforma y al menos una app ya están desplegadas.
# Se aplica en dos pasadas: primero infra+apps con enable_cloudfront=false,
# luego enable_cloudfront=true.

data "aws_lb" "shared" {
  count = var.enable_cloudfront ? 1 : 0

  tags = {
    "ingress.k8s.aws/stack" = "shared"
  }
}

resource "aws_cloudfront_origin_request_policy" "all_viewer" {
  count = var.enable_cloudfront ? 1 : 0
  name  = "${local.name}-all-viewer"

  cookies_config {
    cookie_behavior = "all"
  }
  headers_config {
    header_behavior = "allViewer"
  }
  query_strings_config {
    query_string_behavior = "all"
  }
}

resource "aws_cloudfront_distribution" "main" {
  count = var.enable_cloudfront ? 1 : 0

  enabled         = true
  comment         = "${local.name} - ALB compartido"
  is_ipv6_enabled = true
  price_class     = "PriceClass_100" # solo NA+EU, suficiente para un lab

  origin {
    domain_name = data.aws_lb.shared[0].dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # el ALB solo escucha HTTP; TLS termina en CloudFront
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Comportamiento por defecto: la SPA de invoicing-app en / (raíz), sin
  # caché — el nginx.conf del frontend ya emite los Cache-Control correctos
  # por archivo (no-store en index.html, immutable en assets con hash).
  default_cache_behavior {
    target_origin_id         = "alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled (gestionada AWS)
    origin_request_policy_id = aws_cloudfront_origin_request_policy.all_viewer[0].id
    compress                 = true
  }

  # API de invoicing-service: nunca cachear, reenviar todo (headers de auth, cookies).
  ordered_cache_behavior {
    path_pattern             = "/api/invoicing-management/*"
    target_origin_id         = "alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = aws_cloudfront_origin_request_policy.all_viewer[0].id
    compress                 = true
  }

  # quiz: mismo tratamiento, sin caché (es una app con sesión, no estáticos).
  ordered_cache_behavior {
    path_pattern             = "/quiz*"
    target_origin_id         = "alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = aws_cloudfront_origin_request_policy.all_viewer[0].id
    compress                 = true
  }

  # Assets con hash del frontend: cacheable de forma agresiva.
  ordered_cache_behavior {
    path_pattern           = "/assets/*"
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Certificado *.cloudfront.net por defecto: gratuito, valido, sin dominio propio.
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.tags
}

output "cloudfront_domain" {
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.main[0].domain_name : null
  description = "Hostname HTTPS de la plataforma. Usarlo como VITE_REDIRECT_URI / VITE_LOGOUT_URI / CORS_ALLOWED_ORIGINS y como callback URL en Cognito."
}
