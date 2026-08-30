# Argo learning roadmap

A progressive path through the Argo project. Work top to bottom — each step is a
small, self-contained lab in this repo. Ask and it gets built; then you poke at
it, break it, read the CRD.

Legend:  `[x]` done  `[ ]` next  `( * )` stretch / optional

---

## Done — the baseline you already have

- **Argo CD** — app-of-apps, sync waves, PreSync / PostSync / PreDelete hooks,
  Image Updater (CR-based), `ignoreDifferences`, multi-source apps
- **Argo Workflows** — WorkflowTemplate, CronWorkflow, `steps`, git input
  artifacts, `volumeClaimTemplates`, MinIO artifact repo + `archiveLogs`, kaniko
  builds, terraform, `podGC` / `ttlStrategy`, `workflowDefaults`
- **Argo Events** — webhook EventSource, Sensor, `argoWorkflow` trigger, poll CI
- **Argo Rollouts** — `canary-demo` (replica-based canary + basic analysis)
- **ApplicationSet** — git **directories** generator (`apps/tenants`)
- **Platform** — Keycloak SSO for all UIs, Alloy→Loki, Prometheus, Grafana
  dashboards, in-cluster registry

---

## Unit A — ApplicationSet (finish the tour)

- [x] **A0. git directories generator** — `apps/tenants`, one App per folder
- [ ] **A1. list generator** — deploy one demo app to 3 namespaces from a
  hard-coded list. Smallest possible ApplicationSet. *Teaches:* `generators.list`,
  the simplest template substitution.
- [ ] **A2. git files generator** — put a `tenant.yaml` (replicas, message, host)
  in each `apps/tenants/<name>/` and drive the template from it instead of the
  folder name. *Teaches:* passing **structured values** into the template,
  `{{.replicas}}` vs `{{.path.basename}}`.
- [ ] **A3. matrix generator** — `tenants × {dev,prod}` → 6 Applications.
  *Teaches:* combining generators, nested params, `goTemplate` ranges.
- [ ] **A4. pull request generator** — an `preview-pr-<n>` Application per open
  GitHub PR: own namespace, deployed from the PR branch, torn down on
  merge/close. Polls the GitHub API (outbound — works without inbound webhooks).
  *Needs:* a fine-grained read-only GitHub token (contents + pull-requests).
  *Teaches:* the real value of ApplicationSet — **ephemeral preview
  environments**, `requeueAfterSeconds`, `template.metadata` labels for cleanup.
- [ ] ( * ) **A5. convert `platform-apps`** — replace the app-of-apps `directory`
  root with a git-files generator + a small `params.yaml` per app. Bigger
  refactor; the "production" way to run many apps.

---

## Unit B — Argo Rollouts (make progressive delivery real)

- [ ] **B1. analysis-driven canary** — extend `canary-demo` with an
  `AnalysisTemplate` that queries **Prometheus** (success rate, p95 latency).
  Canary auto-**rolls back** when a threshold is breached; auto-promotes when
  green. Add a Grafana panel. *Teaches:* `AnalysisTemplate` / `AnalysisRun`,
  metric providers, `failureLimit`, `inconclusive`, rollback behaviour.
- [ ] **B2. blue-green** — a second demo app with the blue-green strategy:
  `activeService` / `previewService`, `autoPromotionEnabled: false`, manual
  `kubectl argo rollouts promote`. *Teaches:* the other rollout strategy, preview
  routing, promotion gates.
- [ ] **B3. Experiment** — run baseline vs canary side-by-side for a fixed
  duration with analysis attached. *Teaches:* the `Experiment` CRD, ephemeral
  ReplicaSets, A/B style comparison.
- [ ] ( * ) **B4. real traffic routing** — weighted canary at the **Traefik**
  ingress (TraefikService), not just replica counts. *Teaches:* `trafficRouting`,
  why replica-weight canaries are only an approximation.

---

## Unit C — Argo Workflows (pipeline patterns)

- [ ] **C1. DAG template** — rewrite a `steps` workflow as a `dag` with
  `dependencies`: fan out (build ‖ lint ‖ scan) then fan in (deploy). *Teaches:*
  `dag` vs `steps`, `depends` logic (`A && (B || C)`).
- [ ] **C2. artifact passing** — step 1 produces an artifact (a report / tarball)
  to MinIO, step 2 consumes it as an input artifact. *Teaches:*
  `outputs.artifacts` → `inputs.artifacts`, artifact GC.
- [ ] **C3. suspend / approval gate** — a `suspend` template between build and
  deploy; resume with `argo resume` or the UI; add a timeout. *Teaches:*
  human-in-the-loop CD, `suspend` with `duration`, `WorkflowEventBinding` to
  resume from an event.
- [ ] **C4. exit handlers + hooks** — `onExit` for cleanup, `hooks:` to fire a
  notification on `Failed`. *Teaches:* `workflow.status` in templates, lifecycle
  hooks vs `onExit`.
