# s3-moto — deploying an app that depends on an AWS resource

A worked example of the common pattern:

> **The app runs on Kubernetes but needs a cloud resource (here: an S3 bucket).
> Argo CD deploys the app and the pipeline; an Argo Workflow runs Terraform to
> provision the cloud resource.**

[Moto](https://docs.getmoto.org/) stands in for AWS — it already runs on the
k3d host at `localhost:5000`, reachable from inside the cluster as
`http://host.k3d.internal:5000`. Point the same manifests and Terraform at real
AWS by dropping the endpoint override and wiring real credentials.

> **Moto must run with `S3_IGNORE_SUBDOMAIN_BUCKETNAME=1`** (already set in
> `~/repos/moto/compose.yaml`). Without it, Moto reads the request `Host`
> (`host.k3d.internal`) as `<bucket>.<domain>` and every S3 call fails with
> `NoSuchBucket`. `localhost` works only because Moto special-cases it.

```
Git ──► Argo CD ──► s3-consumer Deployment              (namespace: s3-moto)
                └─► s3-moto-terraform WorkflowTemplate  (namespace: argo-workflows)

you ──► argo submit ──► Workflow:  checkout ─► terraform apply ─► verify ─► [destroy]
                                                    │
                                                    ▼
                                      Moto  (host.k3d.internal:5000)
                                                    ▲
                                                    │
s3-consumer pod ── aws s3 cp heartbeat ─────────────┘
```

## What Argo CD deploys

| File | Resource | Namespace |
| --- | --- | --- |
| `manifests/app.yaml` | `s3-consumer` Deployment + SA + ConfigMap | `s3-moto` |
| `manifests/workflowtemplate.yaml` | `s3-moto-terraform` WorkflowTemplate | `argo-workflows` |

`terraform/*.tf` is **not** applied by Argo CD — the workflow clones it from Git
at run time. One Argo CD `Application` managing two namespaces is fine; the
`default` project has no namespace restrictions. The WorkflowTemplate must live
in `argo-workflows` because the controller runs with `singleNamespace=true`.

## The app (`s3-consumer`)

A loop that writes a heartbeat object to `s3://s3-consumer-demo/` every 30s and
lists the bucket. It's ordinary AWS-SDK code; the only lab-specific parts are:

- `AWS_ENDPOINT_URL=http://host.k3d.internal:5000` — sends S3 calls to Moto
- static `test` / `test` credentials

For real AWS: remove both, and attach an IAM role to the `s3-consumer`
ServiceAccount (IRSA on EKS, or Pod Identity).

Until the bucket exists the pod stays up and logs
`cannot reach s3://... - run the s3-moto-terraform workflow first`.

## Run the provisioning workflow

```bash
# with the argo CLI
argo submit -n argo-workflows --from workflowtemplate/s3-moto-terraform --watch

# or without it
kubectl -n argo-workflows create -f apps/s3-moto/examples/run.yaml
kubectl -n argo-workflows get wf -w

# or the UI: http://workflows.localhost -> Submit new workflow -> s3-moto-terraform
```

Steps: **checkout** (git clone to a shared volume) → **apply** (`terraform init`
+ `plan` + `apply`) → **verify** (`aws s3 ls`) → **destroy** (only if
`cleanup=true`).

### Parameters

| Name | Default | Meaning |
| --- | --- | --- |
| `bucket_name` | `s3-consumer-demo` | bucket to create (keep in sync with `app.yaml`) |
| `git_revision` | `main` | ref of this repo to check out |
| `s3_endpoint` | `http://host.k3d.internal:5000` | S3 API URL; `""` = real AWS |
| `cleanup` | `false` | append a `terraform destroy` step |

## Check the result

```bash
kubectl -n s3-moto logs deploy/s3-consumer --tail=20

# from the host, straight against Moto
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  aws --endpoint-url http://localhost:5000 --region us-east-1 \
  s3 ls s3://s3-consumer-demo --recursive
```

## Notes

- **Ephemeral.** Moto keeps state until its container restarts; the workflow's
  Terraform state lives on a per-run volume that is deleted with the workflow.
  Re-running `apply` is safe — `us-east-1` bucket creation is idempotent in Moto.
- **Reset Moto** (on the host): `docker compose -f ~/repos/moto/compose.yaml restart`.
- The workflow needs egress to `github.com` and `registry.terraform.io`.
- Terraform's `provider "aws"` block (`terraform/main.tf`) toggles Moto vs AWS
  behaviour entirely on `var.s3_endpoint` — a `dynamic "endpoints"` block, and
  the AWS-only checks/credentials are skipped only when an endpoint is set.
