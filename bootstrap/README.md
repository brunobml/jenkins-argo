# Automated bootstrap

`./bootstrap/bootstrap.sh` runs every step below end to end (and `--destroy`
tears the cluster down). The manual steps are kept here for reference.

## After a host / WSL reboot

Docker restarts the k3d containers, but k3d does **not** re-inject
`host.k3d.internal` into CoreDNS (it only does that at cluster-create). Our
`coredns-custom` override now rewrites `host.k3d.internal -> host.docker.internal`
so this survives, but if things still look broken:

```bash
kubectl apply -f bootstrap/coredns-localhost-rewrite.yaml
kubectl -n kube-system rollout restart deploy/coredns

docker compose -f ~/repos/moto/compose.yaml up -d   # Moto (restart:unless-stopped now)

argocd app sync s3-moto        # re-runs terraform -> recreates the bucket
                               # (Moto is in-memory: guestbook entries are gone)
```

> Ports are mapped 1:1 (`80:80`, `443:443`) so the Keycloak OIDC issuer
> `http://keycloak.localhost` resolves to the same URL from the browser and from
> inside the cluster. See [SSO with Keycloak](#sso-with-keycloak) below.

# install k3d cluster

```bash
k3d cluster create argolab \
--api-port 6550 \
-p "80:80@loadbalancer" \
-p "443:443@loadbalancer" \
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

## Resolve *.localhost inside the cluster

So in-cluster clients (Argo CD, Grafana, Jenkins, Argo Workflows) can reach the
Keycloak issuer at the same URL as the browser.

```bash
kubectl apply -f bootstrap/coredns-localhost-rewrite.yaml
kubectl -n kube-system rollout restart deployment coredns
```

## Create Ingress

```bash
kubectl apply -f bootstrap/argocd-ingress.yaml
ingress.networking.k8s.io/argocd created
```

The ingress is served at `http://argocd.localhost`.

## Patch ConfigMap argoCD server to accept insecure connections

```bash
kubectl patch configmap argocd-cmd-params-cm \
  -n argocd \
  --type merge \
  -p '{"data":{"server.insecure":"true"}}'
```

## Wire Argo CD login to Keycloak

```bash
kubectl patch configmap argocd-cm -n argocd --type merge \
  --patch-file bootstrap/argocd-cm-sso-patch.yaml
kubectl patch configmap argocd-rbac-cm -n argocd --type merge \
  --patch-file bootstrap/argocd-rbac-cm-sso-patch.yaml
```

### Rollout Restart ArgoCD server

```bash
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
http://argocd.localhost
```

Either the local `admin` user, or **Log in via Keycloak** as `developer` /
`developer` (member of `platform-admins`, mapped to Argo CD `role:admin`).

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
argocd login argocd.localhost \
--username admin \
--password "$ARGOCD_PASSWORD" \
--plaintext \
--insecure \
--grpc-web
'admin:login' logged in successfully
Context 'argocd.localhost' updated
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

# SSO with Keycloak

The `keycloak` application (`apps/keycloak/`) runs Keycloak in dev mode and
imports the `platform` realm from `apps/keycloak/manifests/realm.yaml`. The realm
declares one confidential client per UI:

| App            | URL                        | Keycloak client  | Login flow                          |
| -------------- | -------------------------- | ---------------- | ----------------------------------- |
| Argo CD        | http://argocd.localhost    | `argocd`         | "Log in via Keycloak" button        |
| Grafana        | http://grafana.localhost   | `grafana`        | "Sign in with Keycloak" button      |
| Argo Workflows | http://workflows.localhost | `argo-workflows` | redirected to Keycloak (SSO only)   |
| Jenkins        | http://jenkins.localhost   | `jenkins`        | redirected to Keycloak (`oic-auth`) |

Keycloak admin console: http://keycloak.localhost — `admin` / `admin`.

Seed users (realm `platform`):

| User        | Password    | Group             | Effect                                        |
| ----------- | ----------- | ----------------- | --------------------------------------------- |
| `developer` | `developer` | `platform-admins` | admin on Argo CD + Grafana, full Jenkins/WF   |
| `viewer`    | `viewer`    | `platform-viewers`| viewer on Grafana, read on the others         |

Group → role mapping is driven by the `groups` claim:

- **Argo CD** — `bootstrap/argocd-rbac-cm-sso-patch.yaml`: `g, platform-admins, role:admin`
- **Grafana** — `role_attribute_path` in `apps/grafana/application.yaml`
- **Argo Workflows / Jenkins** — any authenticated user is logged in (`rbac.enabled: false` / `loggedInUsersCanDoAnything`)

## Notes and caveats

- **Fixed client secrets** live in Git (`realm.yaml`, the app manifests, the
  patch files). Fine for a throwaway local lab, not for anything shared.
- **Dev mode / H2** — Keycloak state is in-memory. A pod restart reimports the
  realm from Git, so any manual change in the admin console is lost.
- **Port 80** — SSO relies on `http://keycloak.localhost` resolving identically
  from the browser and from inside the cluster. Keep the host port at 80.
- Fallback: Argo CD keeps its local `admin` user. **Jenkins has no local
  fallback** - if Keycloak is unreachable, revert the `securityRealm` block in
  `apps/jenkins/application.yaml` (or set it back to `local`) and let Argo CD
  re-sync.
- SSO only works after the `keycloak` app is Synced/Healthy:
  `argocd app wait keycloak --grpc-web --timeout 600`. The consuming apps may
  crash-loop or show login errors until then, then self-heal.
- `oic-auth` config keys occasionally change between plugin majors; if Jenkins
  login breaks, check `apps/jenkins/application.yaml` against the installed
  plugin's JCasC schema at `http://jenkins.localhost/manage/configuration-as-code/`.
