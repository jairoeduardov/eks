# Runbook

## Acceso

```bash
aws eks update-kubeconfig --name eks-lab-lab --region us-east-1
kubectl get nodes
```

**ArgoCD UI** (sin dominio, solo port-forward):

```bash
kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:443
# usuario: admin
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

**Grafana** (sin dominio, solo port-forward):

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

**Hostname del ALB compartido**:

```bash
kubectl -n quiz get ingress quiz -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## Rollback de una aplicación

El estado deseado vive en `deploy/values.yaml` del repo de la app. Revertir
el commit del bump y ArgoCD sincroniza solo:

```bash
git log --oneline -- deploy/values.yaml   # localizar el commit "chore: deploy <sha>"
git revert <commit>
git push
kubectl -n <app> rollout status deploy/<app>
```

Rollback manual inmediato sin esperar a ArgoCD (usar solo si es urgente,
ArgoCD lo revertirá de nuevo salvo que también se corrija Git):

```bash
kubectl -n <app> rollout undo deploy/<app>
```

## Troubleshooting

**Pod no llega a Ready**: revisar que `/actuator/health/liveness` y
`/readiness` respondan 200 dentro del pod:

```bash
kubectl -n <app> exec -it deploy/<app> -- curl -s localhost:8080/actuator/health/readiness
kubectl -n <app> describe pod <pod>       # eventos de probes fallidos
```

**ExternalSecret no sincroniza**:

```bash
kubectl -n <app> describe externalsecret <app>
kubectl -n external-secrets logs deploy/external-secrets -f
```

Causas comunes: el secreto `eks/<app>` no existe en Secrets Manager, o el rol
IRSA (`external-secrets`) no tiene permiso sobre ese ARN — revisar
`terraform/50-irsa.tf`, el statement de `external_secrets` restringe a `eks/*`.

**Ingress no crea el ALB / no aparece el path**:

```bash
kubectl -n kube-system logs deploy/aws-load-balancer-controller -f
kubectl -n <app> describe ingress <app>
```

Confirmar que todas las apps del mismo ALB usan el mismo
`alb.ingress.kubernetes.io/group.name: shared` y que los paths no colisionan.

**Nodos SPOT interrumpidos simultáneamente**: el ASG los reemplaza solo en
minutos; si ocurre seguido, considerar mover un nodo a ON_DEMAND
(`capacity_type` mixto) o revisar `node_instance_types` en
`terraform/variables.tf` para diversificar más.

## Costo

Revisar Cost Explorer filtrado por tag `Project=eks-lab`. El control plane de
EKS (73 USD/mes) y el ALB (~18 USD/mes) son los componentes fijos; escalar el
node group o los volúmenes de Prometheus/RDS es lo que mueve el resto.