- [ ] **C5. loops** — `withItems` / `withParam` (fan out over a JSON list from a
  previous step) / `withSequence`. *Teaches:* dynamic parallelism.
- [ ] **C6. retries + conditionals** — `retryStrategy` (backoff, `limit`,
  `retryPolicy`), `when:` expressions, `continueOn`. *Teaches:* resilient steps.
- [ ] ( * ) **C7. odds and ends** — `memoize` (cache a step by key); `http`
  template (call an API with no container); `resource` template (create/patch a
  k8s object); `data` template (process an artifact listing).

---

## Unit D — Argo Events (event-driven, beyond webhooks)

- [ ] **D1. resource EventSource** — fire a workflow when a k8s object changes
  (e.g. a new `Workflow`, a `ConfigMap` edit). *Teaches:* `resource` source,
  watching the API, `eventTypes`.
- [ ] **D2. MinIO bucket-notification EventSource** — a workflow fires when an
  object lands in a bucket (you already run MinIO). *Teaches:* `minio` /
  `s3` source, bucket notifications, event payloads.
- [ ] **D3. calendar EventSource** — cron-style triggers through Events (contrast
  with `CronWorkflow`). *Teaches:* `calendar` source, when Events vs Workflows
  scheduling makes sense.
- [ ] **D4. multi-dependency Sensor** — trigger only when **A and B** have both
  fired; dependency groups; `circuit` / `switch`. *Teaches:* correlating events.
- [ ] **D5. event filters** — data / context / `expr` filters
  (`body.action == "opened"`), so one EventSource feeds many Sensors. *Teaches:*
  `filters`, `filtersLogicalOperator`.
- [ ] **D6. non-workflow triggers** — a Sensor that **creates/patches a k8s
  object**, calls an **HTTP** endpoint, or posts to **Slack**. *Teaches:*
  trigger types other than `argoWorkflow`, `parameters` templating into the
  trigger.
- [ ] ( * ) **D7. WorkflowEventBinding** — submit workflows from events with no
  Sensor at all; EventBus (jetstream) tuning.

---

## Unit E — Operating Argo CD (the team / production layer)

- [ ] **E1. AppProject** — a real project instead of `default`: allowed source
  repos, destination namespaces/clusters, permitted resource kinds; project RBAC
  roles + project tokens. Move `tenants` into it. *Teaches:* blast-radius
  control, `AppProject` spec.
- [ ] **E2. sync windows** — allow/deny automatic sync by schedule (e.g. freeze
  prod Fri–Mon). *Teaches:* `spec.syncWindows`, `kind: deny/allow`,
  `manualSync`.
- [ ] **E3. argocd-notifications** — notify on `on-sync-succeeded`,
  `on-sync-failed`, `on-health-degraded` → a webhook (or Slack). *Teaches:*
  triggers, templates, subscriptions via annotations.
- [ ] **E4. custom health check** — a Lua `resource.customizations` health
  assessment for a CRD Argo CD doesn't understand out of the box. *Teaches:* how
  Argo CD decides "Healthy", `argocd-cm` customizations.
- [ ] ( * ) **E5. SSO group RBAC** — map Keycloak groups → Argo CD roles per
  project (you have Keycloak + `platform-admins` already). Resource exclusions.

---

## Unit F — Multi-environment GitOps (capstone — ties it together)

- [ ] **F1. Kustomize base + overlays** — one app, `overlays/dev` +
  `overlays/prod` differing in replicas / resources / host / image tag.
  *Teaches:* overlay structure, patches, `images:`.
- [ ] **F2. fan out** — an ApplicationSet (matrix `env × app`, or a
  directory-per-env generator) creates dev + prod Applications, each pointed at
  its overlay. *Teaches:* environments as generator params.
- [ ] **F3. promotion workflow** — after the dev canary passes analysis (Unit B),
  an Argo Workflow **bumps the prod overlay's image tag** (git commit) — gated by
  a `suspend` approval (Unit C3). Argo CD then rolls prod. *Teaches:* the whole
  loop: build → test → analyse → promote → deploy.
- [ ] ( * ) **F4. PR-based promotion** — the promotion workflow opens a **PR**
  instead of committing; a human merges. Progressive/ordered sync across envs.

---

## Suggested linear order

If you just want one queue: **A1 → A2 → A3 → C3 → B1 → A4 → D2 → C1 → C2 →
D4/D5 → E1 → E2 → E3 → F1 → F2 → F3**, then cherry-pick the `( * )` items.

Rationale: finish ApplicationSet basics while it's fresh (A1–A3); grab the quick
high-value `suspend` gate (C3); do analysis-Rollouts (B1) since Prometheus is
ready; then preview envs (A4) and real events (D2); DAG + artifacts (C1–C2);
correlate/filter events (D4/D5); the operating layer (E1–E3); and finally wire
it all into a dev→prod promotion (F).
