# s3-moto — an app whose infra is provisioned by an Argo Workflow

One Argo CD `Application` that:

1. **provisions** the app's cloud dependency (an S3 bucket) with Terraform, run
   in an Argo Workflow as a **PreSync hook**, and
2. writes the provisioned coordinates into a **Secret** the app consumes, then
3. **deploys** the app — an S3-backed guestbook served at `s3-moto.localhost`.

The bucket is genuinely the app's datastore: each guestbook entry is one S3
object, restart the pod and the entries are still there, delete the bucket and
the app has nothing to serve.

[Moto](https://docs.getmoto.org/) stands in for AWS on the k3d host
(`localhost:5000`, in-cluster `host.k3d.internal:5000`). Same manifests +
Terraform run against real AWS by clearing `AWS_ENDPOINT_URL` / `s3_endpoint`
and wiring real credentials (IRSA / Pod Identity on the ServiceAccount).

> Moto must run with `S3_IGNORE_SUBDOMAIN_BUCKETNAME=1` (set in
> `~/repos/moto/compose.yaml`) or every S3 call returns `NoSuchBucket`.

## How Argo CD sequences it

Argo CD has no "run a workflow" action — ordering comes from **sync waves** and
**resource hooks**. Everything the app depends on is a **PreSync hook**, so it is
(re)applied and completed *before* the app Deployment is touched:

| Phase / wave | Resource | File | Effect |
| --- | --- | --- | --- |
| PreSync -2 | `Role` + `RoleBinding` | `manifests/rbac.yaml` | let the workflow SA write the infra Secret into `s3-moto` |
| PreSync -1 | `WorkflowTemplate s3-moto-terraform` | `manifests/workflowtemplate.yaml` | the pipeline definition (re-applied each sync ⇒ never stale) |
| PreSync 0 | `Workflow s3-moto-provision` | `manifests/provision-workflow.yaml` | `terraform apply` → `verify` → **`publish-config`** writes `s3-moto-infra` Secret. Argo CD **blocks** until `Succeeded`. `BeforeHookCreation` ⇒ recreated fresh each sync |
| Sync | `s3-moto-app` Deployment/Service/Ingress + code ConfigMap | `manifests/app.yaml`, `app/main.py` | the guestbook; `envFrom` the `s3-moto-infra` Secret |
| PreDelete | `Workflow s3-moto-teardown` | `manifests/teardown-workflow.yaml` | `terraform destroy` on `argocd app delete s3-moto` |

`terraform/*.tf` is **not** synced by Argo CD — the workflow clones it from Git
at run time. Terraform owns only the bucket; state is per-run (ephemeral volume),
so `apply` runs `terraform import` first to stay idempotent.

**The real dependency:** the app `envFrom`s the `s3-moto-infra` Secret. No Secret
→ the Deployment can't start → the Argo CD app is not Healthy. The PreSync
provisioning is what makes the Secret exist.

`app/main.py` is shipped as a ConfigMap via kustomize `configMapGenerator` (the
name carries a content hash, so editing it rolls the Deployment). **Phase B**
replaces the ConfigMap with a container image built by a CI workflow.

## Use it

```bash
kubectl -n argocd get app s3-moto
argo -n argo-workflows get s3-moto-provision            # the PreSync pipeline
open http://s3-moto.localhost                            # the guestbook

# add an entry -> a new S3 object
curl "http://s3-moto.localhost/add?msg=hello"
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  aws --endpoint-url http://localhost:5000 --region us-east-1 \
  s3 ls s3://s3-consumer-demo/entries/ --recursive
```

Every `argocd app sync` re-runs the PreSync pipeline (idempotent `terraform
apply` + Secret refresh), then reconciles the app.

## Tear down

```bash
argocd app delete s3-moto     # PreDelete hook runs `terraform destroy` first
                              # (NOT `kubectl delete application` - that skips hooks)

# manual teardown without deleting the app
argo submit -n argo-workflows --from workflowtemplate/s3-moto-terraform -p mode=teardown --watch
```

## Honest limitations

- Argo CD can't see inside S3, so it can't detect drift of the bucket/objects —
  the PreSync workflow just re-`apply`s every sync. True cloud-resource drift
  detection needs Crossplane (bucket as a Kubernetes CR).
- Provisioning by Argo CD is a lab choice; in the real world infra is usually
  CI/Crossplane/a management cluster, and Argo CD deploys the app onto it.
- Moto is a mock — a green run is not a real AWS plan.
