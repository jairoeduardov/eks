# EKS con un managed node group SPOT, arquitectura AMD64 (x86_64) exclusivamente.
# Autenticación por EKS Access Entries (API), no por el aws-auth ConfigMap legado.
# Sin acceso SSH a los nodos: administración solo vía API de EKS (kubectl).

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  cluster_endpoint_private_access      = true

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    # Prefix delegation: sin esto, t3.medium limita a 17 pods/nodo (IPs por
    # ENI), insuficiente para plataforma (ArgoCD, ALB controller, Prometheus,
    # Loki/Alloy) + apps. Cada ENI reserva un prefijo /28 en vez de IPs
    # individuales -> ~110 pods/nodo posibles. Gratis, sin cambiar instancia.
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
        }
      })
    }
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    spot = {
      ami_type       = "AL2023_x86_64_STANDARD" # AMD64 explícito, sin variante ARM
      capacity_type  = "SPOT"
      instance_types = var.node_instance_types

      min_size     = var.node_min_size
      desired_size = var.node_desired_size
      max_size     = var.node_max_size

      # Sin acceso remoto (SSH): remote_access se omite -- el default del
      # modulo es {}, que no crea ningun canal SSH. (No usar `null`: el
      # modulo llama length(var.remote_access), que revienta con null.)

      # kubernetes.io/* es un prefijo reservado por EKS -- CreateNodegroup lo
      # rechaza (InvalidParameterException). El nodo ya trae ese label solo
      # (AL2023_x86_64_STANDARD lo fija via kubelet), no hace falta declararlo.
      labels = {
        "node.eks/capacity" = "spot"
      }

      tags = local.tags
    }
  }

  # El SG de nodos gestionado por el módulo ya restringe el ingreso al tráfico
  # del propio cluster (control plane + nodos entre sí). Se añade explícitamente
  # el puerto de la app solo desde el SG del ALB, creado en 60-platform.tf.
  node_security_group_additional_rules = {
    ingress_alb_to_nodeport = {
      description              = "Trafico del ALB compartido hacia los NodePort de los Services"
      protocol                 = "tcp"
      from_port                = 30000
      to_port                  = 32767
      type                     = "ingress"
      source_security_group_id = aws_security_group.alb.id
    }
  }

  tags = local.tags
}

# Security group propio para el ALB compartido, referenciado por el node group
# de arriba y por el AWS Load Balancer Controller (60-platform.tf) vía anotación.
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "SG del ALB compartido (IngressGroup) para todas las apps"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-alb" })
}

# Antes de activar CloudFront (var.enable_cloudfront = false): el ALB acepta
# HTTP directo de internet, necesario para validar la plataforma y para que
# CloudFront tenga algo que descubrir la primera vez.
resource "aws_vpc_security_group_ingress_rule" "alb_http_public" {
  count = var.enable_cloudfront ? 0 : 1

  security_group_id = aws_security_group.alb.id
  description       = "HTTP publico (sin CloudFront todavia)"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# Con CloudFront activo: el ALB solo acepta trafico que ya paso por la CDN
# (TLS terminado ahi). Cierra el HTTP plano directo al balanceador.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  count = var.enable_cloudfront ? 1 : 0
  name  = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_from_cloudfront" {
  count = var.enable_cloudfront ? 1 : 0

  security_group_id = aws_security_group.alb.id
  description       = "HTTP solo desde CloudFront"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront[0].id
}

# El addon aws-ebs-csi-driver no crea ninguna StorageClass por si solo, y
# EKS no marca "gp2" (in-tree, legado) como default. Sin esto, cualquier PVC
# sin storageClassName explicito -- como el de Loki -- queda Pending para
# siempre ("no persistent volumes available ... and no storage class is set").
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type = "gp3"
  }

  depends_on = [module.eks]
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}
