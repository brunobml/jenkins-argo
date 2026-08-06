# ARGO EVENTS DEMO  

The best first use case for this lab is:

```text
curl / Postman
      ↓
Webhook EventSource
      ↓
JetStream EventBus
      ↓
Sensor
      ↓
Argo Workflow in argo-workflows
      ↓
Workflow prints the webhook message
```

The EventBus transports events from EventSources to Sensors, while the Sensor creates the Workflow after its event dependency is satisfied. ([Argo Project][1])

## 1. Verify the EventBus

Your Argo Events installation should already have a default EventBus:

```bash
kubectl get eventbus -n argo-events
```

Wait until it reports `Deployed`:

```bash
kubectl get eventbus default -n argo-events -w
```

Also check the JetStream pods:

```bash
kubectl get pods -n argo-events
```

A default JetStream EventBus normally creates three JetStream replicas. ([Argo Project][2])

---

# 2. Create a GitOps application for the demo

Keep the Argo Events installation separate from the resources that use it:

```bash
mkdir -p apps/argo-events-demo/manifests
```

Your structure will become:

```text
apps/
├── argo-events/
│   └── application.yaml
└── argo-events-demo/
    ├── application.yaml
    └── manifests/
        ├── rbac.yaml
        ├── webhook-eventsource.yaml
        ├── webhook-ingress.yaml
        └── webhook-sensor.yaml
```

## `apps/argo-events-demo/application.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argo-events-demo
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: https://github.com/brunobml/jenkins-argo.git
    targetRevision: main
    path: apps/argo-events-demo/manifests

  destination:
    server: https://kubernetes.default.svc
    namespace: argo-events

  syncPolicy:
    automated:
      prune: true
      selfHeal: true

    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
```

---

# 3. Give the Sensor permission to create Workflows

The Sensor runs in `argo-events`, but it will create Workflow resources in your existing `argo-workflows` namespace.

## `apps/argo-events-demo/manifests/rbac.yaml`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: workflow-trigger-sa
  namespace: argo-events

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: workflow-trigger
  namespace: argo-workflows
rules:
  - apiGroups:
      - argoproj.io
    resources:
      - workflows
    verbs:
      - create
      - get
      - list
      - watch

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: workflow-trigger
  namespace: argo-workflows
subjects:
  - kind: ServiceAccount
    name: workflow-trigger-sa
    namespace: argo-events
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: workflow-trigger
```

A Sensor using an Argo Workflow trigger needs a service account with permission to create and list Workflow resources. ([Argo Project][3])

You can validate this permission later:

```bash
kubectl auth can-i create workflows.argoproj.io \
  --as=system:serviceaccount:argo-events:workflow-trigger-sa \
  -n argo-workflows
```

Expected:

```text
yes
```

---

# 4. Create the webhook EventSource

## `apps/argo-events-demo/manifests/webhook-eventsource.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: lab-webhook
  namespace: argo-events
spec:
  service:
    ports:
      - name: webhook
        port: 12000
        targetPort: 12000

  webhook:
    deploy:
      port: "12000"
      endpoint: /deploy
      method: POST
```

This creates:

* An EventSource pod
* A ClusterIP service
* An HTTP endpoint at `/deploy`
* A published event named `deploy`

Webhook request data is placed under:

```text
data.body
data.header
```

Therefore, a request containing:

```json
{
  "message": "Hello from Argo Events"
}
```

can be read by the Sensor from:

```text
body.message
```

That event structure is documented by Argo Events. ([Argo Project][4])

---

# 5. Expose the webhook through Traefik

Because your k3d cluster already uses Traefik and maps host port `8080` to cluster port `80`, use a `.localhost` hostname.

## `apps/argo-events-demo/manifests/webhook-ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lab-webhook
  namespace: argo-events
spec:
  ingressClassName: traefik

  rules:
    - host: events.localhost
      http:
        paths:
          - path: /deploy
            pathType: Prefix
            backend:
              service:
                name: lab-webhook-eventsource-svc
                port:
                  number: 12000
```

Argo Events generates the EventSource service name using this pattern:

```text
<eventsource-name>-eventsource-svc
```

In this example:

```text
lab-webhook-eventsource-svc
```

---

# 6. Create the Sensor

The Sensor will:

1. Wait for the `deploy` event from `lab-webhook`
2. Read `body.message`
3. Create an Argo Workflow
4. Pass the message as a Workflow parameter

## `apps/argo-events-demo/manifests/webhook-sensor.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: lab-webhook
  namespace: argo-events
spec:
  template:
    serviceAccountName: workflow-trigger-sa

  dependencies:
    - name: deploy-request
      eventSourceName: lab-webhook
      eventName: deploy

  triggers:
    - template:
        name: submit-lab-workflow

        argoWorkflow:
          operation: submit

          source:
            resource:
              apiVersion: argoproj.io/v1alpha1
              kind: Workflow

              metadata:
                generateName: event-webhook-
                namespace: argo-workflows

              spec:
                serviceAccountName: argo-workflow

                entrypoint: print-message

                arguments:
                  parameters:
                    - name: message
                      value: Default message

                templates:
                  - name: print-message
                    inputs:
                      parameters:
                        - name: message

                    container:
                      image: alpine:3.22
                      command:
                        - /bin/sh
                        - -c
                      args:
                        - |
                          echo "================================="
                          echo "Workflow triggered by Argo Events"
                          echo "Message: {{inputs.parameters.message}}"
                          echo "================================="

          parameters:
            - src:
                dependencyName: deploy-request
                dataKey: body.message
              dest: spec.arguments.parameters.0.value
