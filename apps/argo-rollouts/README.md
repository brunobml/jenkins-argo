# ARGO ROLLOUTS

```bash
kubectl argo rollouts get rollout canary-demo -n canary-demo
Name:            canary-demo
Namespace:       canary-demo
Status:          ✔ Healthy
Strategy:        Canary
  Step:          4/4
  SetWeight:     100
  ActualWeight:  100
Images:          argoproj/rollouts-demo:blue (stable)
Replicas:
  Desired:       5
  Current:       5
  Updated:       5
  Ready:         5
  Available:     5

NAME                                     KIND         STATUS        AGE   INFO
⟳ canary-demo                            Rollout      ✔ Healthy     164m
├──# revision:6
│  └──⧉ canary-demo-84d475f54d           ReplicaSet   ✔ Healthy     44m   stable
│     ├──□ canary-demo-84d475f54d-gq52n  Pod          ✔ Running     43m   ready:1/1
│     ├──□ canary-demo-84d475f54d-h68fn  Pod          ✔ Running     41m   ready:1/1
│     ├──□ canary-demo-84d475f54d-ktdps  Pod          ✔ Running     41m   ready:1/1
│     ├──□ canary-demo-84d475f54d-c44mx  Pod          ✔ Running     39m   ready:1/1
│     └──□ canary-demo-84d475f54d-qj75r  Pod          ✔ Running     20s   ready:1/1
├──# revision:5
│  └──⧉ canary-demo-65bbbcc8fd           ReplicaSet   • ScaledDown  164m
└──# revision:2
   ├──α canary-demo-84d475f54d-2-1       AnalysisRun  ✔ Successful  43m   ✔ 5
   └──α canary-demo-84d475f54d-2-3       AnalysisRun  ✔ Successful  41m   ✔ 5
➜  jenkins-argo git:(main)
```

## Install Kubernetes plugin

That error means the **Argo Rollouts kubectl plugin is not available in your current shell/PATH**.

Check first:

```bash
kubectl argo rollouts version
which kubectl-argo-rollouts
```

The plugin executable must be named exactly:

```text
kubectl-argo-rollouts
```

and be somewhere in your `$PATH`.

On Linux/WSL, reinstall it with:

```bash
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64

chmod +x kubectl-argo-rollouts-linux-amd64

sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
```

Then verify:

```bash
kubectl argo rollouts version
```

And retry:

```bash
kubectl argo rollouts get rollout canary-demo -n canary-demo
```

You can also run the plugin directly:

```bash
kubectl-argo-rollouts get rollout canary-demo -n canary-demo
```

Since this command worked earlier, you are probably now using a different environment—such as Windows PowerShell instead of WSL—or the plugin was installed in a directory that is no longer in `$PATH`.


On macOS, the easiest method is **Homebrew**:

```bash
brew install argoproj/tap/kubectl-argo-rollouts
```

Verify the installation:

```bash
kubectl argo rollouts version
```

Then run your command:

```bash
kubectl argo rollouts get rollout canary-demo -n canary-demo
```

You can also invoke the plugin directly:

```bash
kubectl-argo-rollouts get rollout canary-demo -n canary-demo
```

### If Homebrew cannot find the command

Update Homebrew and reinstall:

```bash
brew update
brew tap argoproj/tap
brew install kubectl-argo-rollouts
```

Confirm that `kubectl` recognizes the plugin:

```bash
kubectl plugin list
```

You should see a path ending in:

```text
kubectl-argo-rollouts
```

This installs only the local CLI plugin; it does not reinstall or modify the Argo Rollouts controller running in your Kubernetes cluster. ([github.com][1])

[1]: https://github.com/argoproj/argo-rollouts?utm_source=chatgpt.com "GitHub - argoproj/argo-rollouts: Progressive Delivery for Kubernetes · GitHub"

