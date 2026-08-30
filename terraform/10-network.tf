# VPC de 2 AZ. Sin NAT Gateway por defecto (var.enable_nat_gateway = false):
# los nodos viven en subnets públicas con IP pública propia y el VPC CNI hace
# SNAT del tráfico de los pods. Ahorra ~32 USD/mes frente a un NAT Gateway.
# La exposición se mitiga en 20-cluster.tf: SG de nodos sin ingreso desde 0.0.0.0/0
# y sin acceso SSH (remote_access deshabilitado).

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = local.name
  cidr = var.vpc_cidr
  azs  = var.availability_zones

  # /20 por subnet: suficiente para varios cientos de pods por AZ (VPC CNI asigna
  # una IP de la subnet del nodo a cada pod).
  public_subnets  = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 4, i + 4)]

  enable_nat_gateway     = var.enable_nat_gateway
  single_nat_gateway     = var.enable_nat_gateway # un solo NAT si se activa, no uno por AZ
  one_nat_gateway_per_az = false

  # Sin NAT Gateway (var.enable_nat_gateway = false): los nodos necesitan IP
  # publica propia para salir a internet, o CreateNodegroup falla con
  # "does not automatically assign public IP addresses to instances".
  map_public_ip_on_launch = !var.enable_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags requeridos por el controlador de ALB y por el autoscaler/Karpenter futuro
  public_subnet_tags = {
    "kubernetes.io/role/elb"              = "1"
    "kubernetes.io/cluster/${local.name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"     = "1"
    "kubernetes.io/cluster/${local.name}" = "shared"
  }

  tags = local.tags
}

# Gateway endpoint de S3, gratis: tráfico de Loki hacia S3 y de layers de ECR
# (que se respaldan en S3) queda dentro de la VPC en vez de salir a internet.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(module.vpc.public_route_table_ids, module.vpc.private_route_table_ids)

  tags = merge(local.tags, { Name = "${local.name}-s3-endpoint" })
}
