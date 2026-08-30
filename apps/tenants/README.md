# tenants — ApplicationSet (git directories generator)

Instead of one `application.yaml` per app (the app-of-apps pattern the platform
apps use), an **`ApplicationSet`** generates one Argo CD `Application` per
sub-directory here.

```
apps/tenants/
├── application.yaml      Argo CD App that deploys just the ApplicationSet
├── applicationset.yaml   generator + template
├── alpha/  deploy.yaml   ─┐
├── bravo/  deploy.yaml    ├─ each becomes  tenant-<name>  in namespace  tenant-<name>
└── charlie/ deploy.yaml  ─┘     served at  <name>.tenants.localhost
```

- `platform-apps` (the root) picks up `application.yaml` → deploys the
  `ApplicationSet`.
- The ApplicationSet's **git directories generator** lists `apps/tenants/*`
  (directories only) and renders the `template` once per directory, filling in
  `{{.path.basename}}`, `{{.path.path}}`, etc. (`goTemplate: true`).
- Each generated Application syncs its directory like any normal app.

## See it

```bash
kubectl -n argocd get applicationset tenants
kubectl -n argocd get applications -l tenant           # tenant-alpha/bravo/charlie
argocd appset get tenants

curl http://alpha.tenants.localhost      # tenant alpha :: the first tenant
curl http://charlie.tenants.localhost    # (3 replicas)
```

## Try it

```bash
mkdir apps/tenants/delta && cp apps/tenants/alpha/deploy.yaml apps/tenants/delta/
sed -i 's/alpha/delta/g' apps/tenants/delta/deploy.yaml
git add apps/tenants/delta && git commit -m "tenant delta" && git push
# within ~3 min: a "tenant-delta" Application appears, http://delta.tenants.localhost works

git rm -r apps/tenants/delta && git commit -m "drop delta" && git push
# the Application AND its namespace are pruned (prune: true + CreateNamespace)
```

## Notes

- The ApplicationSet polls Git on the same interval as Argo CD's app refresh
  (~3 min); `argocd appset get tenants` shows the generated params.
- `goTemplateOptions: [missingkey=error]` makes a typo in a `{{...}}` fail loudly
  instead of rendering an empty string.
- Other generators worth knowing: **list** (hard-coded values), **cluster**
  (fan out across registered clusters), **matrix** (cross-product of two
  generators), **pull request** (an Application per open GitHub PR — preview
  environments, uses the GitHub API so it works without inbound webhooks).
