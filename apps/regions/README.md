# regions — ApplicationSet, list generator (roadmap A1)

The **simplest** ApplicationSet generator. Compare with `apps/tenants`
(directories generator):

| | `tenants` (A0) | `regions` (A1) |
| --- | --- | --- |
| instances defined by | one directory per app | one inline list element per app |
| per-instance manifests | separate folder each | **one shared Helm chart** |
| per-instance values | (the folder name) | list-element keys → Helm `parameters` |

```
apps/regions/
├── application.yaml       root app-of-apps deploys just the ApplicationSet
├── applicationset.yaml    list generator (3 elements) + template
└── chart/                 one Helm chart, rendered 3× with different values
```

Result: `regions-us` / `regions-eu` / `regions-apac` Applications, in namespaces
`region-us` / `region-eu` / `region-apac`, served at `<region>.regions.localhost`
(`us` gets 2 replicas, the others 1).

## See it

```bash
kubectl -n argocd get applicationset regions
kubectl -n argocd get applications -l demo=regions
argocd appset get regions            # shows the generated params

curl http://us.regions.localhost     # region US :: N. Virginia :: 2 replica(s)
curl http://eu.regions.localhost
kubectl get pods -A -l app=echo
```

## Try it

```bash
# add a region: edit apps/regions/applicationset.yaml, add
#   - region: sa
#     city: São Paulo
#     replicas: "1"
git commit -am "regions: add sa" && git push
argocd app get regions --hard-refresh    # or wait ~3 min for the repo cache
# -> regions-sa appears, http://sa.regions.localhost works

# remove that element + push -> regions-sa Application AND namespace region-sa pruned
```

## Notes

- **List values are always strings.** `replicas: "2"` in the generator →
  `.Values.replicas` is `"2"` → the chart does `{{ .Values.replicas | int }}`
  for the Deployment field. (Alternatively: `generators.list` supports
  `elementsYaml` / a `template.spec.source.helm.valuesObject` for real types.)
- The chart renders its own `Namespace` so a removed list entry prunes cleanly
  (`prune: true`), instead of leaving an empty namespace behind.
- Next: **A2** replaces this inline list with a `tenant.yaml` file per directory
  (git *files* generator).
