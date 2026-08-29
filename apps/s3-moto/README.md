# s3-moto — infra-then-app continuous deployment with Argo CD + Argo Workflows

One Argo CD `Application` drives a full deploy chain:

1. **provision** the cloud resource (S3 bucket) with Terraform, run in an Argo
   Workflow, and
2. **deploy** an artifact onto it (`index.html` → `s3://…/index.html`), and
3. keep that artifact in sync with Git — edit the file, push, it re-deploys.

Analogy: the **bucket** is the infra (think: a cluster / DB / queue), the
**`index.html`** is the app release running on it. [Moto](https://docs.getmoto.org/)
stands in for AWS on the k3d host (`localhost:5000`, in-cluster
`host.k3d.internal:5000`). Same manifests + Terraform run against real AWS by
dropping the endpoint override and wiring real credentials.

> Moto must run with `S3_IGNORE_SUBDOMAIN_BUCKETNAME=1` (set in
> `~/repos/moto/compose.yaml`) or every S3 call returns `NoSuchBucket`.

## How Argo CD sequences it

Argo CD has no built-in "run a workflow" action — you wire ordering with
**sync waves** and **resource hooks**:

| Order | Resource | File | Effect |
| --- | --- | --- | --- |
| wave 0 | `WorkflowTemplate s3-moto-terraform` | `manifests/workflowtemplate.yaml` | the reusable pipeline definition |
| wave 1 | `Workflow s3-moto-provision` | `manifests/provision-workflow.yaml` | `terraform apply`; Argo CD **blocks** until it is `Succeeded` |
| wave 2 | `ConfigMap s3-moto-artifact` + `s3-consumer` app | `manifests/artifact.yaml`, `manifests/app.yaml` | the artifact and a pod that reads it |
| PostSync hook | `Job s3-moto-deploy` | `manifests/deploy-job.yaml` | `aws s3 cp` the artifact to the bucket, every sync |
| PreDelete hook | `Workflow s3-moto-teardown` | `manifests/teardown-workflow.yaml` | `terraform destroy` when you `argocd app delete s3-moto` |

`terraform/*.tf` is **not** synced by Argo CD — the workflow clones it from Git
at run time. Terraform owns only the bucket; the artifact is the PostSync job's
job. State is per-run (ephemeral volume) so `apply` runs `terraform import` first
to stay idempotent.

## The CD loop

```bash
# 1. edit the release
$EDITOR apps/s3-moto/artifact.yaml     # change "Release v1" -> "Release v2"
git commit -am "s3-moto: release v2" && git push

# 2. Argo CD syncs (or: argocd app sync s3-moto)
#    - provision workflow: already Succeeded, no-op
#    - ConfigMap updates
#    - PostSync job uploads the new index.html

# 3. watch the app pick it up
kubectl -n s3-moto logs -f deploy/s3-consumer
#   --- [..] current release ---
#   <h1>Hello from s3-moto</h1>
#   <p>Release v2 - ...</p>
```

`git revert` the release commit → the previous `index.html` is restored in S3.

## First deploy

Commit + push; the root app picks up `s3-moto`. Then:

```bash
kubectl -n argocd get app s3-moto
argo -n argo-workflows list                       # the provision workflow
kubectl -n s3-moto get pods,cm,job
kubectl -n s3-moto logs deploy/s3-consumer
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  aws --endpoint-url http://localhost:5000 --region us-east-1 s3 ls s3://s3-consumer-demo --recursive
```

## Re-provision / tear down

```bash
# force the provision workflow to run again (e.g. after editing the template)
kubectl -n argo-workflows delete wf s3-moto-provision      # Argo CD recreates it

# destroy the bucket + everything: PreDelete hook runs terraform destroy
argocd app delete s3-moto        # NOT `kubectl delete application` - that skips hooks

# manual teardown without deleting the app
argo submit -n argo-workflows --from workflowtemplate/s3-moto-terraform -p mode=teardown --watch
```

## Honest limitations

- Argo CD can't see inside S3 — it can't detect that the S3 object drifted from
  Git. The PostSync job just re-uploads on **every** sync (idempotent, cheap).
  True drift-detection of a cloud resource needs something like Crossplane
  (bucket/object as Kubernetes CRs).
- Provisioning by Argo CD is a deliberate lab choice. In the real world infra is
  usually created by CI/Crossplane/a management cluster; Argo CD deploys the app.
- Moto is a mock. A green run here is not a substitute for a real plan against an
  isolated AWS account.