```

The important distinction is:

```yaml
spec:
  template:
    serviceAccountName: workflow-trigger-sa
```

That account belongs to the **Sensor** and allows it to submit Workflows.

Inside the generated Workflow:

```yaml
spec:
  serviceAccountName: argo-workflow
```

That account belongs to the **Workflow** and allows its pods to execute correctly. Argo’s documentation treats these as separate service-account responsibilities. ([Argo Project][3])

---

# 7. Commit and deploy

```bash
git add apps/argo-events-demo

git commit -m "Add Argo Events webhook workflow demo"

git push
```

Force your root application to discover it:

```bash
argocd app sync platform-apps --grpc-web
```

Then synchronize the demo:

```bash
argocd app sync argo-events-demo --grpc-web
```

Check its status:

```bash
argocd app get argo-events-demo --grpc-web
```

---

# 8. Verify the EventSource and Sensor

```bash
kubectl get eventsource,sensor -n argo-events
```

Expected:

```text
NAME                                      AGE
eventsource.argoproj.io/lab-webhook       ...

NAME                                 AGE
sensor.argoproj.io/lab-webhook       ...
```

Check the generated pods and service:

```bash
kubectl get pods,svc -n argo-events
```

You should see resources resembling:

```text
pod/lab-webhook-eventsource-...
pod/lab-webhook-sensor-...
service/lab-webhook-eventsource-svc
```

Inspect their status:

```bash
kubectl describe eventsource lab-webhook -n argo-events
```

```bash
kubectl describe sensor lab-webhook -n argo-events
```

Check the logs:

```bash
kubectl logs \
  -n argo-events \
  -l eventsource-name=lab-webhook \
  --all-containers=true \
  --tail=100
```

```bash
kubectl logs \
  -n argo-events \
  -l sensor-name=lab-webhook \
  --all-containers=true \
  --tail=100
```

---

# 9. Trigger the Workflow

From your Mac or WSL terminal:

```bash
curl -i \
  -X POST \
  http://events.localhost:8080/deploy \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "Hello from my Argo Events lab"
  }'
```

The HTTP response should be successful.

Now check the Workflows:

```bash
kubectl get workflows -n argo-workflows
```

You should see something similar to:

```text
NAME                    STATUS      AGE
event-webhook-abc12     Succeeded   20s
```

Watch the newest Workflow:

```bash
argo list -n argo-workflows
```

```bash
argo logs @latest -n argo-workflows
```

Expected output:

```text
=================================
Workflow triggered by Argo Events
Message: Hello from my Argo Events lab
=================================
```

The Workflow should also appear in your existing **Argo Workflows UI**.

---

# 10. Test different parameters

Send another event:

```bash
curl \
  -X POST \
  http://events.localhost:8080/deploy \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "Deploy customer-api to development"
  }'
```

Then:

```bash
argo list -n argo-workflows
```

Every webhook call should generate a new Workflow.

## What each UI will show

**Argo CD UI:**

```text
argo-events-demo
├── ServiceAccount
├── Role
├── RoleBinding
├── EventSource
├── Sensor
└── Ingress
```

**Argo Workflows UI:**

```text
event-webhook-xxxxx
└── print-message
    └── container logs
```

Argo Events itself handles the webhook and trigger logic, while Argo Workflows provides the visual execution history.

One possible issue is that your Workflow controller may be configured to watch only `argo-workflows`. That is fine for this example because the generated Workflow explicitly uses:

```yaml
metadata:
  namespace: argo-workflows
```

Argo’s getting-started documentation specifically notes that the Workflow controller must be able to watch the namespace where triggered Workflows are created. ([Argo Project][5])

[1]: https://argoproj.github.io/argo-events/concepts/eventbus/?utm_source=chatgpt.com "EventBus - Argo Events - The Event-Based Dependency Manager for Kubernetes"
[2]: https://argoproj.github.io/argo-events/eventbus/jetstream/?utm_source=chatgpt.com "Jetstream - Argo Events - The Event-Based Dependency Manager for Kubernetes"
[3]: https://argoproj.github.io/argo-events/service-accounts/?utm_source=chatgpt.com "Service Accounts - Argo Events - The Event-Based Dependency Manager for Kubernetes"
[4]: https://argoproj.github.io/argo-events/eventsources/setup/webhook/?utm_source=chatgpt.com "Webhook - Argo Events - The Event-Based Dependency Manager for Kubernetes"
[5]: https://argoproj.github.io/argo-events/quick_start/?utm_source=chatgpt.com "Getting Started - Argo Events - The Event-Based Dependency Manager for Kubernetes"
