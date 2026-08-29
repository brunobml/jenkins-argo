# Keycloak

OIDC identity provider for the lab. Runs in **dev mode** (`start-dev`, H2
in-memory) and imports the `platform` realm from `manifests/realm.yaml` on every
start, so the realm is always reproducible from Git and manual console changes do
not survive a pod restart.

| Resource | File |
| --- | --- |
| Argo CD Application | `application.yaml` |
| Realm + clients + users | `manifests/realm.yaml` (ConfigMap mounted at `/opt/keycloak/data/import`) |
| Deployment / Service / Ingress | `manifests/deployment.yaml`, `manifests/service.yaml`, `manifests/ingress.yaml` |

- Console: http://keycloak.localhost — `admin` / `admin`
- Issuer: `http://keycloak.localhost/realms/platform`
- Clients: `argocd`, `grafana`, `argo-workflows`, `jenkins` (fixed secrets in the realm file)
- Users: `developer` / `developer` (`platform-admins`), `viewer` / `viewer` (`platform-viewers`)

In-cluster clients reach the issuer because `bootstrap/coredns-localhost-rewrite.yaml`
points `*.localhost` at the Traefik service. Full notes:
[bootstrap/README.md](../../bootstrap/README.md#sso-with-keycloak).
