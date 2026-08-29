# Running workflows from the command line

The `argo` CLI talks to the cluster through your kubeconfig (no login needed).
Everything runs in the `argo-workflows` namespace.

```bash
alias argo='argo -n argo-workflows'     # save some typing
```

## Submit a workflow file

```bash
argo submit workflows/hello-world/hello-world.yaml --watch
argo submit workflows/git-script-parameters/git-script-parameters.yaml \
  -p message="hi" -p environment=staging --watch
```

- `--watch` streams the DAG/step status until it finishes
- `--wait` blocks without the live view
- `-p name=value` overrides a `spec.arguments.parameters` entry
- `--log` also tails container logs

## Submit from a WorkflowTemplate

```bash
argo template list

# the s3-moto pipelines
argo submit --from workflowtemplate/s3-moto-terraform -p mode=deploy   --watch
argo submit --from workflowtemplate/s3-moto-terraform -p mode=teardown --watch
argo submit --from workflowtemplate/s3-moto-build     -p revision=main --watch
```

## Inspect

```bash
argo list                       # recent workflows
argo get   @latest              # DAG + node status of the most recent
argo logs  @latest --follow     # or: argo logs <name>
argo logs  <name> <node-name>   # one step
```

`@latest` = the most recently created workflow. After GC the pods are gone but
`argo logs` via the UI reads them back from MinIO
(<http://workflows.localhost>).

## Re-run / stop / delete

```bash
argo resubmit @latest --watch   # new run, same spec
argo retry    <name>            # re-run only the failed nodes
argo stop     <name>            # graceful stop (runs exit handlers)
argo terminate <name>           # hard stop
argo delete   <name>            # or: argo delete --completed / --older 24h
```

## Trigger via the webhook (Argo Events)

The s3-moto build also fires from an HTTP POST — this is what a GitHub push
webhook would hit:

```bash
curl -XPOST http://s3-moto-ci.localhost/build -d '{}'
curl -XPOST http://s3-moto-ci.localhost/build \
  -H 'Content-Type: application/json' -d '{"revision":"main"}'
```

## Against the API server instead of kubeconfig

Only needed for remote access / CI. The server accepts a ServiceAccount token
(`authModes: [sso, server]`):

```bash
export ARGO_SERVER=workflows.localhost:80
export ARGO_HTTP1=true ARGO_SECURE=false
export ARGO_TOKEN="Bearer $(kubectl -n argo-workflows create token argo-workflow)"
argo list
```
