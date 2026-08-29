#!/usr/bin/env bash
#
# bootstrap.sh - Stand up a local k3d cluster, install Argo CD and hand control
# over to the GitOps "root" Application. Automates every step from README.md.
#
# Usage:
#   ./bootstrap/bootstrap.sh              # full run
#   ./bootstrap/bootstrap.sh --destroy    # delete the k3d cluster and exit
#   CLUSTER_NAME=mylab ./bootstrap/bootstrap.sh
#   SKIP_CLUSTER=true ./bootstrap/bootstrap.sh   # reuse an existing cluster
#
set -euo pipefail

# --- configuration ----------------------------------------------------------
CLUSTER_NAME="${CLUSTER_NAME:-argolab}"
API_PORT="${API_PORT:-6550}"
# Host ports are mapped 1:1 to the in-cluster ingress (80/443) so that the OIDC
# issuer URL (http://keycloak.localhost) is identical from the browser and from
# inside the cluster. Override only if port 80 is taken - SSO expects port 80.
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"
AGENTS="${AGENTS:-2}"

# Address the argocd CLI / browser use to reach Argo CD.
ARGOCD_ADDR="argocd.localhost"
[[ "${HTTP_PORT}" != "80" ]] && ARGOCD_ADDR="argocd.localhost:${HTTP_PORT}"
ARGOCD_MANIFEST="${ARGOCD_MANIFEST:-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"

SKIP_CLUSTER="${SKIP_CLUSTER:-false}"
SKIP_ARGOCD_LOGIN="${SKIP_ARGOCD_LOGIN:-false}"

DESTROY="${DESTROY:-false}"
[[ "${1:-}" == "--destroy" || "${1:-}" == "-d" ]] && DESTROY=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- helpers --------------------------------------------------------------------
log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed"; }

# --- destroy ------------------------------------------------------------------
if [[ "${DESTROY}" == "true" ]]; then
  require k3d
  if k3d cluster list 2>/dev/null | awk '{print $1}' | grep -qx "${CLUSTER_NAME}"; then
    log "Deleting k3d cluster '${CLUSTER_NAME}'"
    k3d cluster delete "${CLUSTER_NAME}"
    log "Done"
  else
    warn "k3d cluster '${CLUSTER_NAME}' does not exist - nothing to do"
  fi
  exit 0
fi

# --- preflight -----------------------------------------------------------------
require kubectl
[[ "${SKIP_CLUSTER}" == "true" ]] || require k3d

# --- 1. k3d cluster -----------------------------------------------------------
if [[ "${SKIP_CLUSTER}" == "true" ]]; then
  log "Skipping cluster creation (SKIP_CLUSTER=true)"
elif k3d cluster list 2>/dev/null | awk '{print $1}' | grep -qx "${CLUSTER_NAME}"; then
  log "k3d cluster '${CLUSTER_NAME}' already exists - reusing it"
else
  log "Creating k3d cluster '${CLUSTER_NAME}'"
  k3d cluster create "${CLUSTER_NAME}" \
    --api-port "${API_PORT}" \
    -p "${HTTP_PORT}:80@loadbalancer" \
    -p "${HTTPS_PORT}:443@loadbalancer" \
    --agents "${AGENTS}"
fi

log "Waiting for cluster nodes to be Ready"
kubectl wait --for=condition=Ready nodes --all --timeout=180s
kubectl get nodes

# --- 1b. CoreDNS: resolve *.localhost in-cluster -----------------------------
# So Argo CD / Grafana / Jenkins / Argo Workflows can reach the Keycloak issuer
# at the same URL the browser uses (http://keycloak.localhost).
log "Configuring CoreDNS to resolve *.localhost ingress hosts inside the cluster"
kubectl apply -f "${SCRIPT_DIR}/coredns-localhost-rewrite.yaml"
kubectl -n kube-system rollout restart deployment coredns
kubectl -n kube-system rollout status deployment coredns --timeout=120s

# --- 2. Argo CD install ------------------------------------------------------
log "Creating namespace 'argocd'"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

log "Installing Argo CD"
kubectl apply \
  --server-side \
  --force-conflicts \
  -n argocd \
  -f "${ARGOCD_MANIFEST}"

