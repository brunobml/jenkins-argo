# s3-moto — infra + app, provisioned and deployed by Argo

An end-to-end example of Argo CD and Argo Workflows doing the two halves of a
delivery pipeline:

- **Argo Workflows** = the imperative tasks with a start and an end: run
  Terraform to provision the app's cloud dependency, and build the app's
  container image.
- **Argo CD** = continuous reconciliation: deploy the app, keep it matched to
  Git, and roll new images out as they are built.

The app is an **S3-backed guestbook** at `http://s3-moto.localhost`. Each entry
is one S3 object — restart the pod and the entries are still there, delete the
bucket and the app has nothing to serve. [Moto](https://docs.getmoto.org/)
stands in for AWS on the k3d host (`localhost:5000`, in-cluster
`host.k3d.internal:5000`).

> Moto must run with `S3_IGNORE_SUBDOMAIN_BUCKETNAME=1` (set in
> `~/repos/moto/compose.yaml`) or every S3 call returns `NoSuchBucket`.

## The two loops

### Deploy loop (Argo CD)

Every `argocd app sync` (Git change, or an Image Updater write-back):

| Phase / wave | Resource | Effect |
| --- | --- | --- |
| PreSync -2 | `rbac.yaml` Role/RoleBinding | let the workflow SA write the infra Secret into `s3-moto` |
| PreSync -1 | `workflowtemplate.yaml` | the provisioning pipeline definition (re-applied ⇒ never stale) |
| PreSync 0 | `provision-workflow.yaml` | `terraform apply` → `verify` → `publish-config` writes the `s3-moto-infra` Secret. Argo CD **blocks** until `Succeeded`. `BeforeHookCreation` ⇒ fresh each sync |
| Sync | `app.yaml` (+ `image-updater.yaml`, `ci-*.yaml`) | the guestbook Deployment/Service/Ingress; `envFrom` the `s3-moto-infra` Secret |
| PreDelete | `teardown-workflow.yaml` | `terraform destroy` on `argocd app delete s3-moto` |

**The real dependency:** the app `envFrom`s `s3-moto-infra`. No Secret → the
Deployment can't start. The PreSync provisioning is what makes it exist, and it
carries the *actual* `terraform output` (bucket name), not a hard-coded value.

### Build loop (Argo Workflows + Argo Events + Image Updater)

```text
POST http://s3-moto-ci.localhost/build
      │  (or a GitHub push webhook)
      ▼
Argo Events  EventSource → Sensor  ── submits ──▶  Workflow: s3-moto-build
                                                     checkout ─▶ kaniko
                                                                   │ push
                                                                   ▼
                                          k3d-registry:5000/s3-moto-app:<git-sha>
                                                                   │
                        Argo CD Image Updater (polls every 2m) ◀───┘
                          sets .spec.source.kustomize.images on the s3-moto App
                                                                   │
                                          Argo CD renders + syncs ─┘  → new pod
```

- `app/Dockerfile` + `app/main.py` are the build source (not synced by Argo CD).
- `image-updater.yaml` is an `ImageUpdater` CR (Image Updater v1.x): watch
  `k3d-registry:5000/s3-moto-app`, strategy `newest-build`, tags matching a git
  sha, write-back method `argocd` (patches the Application — no Git credentials).
- `bootstrap/root-application.yaml` has an `ignoreDifferences` so the root
  app-of-apps doesn't revert Image Updater's kustomize-image override.

## Try the whole thing

```bash
# 1. change the app
$EDITOR apps/s3-moto/app/main.py
git commit -am "s3-moto: tweak" && git push

# 2. trigger a build (a GitHub webhook would do this automatically)
curl -XPOST http://s3-moto-ci.localhost/build -d '{}'
argo -n argo-workflows list                       # watch s3-moto-build-*

# 3. Image Updater rolls it out within ~2-3 min (or force it):
argocd app sync s3-moto
curl -s http://s3-moto.localhost/                 # new code, entries intact
```

Run pieces by hand:

```bash
argo submit -n argo-workflows --from workflowtemplate/s3-moto-build --watch
argo submit -n argo-workflows --from workflowtemplate/s3-moto-terraform -p mode=teardown --watch
argocd app delete s3-moto      # PreDelete hook runs terraform destroy first
```

## Honest limitations

- **Argo CD can't see inside S3** — no drift detection of the bucket/objects.
  The PreSync workflow just re-`apply`s every sync. Real cloud-resource drift
  detection needs Crossplane (bucket as a Kubernetes CR).
- **Provisioning by Argo CD is a lab choice.** In the real world infra is
  CI/Crossplane/a management cluster; Argo CD deploys onto it.
- **Terraform re-runs on every sync** (~1 min), including on each image
  rollout. Idempotent (`import` → `plan` → `apply`), just not free.
- **Image Updater → deploy lag** is the Argo CD reconcile interval (~3 min)
  unless you `argocd app sync`.
- **The registry is HTTP and unauthenticated**, images are `--insecure`. Fine
  for an in-cluster lab registry, not for anything shared.
- Moto is a mock — a green run is not a real AWS plan.
