# Onboarding de una aplicación nueva

Receta para llevar una aplicación del portafolio al cluster compartido.
Ejemplo con una app llamada `mi-app`, Spring Boot, puerto 8080.

## 1. Terraform: registrar la app

En `terraform/environments/lab.tfvars`, añadir el nombre a `app_names`:

```hcl
app_names = ["quiz", "mi-app"]
```

`terraform apply` crea el repositorio ECR y el namespace `mi-app`.

**Solución con backend + frontend separados** (como invoicing-service +
invoicing-app): ambos comparten namespace vía `namespace_overrides`, para que
convivan como una sola solución en vez de dos namespaces sueltos:

```hcl
app_names = ["quiz", "mi-servicio", "mi-frontend"]
namespace_overrides = {
  "mi-servicio"  = "mi-solucion"
  "mi-frontend"  = "mi-solucion"
}
```

Cada uno sigue teniendo su propio repositorio ECR, su propio `Application` de
ArgoCD y su propio `deploy/values.yaml` — solo el namespace de Kubernetes se
comparte.

**Ruteo dentro del mismo IngressGroup**: si más de una app expone `Ingress`
en el ALB compartido, fijar `ingress.order` en `deploy/values.yaml` para que
los paths específicos se evalúen antes que cualquier catch-all `/`:

```yaml
ingress:
  order: 20  # menor = se evalua antes; el catch-all "/" debe llevar el numero mas alto
```

Solo **una** aplicación puede ocupar `/` en todo el cluster — es el recurso
catch-all del ALB compartido.

## 2. Base de datos (si aplica)

Conectar al RDS compartido (endpoint en el output `postgres_endpoint`) y crear
la base y el usuario a mano:

```sql
CREATE DATABASE mi_app;
CREATE USER mi_app WITH ENCRYPTED PASSWORD '...';
GRANT ALL PRIVILEGES ON DATABASE mi_app TO mi_app;
```

Si la app usa MySQL en vez de PostgreSQL (como `invoicing-service`), añadir
una instancia RDS MySQL en `terraform/40-data.tf` — el RDS Postgres compartido
no le sirve.

## 3. Secreto en AWS Secrets Manager

Crear `eks/mi-app` con las claves que la app espera como variables de entorno:

```bash
aws secretsmanager create-secret --name eks/mi-app --secret-string '{
  "SPRING_DATASOURCE_PASSWORD": "...",
  "APP_AUTH_SECRET": "..."
}'
```

## 4. En el repo de la aplicación

**`deploy/values.yaml`**:

```yaml
image:
  repository: "<account-id>.dkr.ecr.us-east-1.amazonaws.com/mi-app"
  tag: "placeholder" # el pipeline lo sobrescribe en cada deploy

containerPort: 8080

ingress:
  paths: ["/mi-app"]
  healthcheckPath: /mi-app/actuator/health

probes:
  liveness:  { path: /mi-app/actuator/health/liveness }
  readiness: { path: /mi-app/actuator/health/readiness }

env:
  SERVER_SERVLET_CONTEXT_PATH: /mi-app

externalSecret:
  secretName: eks/mi-app
```

**`.github/workflows/deploy.yml`**:

```yaml
name: deploy
on:
  push:
    branches: [main]
    paths-ignore: ["deploy/**", "**.md"]
permissions: { id-token: write, contents: write }
jobs:
  deploy:
    uses: jairoeduardov/eks/.github/workflows/app-build-deploy.yml@main
    with:
      app_name: mi-app
      dockerfile: Dockerfile
      deploy_role_arn: ${{ secrets.DEPLOY_ROLE_ARN }}
```

Requiere el secreto `DEPLOY_ROLE_ARN` en el repo (Settings → Secrets → Actions),
con el ARN del output `github_deploy_role_arn` de `bootstrap/`.

Antes de habilitar Spring Boot probes de Kubernetes: verificar que
`management.endpoint.health.probes.enabled: true` está en el `application.yml`
de la app — sin eso `/actuator/health/liveness` devuelve 404 y el pod nunca
llega a `Ready`.

## 5. Registrar en ArgoCD

Copiar `argocd/applications/quiz.yaml` de este repo a `argocd/applications/mi-app.yaml`,
cambiar `name`, `repoURL` del segundo source y `destination.namespace`. Aplicar:

```bash
kubectl apply -f argocd/applications/mi-app.yaml
```

## 6. Verificar

```bash
git push   # dispara el workflow
kubectl -n mi-app rollout status deploy/mi-app
ALB=$(kubectl -n mi-app get ingress mi-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -sf http://$ALB/mi-app/actuator/health
```
