# products — ApplicationSet: git files (A2) + matrix (A3)

Two ApplicationSets over the **same** `product.yaml` files and Helm chart:

| | `products` (A2) | `products-matrix` (A3) |
| --- | --- | --- |
| generator | git **files** | **matrix**: git files × list(dev, prod) |
| result | `product-<name>` (3 apps) | `product-<name>-<env>` (3 × 2 = 6 apps) |
| namespace | `product-<name>` | `product-<name>-<env>` |
| replicas | from `product.yaml` | `product.yaml` value **×** the env's `replicaFactor` |

```
apps/products/
├── application.yaml            deploys both applicationset*.yaml
├── applicationset.yaml         A2 — git files
├── applicationset-matrix.yaml  A3 — matrix (files × envs)
├── chart/                      shared; namespace = .Release.Namespace, so it
│                               works for product-<name> and product-<name>-<env>
├── checkout/product.yaml   ─┐  { name, team, replicas: 3, featureFlags: [...] }
├── inventory/product.yaml   ├
└── shipping/product.yaml   ─┘
```

## The matrix generator

```yaml
generators:
  - matrix:
      generators:
        - git: { files: [ path: apps/products/*/product.yaml ] }   # A: name, replicas, ...
        - list:
            elements:
              - { env: dev,  replicaFactor: "1" }                   # B: env, replicaFactor
              - { env: prod, replicaFactor: "2" }
```

One rendered Application per **(A, B)** pair, with **both** param sets merged, so
the template can combine them: `replicas: {{ mul .replicas (atoi .replicaFactor) }}`.

- Exactly **two** child generators (nest matrices for more).
- If both generators produced a key with the same name, the **later** one wins.
- `list` values are strings → `atoi` before `mul`; `.replicas` from the file is
  already an int.

## See it

```bash
kubectl -n argocd get applicationset                       # products + products-matrix
kubectl -n argocd get applications -l product=checkout     # checkout, checkout-dev, checkout-prod
argocd appset get products-matrix                          # 6 generated param sets

curl http://checkout.products.localhost        # checkout [payments]        (A2)
curl http://checkout-dev.products.localhost    # checkout/dev [payments]    (A3)
curl http://checkout-prod.products.localhost   # checkout/prod [payments]

kubectl -n product-checkout-dev  get deploy echo -o jsonpath='{.spec.replicas}'   # 3  (3 x 1)
kubectl -n product-checkout-prod get deploy echo -o jsonpath='{.spec.replicas}'   # 6  (3 x 2)
```

## Try it

```bash
# add a "staging" env: edit applicationset-matrix.yaml, add
#   - { env: staging, replicaFactor: "1" }
# -> 3 more Applications (product-*-staging) appear on the next refresh

# a per-product change flows to every env: bump replicas in checkout/product.yaml
# -> product-checkout, -dev (x1), -prod (x2) all rescale
```

## Notes

- The shared chart renders `kind: Namespace: {{ .Release.Namespace }}` (Argo CD
  passes `--namespace <destination.namespace>` to helm), so one chart serves
  both `product-<name>` and `product-<name>-<env>` with no `fullName` parameter.
- Next: **A4** — the pull request generator (an Application per open GitHub PR).
