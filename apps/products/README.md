# products — ApplicationSet, git files generator (roadmap A2)

The **git files** generator reads a config file per instance. Its parsed YAML
becomes the template values — with **real types** (int, list, map), not strings.

| | list (A1) | git files (A2) |
| --- | --- | --- |
| instances defined in | one central file (`applicationset.yaml`) | `product.yaml` **next to each product** |
| value types | strings only (`replicas: "2"` → `\| int`) | native YAML (`replicas: 3`, `featureFlags: [...]`) |
| who edits them | whoever owns the ApplicationSet | whoever owns that folder |

```
apps/products/
├── application.yaml       root deploys just the ApplicationSet
├── applicationset.yaml    git-files generator + template
├── chart/                 one shared Helm chart
├── checkout/product.yaml  ─┐  name, team, replicas(int), featureFlags(list), resources(map)
├── inventory/product.yaml  ├─ each -> product-<name>, ns product-<name>,
└── shipping/product.yaml  ─┘     <name>.products.localhost
```

## See it

```bash
kubectl -n argocd get applicationset products
argocd appset get products                       # generated params, one set per file

curl http://checkout.products.localhost           # checkout [payments] :: ... :: flags=fast-path,one-click
curl http://shipping.products.localhost           # ... :: flags=none   (empty list)

kubectl -n product-checkout get deploy echo -o jsonpath='{.spec.replicas}'   # 3  (a real int)
kubectl -n product-checkout get cm product-info -o yaml                       # the list survived
```

## Try it

```bash
# 1. change a value in place
sed -i 's/replicas: 3/replicas: 1/' apps/products/checkout/product.yaml
git commit -am "checkout: scale down" && git push
argocd app get products --hard-refresh
# -> product-checkout Deployment scales to 1

# 2. new product
mkdir apps/products/search
cat > apps/products/search/product.yaml <<'YAML'
name: search
team: discovery
replicas: 2
message: "full-text search"
featureFlags: [typeahead]
resources: { cpu: 20m, memory: 32Mi }
YAML
git add apps/products/search && git commit -m "product: search" && git push
argocd app get products --hard-refresh
# -> product-search appears
```

## Notes

- The generator merges `.path.*` (basename, path, segments) into the params, so
  you can use either the file contents *or* where the file lives.
- `helm.valuesObject` (vs `helm.parameters`) is what lets `replicas` stay an int
  and `featureFlags` stay a list. `{{ .featureFlags | toJson }}` renders inline
  JSON, which is valid YAML.
- `goTemplateOptions: [missingkey=error]` → a `product.yaml` missing a key the
  template needs fails the whole ApplicationSet loudly (check
  `argocd appset get products` / the applicationset-controller logs).
- Next: **A3 (matrix)** combines this with an environments generator to get
  `product × env` Applications.
