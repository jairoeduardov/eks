variable "region" {
  description = "Región AWS de toda la plataforma"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nombre corto del proyecto, usado como prefijo en los recursos"
  type        = string
  default     = "eks-lab"
}

variable "environment" {
  description = "Nombre del único entorno de esta plataforma"
  type        = string
  default     = "lab"
}

variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZ usadas (2 es el mínimo razonable para EKS)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "enable_nat_gateway" {
  description = "Si es true, los nodos pasan a subnets privadas detrás de NAT (~+35 USD/mes). false = nodos en subnets públicas con SG restrictivo (perfil lab)."
  type        = bool
  default     = false
}

variable "cluster_version" {
  description = "Versión de Kubernetes del control plane EKS. Pinneada explícitamente, no flotante."
  type        = string
  default     = "1.33"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs autorizados a llamar al endpoint público de la API de EKS. Restringir a la IP del operador en uso real."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Lista de tipos de instancia para el node group SPOT (diversificados para reducir interrupciones)"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium", "t2.medium"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "app_names" {
  description = "Nombres de las aplicaciones: cada una obtiene su propio repositorio ECR"
  type        = list(string)
  default     = ["quiz"]
}

variable "namespace_overrides" {
  description = "Mapeo app_name -> namespace, para apps que comparten namespace (ej. invoicing-service e invoicing-app en 'invoicing'). Las apps no listadas usan su propio nombre como namespace."
  type        = map(string)
  default     = {}
}

variable "postgres_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "postgres_allocated_storage" {
  type    = number
  default = 20
}

variable "postgres_engine_version" {
  type    = string
  default = "16"
}

variable "mysql_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "mysql_allocated_storage" {
  type    = number
  default = 20
}

variable "cognito_user_pool_id" {
  description = "User Pool de Cognito que usa invoicing-service (COGNITO_USER_POOL_ID)"
  type        = string
  default     = "us-east-1_CJr63ssKa"
}

variable "cognito_cross_account_role_arn" {
  description = "Rol IAM en la cuenta del pool de Cognito (610550203411, 'User pool - Loroko') que invoicing-service asume via STS -- el pool no vive en esta cuenta AWS."
  type        = string
  default     = "arn:aws:iam::610550203411:role/eks-lab-invoicing-cognito-cross-account"
}

variable "enable_cloudfront" {
  description = "Crea la distribucion CloudFront delante del ALB compartido. Requiere que el ALB ya exista (Ingress sincronizado al menos una vez) porque se descubre por tag, no se referencia directamente."
  type        = bool
  default     = false
}
