# MinIO

Single-node, PVC-backed S3 object store. Its job in this lab: the **artifact
repository for Argo Workflows** — step logs and artifacts are written here
(`archiveLogs: true` in `apps/argo-workflows`), so `argo logs` / the Argo UI
still work after the workflow pods are garbage-collected.

| | |
| --- | --- |
| Console | http://minio.localhost — `minioadmin` / `minioadmin123` |
| S3 endpoint (in-cluster) | `minio.minio.svc.cluster.local:9000` |
| Bucket | `argo-workflows` (created by the `minio-init-buckets` Job) |
| Storage | 10 Gi `local-path` PVC |

Credentials are duplicated in `apps/argo-workflows/manifests/artifacts-secret.yaml`
(`argo-artifacts-minio` Secret) — keep them in sync.

```bash
# browse archived workflow logs
mc alias set lab http://minio.localhost minioadmin minioadmin123   # from the host
mc ls -r lab/argo-workflows
mc cat lab/argo-workflows/<workflow>/<pod>/main.log
```

Not a highly-available setup and the credentials are in Git — lab only.
