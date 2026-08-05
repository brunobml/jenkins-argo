# install k3d cluster

```bash
k3d cluster create argolab \
--api-port 6550 \
-p "8080:80@loadbalancer" \
-p "8443:443@loadbalancer" \
--agents 2

INFO[0000] portmapping '8080:80' targets the loadbalancer: defaulting to [servers:*:proxy agents:*:proxy]
INFO[0000] portmapping '8443:443' targets the loadbalancer: defaulting to [servers:*:proxy agents:*:proxy]
INFO[0000] Prep: Network
INFO[0000] Created network 'k3d-argolab'
INFO[0000] Created image volume k3d-argolab-images
INFO[0000] Starting new tools node...
INFO[0000] Starting node 'k3d-argolab-tools'
INFO[0001] Creating node 'k3d-argolab-server-0'
INFO[0001] Creating node 'k3d-argolab-agent-0'
INFO[0001] Creating node 'k3d-argolab-agent-1'
INFO[0001] Creating LoadBalancer 'k3d-argolab-serverlb'
INFO[0001] Using the k3d-tools node to gather environment information
INFO[0001] Starting new tools node...
INFO[0001] Starting node 'k3d-argolab-tools'
INFO[0002] Starting cluster 'argolab'
INFO[0002] Starting servers...
INFO[0002] Starting node 'k3d-argolab-server-0'
INFO[0007] Starting agents...
INFO[0007] Starting node 'k3d-argolab-agent-1'
INFO[0007] Starting node 'k3d-argolab-agent-0'
INFO[0018] Starting helpers...
INFO[0018] Starting node 'k3d-argolab-serverlb'
INFO[0024] Injecting records for hostAliases (incl. host.k3d.internal) and for 5 network members into CoreDNS configmap...
INFO[0027] Cluster 'argolab' created successfully!
INFO[0027] You can now use it like this:
kubectl cluster-info

➜  jenkins-argo git:(main) ✗ kubectl get nodes
NAME                   STATUS   ROLES           AGE   VERSION
k3d-argolab-agent-0    Ready    <none>          51s   v1.35.5+k3s1
k3d-argolab-agent-1    Ready    <none>          52s   v1.35.5+k3s1
k3d-argolab-server-0   Ready    control-plane   62s   v1.35.5+k3s1
```

## Install Argo-CD and deploy boostrap app

```bash
kubectl create namespace argocd
namespace/argocd created

kubectl apply \
--server-side \
--force-conflicts \
-n argocd \
-f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## Create Ingress

```bash
kubectl apply -f bootstrap/argocd-ingress.yaml
ingress.networking.k8s.io/argocd created
```

## Patch ConfigMap argoCD server to accept insecure connections

```bash
kubectl patch configmap argocd-cmd-params-cm \
  -n argocd \
  --type merge \
  -p '{"data":{"server.insecure":"true"}}'

kubectl rollout restart deployment argocd-server -n argocd
```

## Get Login Credentials

```bash
kubectl get secret argocd-initial-admin-secret \
-n argocd \
-o jsonpath='{.data.password}' | base64 -d; echo
```

## Login to Argo-CD WebUI

```bash
User:Admin

http://localhost:8080
```

## Instal argocd cli

```bash
brew install argocd
```

## export Argo-CD login password

```bash
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath='{.data.password}' | base64 --decode)
```

## login argocd cli

```bash
argocd login localhost:8080 \
--username admin \
--password "$ARGOCD_PASSWORD" \
--plaintext \
--insecure
{"level":"warning","msg":"Failed to invoke grpc call. Use flag --grpc-web in grpc calls. To avoid this warning message, use flag --grpc-web.","time":"2026-08-05T14:44:20-06:00"}
'admin:login' logged in successfully
Context 'localhost:8080' updated
```

## Bootstrap MAIN APP

```bash
kubectl apply -f bootstrap/root-application.yaml
application.argoproj.io/platform-apps created
```

## List argocd apps

```bash

jenkins-argo git:(main) ✗ argocd app list
{"level":"warning","msg":"Failed to invoke grpc call. Use flag --grpc-web in grpc calls. To avoid this warning message, use flag --grpc-web.","time":"2026-08-05T14:43:40-06:00"}
NAME                  CLUSTER                         NAMESPACE      PROJECT  STATUS  HEALTH   SYNCPOLICY  CONDITIONS  REPO                                                  PATH                        TARGET
argocd/alloy          https://kubernetes.default.svc  alloy          default  Synced  Healthy  Auto-Prune  <none>      https://grafana.github.io/helm-charts                                             1.11.0
argocd/argo-rollouts  https://kubernetes.default.svc  argo-rollouts  default  Synced  Healthy  Auto-Prune  <none>      https://argoproj.github.io/argo-helm                                              2.41.1
argocd/canary-demo    https://kubernetes.default.svc  canary-demo    default  Synced  Healthy  Auto-Prune  <none>      https://github.com/brunobml/jenkins-argo.git          apps/canary-demo/manifests  main
argocd/grafana        https://kubernetes.default.svc  grafana        default  Synced  Healthy  Auto-Prune  <none>      oci://ghcr.io/grafana/helm-charts/grafana             .                           10.1.4
argocd/jenkins        https://kubernetes.default.svc  jenkins        default  Synced  Healthy  Auto-Prune  <none>      oci://ghcr.io/jenkinsci/helm-charts/jenkins           .                           5.9.49
argocd/loki           https://kubernetes.default.svc  loki           default  Synced  Healthy  Auto-Prune  <none>      https://grafana-community.github.io/helm-charts                                   13.2.0
argocd/platform-apps  https://kubernetes.default.svc  argocd         default  Synced  Healthy  Auto-Prune  <none>      https://github.com/brunobml/jenkins-argo.git          apps                        main
argocd/prometheus     https://kubernetes.default.svc  prometheus     default  Synced  Healthy  Auto-Prune  <none>      oci://ghcr.io/prometheus-community/charts/prometheus  .                           29.21.0
```