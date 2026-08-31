# Endpoints de la plataforma

Referencia de acceso a todo lo desplegado en el cluster `eks-lab-lab`
(cuenta AWS `aguamarina`, 742682759469, región `us-east-1`). Generado tras
la Fase 2 (CloudFront activo).

## Accesos públicos (internet)

| Servicio | URL | Notas |
|---|---|---|
| invoicing-app (frontend) | https://d2j83258seld3f.cloudfront.net/ | SPA, login vía Cognito Hosted UI |
| invoicing-service (API) | https://d2j83258seld3f.cloudfront.net/api/invoicing-management/* | Mismo origen que el frontend (rutea por el ALB compartido) |
| Health check | https://d2j83258seld3f.cloudfront.net/api/invoicing-management/actuator/health | Público, sin auth |
| Swagger UI | https://d2j83258seld3f.cloudfront.net/api/invoicing-management/swagger-ui/index.html | Público, sin auth (ver nota de seguridad abajo) |
| OpenAPI spec | https://d2j83258seld3f.cloudfront.net/api/invoicing-management/v3/api-docs | JSON, público |
| Cognito Hosted UI (login directo) | `https://us-east-1cjr63sska.auth.us-east-1.amazoncognito.com/login?client_id=27uev4h8vehted9s4m4ospmre4&response_type=code&scope=openid+email+phone+profile+aws.cognito.signin.user.admin&redirect_uri=https://d2j83258seld3f.cloudfront.net/` | Pool "Loroko", cuenta AWS 610550203411 (distinta de la de EKS) |

El ALB compartido (`ingress.k8s.aws/stack=shared`) ya **no acepta tráfico
público directo** — su Security Group solo permite el prefix list de
CloudFront (`terraform/20-cluster.tf`, `var.enable_cloudfront=true`). Toda
verificación debe pasar por el dominio de CloudFront.

`quiz` no está desplegado (sin `deploy/values.yaml` en su repo) — no tiene
endpoint todavía.

## Accesos internos (sin Ingress — requieren `kubectl port-forward`)

| Servicio | Comando | URL local |
|---|---|---|
| ArgoCD UI | `kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:443` | https://localhost:8080 |
| ArgoCD admin password | `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` | usuario `admin` |
| Grafana | `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80` | http://localhost:3000 |
| Prometheus | `kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090` | http://localhost:9090 |
| Alertmanager | `kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093` | http://localhost:9093 |
| Loki | `kubectl -n monitoring port-forward svc/loki-gateway 3100:80` | http://localhost:3100 (datasource de Grafana, no para uso directo) |

## Bases de datos (privadas, solo alcanzables desde dentro de la VPC)

| Servicio | Endpoint |
|---|---|
| RDS Postgres (compartido) | `eks-lab-lab-postgres.cbhiu1cmpiqs.us-east-1.rds.amazonaws.com:5432` |
| RDS MySQL (invoicing) | `eks-lab-lab-mysql.cbhiu1cmpiqs.us-east-1.rds.amazonaws.com:3306` |

Sin acceso directo desde el laptop (subnets privadas); para consultas
puntuales usar un pod efímero (`kubectl run ... --image=mysql:8.0`).

---

## API REST — invoicing-service

Base path: `/api/invoicing-management` (vía CloudFront, prefijo ya incluido
en la tabla de accesos públicos arriba).

### Autenticación

Todas las rutas requieren `Authorization: Bearer <access_token>` de Cognito
(JWT validado contra `COGNITO_JWK_SET_URI`), **excepto**:

| Ruta | Motivo |
|---|---|
| `/actuator/health/**` | Health check para probes/ALB |
| `/swagger-ui.html`, `/swagger-ui/**`, `/v3/api-docs/**`, `/swagger-resources/**`, `/webjars/**` | Documentación de la API |
| `/v1/onboarding/**` | Registro público de nueva empresa |
| `/v1/auth/forgot-password` | Flujo de recuperación de contraseña |
| `/v1/auth/confirm-forgot-password` | Confirmación de recuperación |

`/v1/auth/change-password` sí requiere JWT (reenvía el access token a
Cognito `ChangePassword`).

> **Nota de seguridad**: Swagger UI y el spec OpenAPI quedan expuestos sin
> autenticación al público. Es un riesgo de exposición de información
> (estructura completa de la API, 214 rutas, nombres de campos) más que de
> acceso a datos — cada endpoint de negocio sigue exigiendo JWT — pero vale
> restringirlo si se quiere endurecer antes de un uso más amplio que el
> lab.

### Superficie de la API (58 controladores, 214 rutas)

El spec completo con todos los parámetros, schemas y respuestas vive en
Swagger UI (link arriba) — esta tabla es un mapa de navegación, no el
contrato completo.

| Recurso | Rutas | Recurso | Rutas |
|---|---|---|---|
| accounts-receivable | 2 | list-price | 3 |
| admin-dte | 7 | list-price-item | 7 |
| admin-tenant | 3 | manager | 2 |
| audit | 2 | municipality | 3 |
| auth | 3 | onboarding | 1 |
| branch-office | 2 | order | 2 |
| branch-office-type | 2 | payment | 3 |
| business-activity | 2 | payment-method | 2 |
| cash-register-session | 4 | payment-terms | 2 |
| cashier | 3 | permission | 1 |
| code-generation-config | 2 | point-of-sale | 2 |
| company | 8 | presence | 4 |
| cost-center | 2 | print-template | 2 |
| country | 2 | printing | 6 |
| credit-note | 5 | report | 23 |
| currency | 2 | seller | 2 |
| customer | 6 | tax | 2 |
| customer-withholding | 2 | unit-of-measure | 2 |
| debit-note | 4 | user | 7 |
| department | 3 | withholding | 2 |
| district | 3 | dte | 13 |
| dte-email-log | 3 | e-invoicing | 1 |
| enum | 6 | group | 1 |
| invoice | 12 | invoice-correlative | 3 |
| invoice-detail | 3 | invoice-payment | 3 |
| invoice-schedule | 7 | invoice-type | 1 |
| invoice-withholding | 2 | item | 4 |
| item-category | 3 | item-image | 1 |
| item-unit-of-measure | 2 | iva-report | 2 |

Grupos más relevantes para operar el sistema:

- **`auth`** (`/v1/auth/*`) — login, cambio/recuperación de contraseña.
- **`onboarding`** (`/v1/onboarding/*`) — alta de una empresa nueva (público).
- **`admin-tenant`** — gestión de tenants (la tabla `invoicing_mgmt.tenant`
  documentada en el runbook de despliegue).
- **`company`, `customer`, `item`** — catálogos base.
- **`invoice`, `credit-note`, `debit-note`, `dte`, `admin-dte`** — el núcleo
  de facturación electrónica y su ciclo de vida ante el Ministerio de
  Hacienda (El Salvador).
- **`report`** (23 rutas) — el grupo más grande; reportes operativos y
  fiscales.
- **`printing`, `print-template`** — generación de PDF/tickets.

### Cómo explorar el resto

```bash
# Listado de rutas + verbos + tags, desde el spec en vivo
curl -s https://d2j83258seld3f.cloudfront.net/api/invoicing-management/v3/api-docs \
  | python3 -c "
import json,sys
d = json.load(sys.stdin)
for path, methods in sorted(d['paths'].items()):
    for verb in methods:
        if verb.upper() in ('GET','POST','PUT','DELETE','PATCH'):
            print(verb.upper(), path)
"
```

O directamente en el navegador: Swagger UI (link en la tabla de arriba).
