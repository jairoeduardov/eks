# Plataforma EKS del portafolio

Cluster EKS único, de bajo costo, compartido por las aplicaciones del portafolio
(`quiz`, `invoicing-service` + `invoicing-app`, y las que se vayan agregando).
GitOps con ArgoCD; infraestructura con Terraform; un ALB compartido con ruteo
por path; secretos desde AWS Secrets Manager vía External Secrets Operator.

Ver el plan completo de diseño y las decisiones en
`~/.claude/plans/analiza-y-dise-a-una-lovely-planet.md`.

## Estructura

```
bootstrap/     Se aplica UNA vez, con estado local: bucket S3 de estado, tabla
               de lock, OIDC provider de GitHub y los dos roles de despliegue.
terraform/     Toda la plataforma: VPC, EKS, ECR, RDS, IRSA, ArgoCD,
               observabilidad. Backend remoto S3 (creado por bootstrap).
charts/app/    Chart Helm generico que reutilizan todas las aplicaciones.
argocd/        AppProject + una Application por aplicacion (multi-source:
               chart de aqui + deploy/values.yaml del repo de la app).
docs/          onboarding-app.md (como agregar una app nueva) y runbook.md.
```

## Puesta en marcha desde cero

```bash
# 1. Bootstrap (una sola vez)
cd bootstrap
terraform init
terraform apply
terraform output              # anotar state_bucket, lock_table, ambos role_arn

# 2. Plataforma
cd ../terraform
terraform init \
  -backend-config="bucket=<state_bucket>" \
  -backend-config="dynamodb_table=<lock_table>" \
  -backend-config="region=us-east-1"
terraform apply -var-file="environments/lab.tfvars"

# 3. Conectar kubectl
aws eks update-kubeconfig --name eks-lab-lab --region us-east-1
kubectl get nodes

# 4. Registrar el proyecto de ArgoCD y las Applications
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/applications/quiz.yaml

# 5. Secretos de GitHub Actions (Settings -> Secrets, en cada repo de app y en eks)
#    TERRAFORM_ROLE_ARN, TF_STATE_BUCKET, TF_LOCK_TABLE  (solo en eks)
#    DEPLOY_ROLE_ARN = github_deploy_role_arn             (en cada repo de app)
```

## Onboarding de una aplicación nueva

Ver `docs/onboarding-app.md`.

## Costo estimado

~134 USD/mes en el perfil lab (ver plan de diseño para el detalle). El control
plane de EKS (73 USD/mes) es fijo; cada app adicional que quepa en los nodos
existentes es prácticamente gratis.
