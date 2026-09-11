# apps/platform — the platform apps, via ApplicationSet

Roadmap A5. This replaces the old app-of-apps `directory` root that recursed
`apps/` and applied every `*/application.yaml`.

## How it works

- `applicationset.yaml` — a **git files** generator over `params/*.yaml`. One
  file per platform app.
- `params/<name>.yaml` — flat config: what repo/chart/path, which namespace,
  helm values, sync options. See the schema comment in `applicationset.yaml`.
- The `template` block holds only the fields every app shares. `templatePatch`
  (a Go template emitting a JSON merge patch) builds the parts that vary:
  `source` vs `sources`, `chart` vs `path`, `directory.include`, finalizers,
  `syncOptions`.

`bootstrap/root-application.yaml` points here with
`directory.include: applicationset.yaml`, so the root now manages exactly one
object (this ApplicationSet) instead of ~17 Applications.

## Add a platform app

Drop a `params/<name>.yaml` in. The ApplicationSet picks it up on the next
git poll. Delete the file to remove the app (the generated Application is
pruned).

## Not managed here

`apps/products`, `apps/regions`, `apps/tenants` are themselves ApplicationSets —
`params/{products,regions,tenants}.yaml` deploy those manifests (they carry
`directoryInclude`), the child apps they generate are their own thing.