log "Waiting for Argo CD CRDs to register"
kubectl wait --for=condition=Established \
  crd/applications.argoproj.io \
  crd/appprojects.argoproj.io \
  --timeout=120s

# --- 3. Ingress -------------------------------------------------------------
log "Creating Argo CD ingress"
kubectl apply -f "${SCRIPT_DIR}/argocd-ingress.yaml"

# --- 4. Insecure server + Keycloak SSO --------------------------------------
log "Patching argocd-cmd-params-cm for insecure server"
kubectl patch configmap argocd-cmd-params-cm \
  -n argocd \
  --type merge \
  -p '{"data":{"server.insecure":"true"}}'

log "Wiring Argo CD login to Keycloak (OIDC)"
kubectl patch configmap argocd-cm -n argocd --type merge \
  --patch-file "${SCRIPT_DIR}/argocd-cm-sso-patch.yaml"
kubectl patch configmap argocd-rbac-cm -n argocd --type merge \
  --patch-file "${SCRIPT_DIR}/argocd-rbac-cm-sso-patch.yaml"

log "Restarting Argo CD server"
kubectl rollout restart deployment argocd-server -n argocd

log "Waiting for Argo CD components to be available"
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=300s
kubectl -n argocd wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=argocd-application-controller --timeout=300s 2>/dev/null || \
  kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

# --- 5. Credentials ------------------------------------------------------
log "Retrieving initial admin password"
ARGOCD_PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)"

# --- 6. argocd CLI login (optional) ------------------------------------
if [[ "${SKIP_ARGOCD_LOGIN}" != "true" ]] && command -v argocd >/dev/null 2>&1; then
  log "Logging in with the argocd CLI"
  argocd login "${ARGOCD_ADDR}" \
    --username admin \
    --password "${ARGOCD_PASSWORD}" \
    --plaintext \
    --insecure \
    --grpc-web \
    || warn "argocd CLI login failed (is '${ARGOCD_ADDR}' resolvable? see /etc/hosts note below) - continuing"
else
  warn "Skipping 'argocd' CLI login (not installed or SKIP_ARGOCD_LOGIN=true)"
fi

# --- 7. Bootstrap the root Application ---------------------------------
log "Applying the root Application (platform-apps)"
kubectl apply -f "${SCRIPT_DIR}/root-application.yaml"

# --- 8. Summary --------------------------------------------------------
if command -v argocd >/dev/null 2>&1 && [[ "${SKIP_ARGOCD_LOGIN}" != "true" ]]; then
  log "Argo CD applications"
  argocd app list --grpc-web || true
fi

cat <<EOF

$(printf '\033[1;32m==> Bootstrap complete\033[0m')

  Application URLs
  ---------------------------------------------------------------------
  Argo CD          http://${ARGOCD_ADDR}
  Keycloak         http://keycloak.localhost
  Grafana          http://grafana.localhost
  Jenkins          http://jenkins.localhost
  Argo Workflows   http://workflows.localhost
  Argo Rollouts    http://rollouts.localhost
  Prometheus       http://prometheus.localhost
  Alertmanager     http://alertmanager.localhost
  ---------------------------------------------------------------------

  Argo CD admin (local fallback) : admin / ${ARGOCD_PASSWORD}
  Keycloak admin                 : admin / admin
  SSO user (all UIs)             : developer / developer   (group: platform-admins)

  argocd CLI login (copy/paste):

    argocd login ${ARGOCD_ADDR} --username admin --password '${ARGOCD_PASSWORD}' --plaintext --insecure --grpc-web

  Add '127.0.0.1  argocd.localhost keycloak.localhost grafana.localhost jenkins.localhost workflows.localhost rollouts.localhost prometheus.localhost alertmanager.localhost' to /etc/hosts if *.localhost does not resolve.

  SSO for Argo CD, Grafana, Jenkins and Argo Workflows becomes usable once the
  'keycloak' Argo CD application reports Synced/Healthy:

    kubectl -n argocd get applications
    argocd app wait keycloak --grpc-web --timeout 600
EOF
