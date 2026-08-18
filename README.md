# Helm 101 — the same app, twice (and then without you)

The same tiny app (nginx serving one HTML page) deployed to **dev** and **prod**:

```
01-plain-k8s/    plain YAML — one folder per environment
02-helm/webapp/  one Helm chart — one values file per environment
03-gitops/       the same chart, applied by Argo CD instead of by you
```

Both produce identical Kubernetes objects: a Deployment, a Service, a ConfigMap.

| | dev | prod |
|---|---|---|
| replicas | 1 | 3 |
| service | ClusterIP | NodePort 30080 |
| resources | small | bigger |
| message | "Hello from DEV" | "Hello from PROD" |

---

## Part 1 — plain YAML

```bash
kubectl apply -f 01-plain-k8s/dev
kubectl get all -l app=webapp-dev

kubectl apply -f 01-plain-k8s/prod
kubectl get all -l app=webapp-prod
```

Then show the class:

```bash
diff -u 01-plain-k8s/dev/deployment.yaml 01-plain-k8s/prod/deployment.yaml
```

**The point:** ~90% of the two folders is identical. The 4 things that actually
differ are buried in ~100 lines of copy-paste.

Ask the class: *"we upgrade nginx to 1.29 — how many files do you touch?"*
Four: both Deployments, and both ConfigMaps (the version is printed on the page).
Miss one and dev and prod silently drift apart. Now imagine 12 microservices
× 3 environments.

Cleanup:

```bash
kubectl delete -f 01-plain-k8s/dev -f 01-plain-k8s/prod
```

---

## Part 2 — the same thing as a Helm chart

```
02-helm/webapp/
  Chart.yaml          name + version of the chart
  values.yaml         default values
  values-dev.yaml     dev overrides
  values-prod.yaml    prod overrides
  templates/          the YAML from part 1, with the values punched out
    deployment.yaml
    service.yaml
    configmap.yaml
    NOTES.txt         printed after install
```

Mental model: **template + values = manifest**. Nothing more.
Helm renders the templates, sends the result to the API server, and remembers
what it sent (that record is called a *release*).

### Look before you leap — render without installing

```bash
cd 02-helm
helm template dev  ./webapp -f webapp/values-dev.yaml
helm template prod ./webapp -f webapp/values-prod.yaml
```

Same output as the plain YAML from part 1 — that is the whole trick.

```bash
helm lint ./webapp
```

### Install

```bash
helm install dev  ./webapp -f webapp/values-dev.yaml
helm install prod ./webapp -f webapp/values-prod.yaml

helm list
kubectl get all
```

Note the object names: `dev`, `dev-html`, `prod`, `prod-html`. They come from
`{{ .Release.Name }}` — the same chart installed twice, no name collisions.

### Change something

```bash
helm upgrade dev ./webapp -f webapp/values-dev.yaml --set replicaCount=3
kubectl get pods -l app=dev

helm upgrade dev ./webapp -f webapp/values-dev.yaml --set image.tag=1.29-alpine
```

One value, one place — the Deployment *and* the HTML page both follow.

```bash
helm history dev
helm rollback dev 1
helm history dev
```

**The point:** `kubectl apply` has no undo. Helm keeps every revision.

### Uninstall

```bash
helm uninstall dev
helm uninstall prod
```

One command removes everything the chart created — no hunting for leftovers.

Do run this before part 3 — Argo CD will install the same chart again, and
prod's NodePort can only be claimed once.

---

## Part 3 — GitOps: nobody types `helm` any more

→ **[03-gitops/README.md](03-gitops/README.md)**

Same chart, same values files, nothing repackaged. The difference is who runs
it: Argo CD watches the git repo and keeps the cluster matching it — including
undoing changes someone makes by hand.

```
02-helm/webapp/       the chart (unchanged)
03-gitops/apps/       two Argo CD Applications: dev (auto-sync) and prod (manual)
03-gitops/set-repo.sh point them at your fork
```

Requires the repo to be pushed to GitHub — Argo CD clones it, it can't read
your laptop.

---

## The template syntax you need today

| syntax | meaning |
|---|---|
| `{{ .Values.replicaCount }}` | a value from values.yaml / `-f` / `--set` |
| `{{ .Release.Name }}` | the name you gave `helm install` |
| `{{ .Release.Namespace }}` | where it's being installed |
| `{{ .Chart.Name }}` `{{ .Chart.AppVersion }}` | from Chart.yaml |
| `{{- if eq .Values.service.type "NodePort" }} … {{- end }}` | include a block conditionally |

The `-` in `{{-` trims the whitespace before the tag — it keeps the rendered
YAML indented correctly. That's why you see it on `if`/`end` lines.

Precedence, lowest to highest: `values.yaml` → `-f myvalues.yaml` → `--set`.

## Cheat sheet

```bash
helm create NAME              # scaffold a new chart (much bigger than ours)
helm lint ./chart             # sanity-check it
helm template NAME ./chart    # render locally, install nothing
helm install NAME ./chart -f values-x.yaml
helm upgrade NAME ./chart -f values-x.yaml
helm list
helm history NAME
helm rollback NAME REVISION
helm uninstall NAME

helm repo add bitnami https://charts.bitnami.com/bitnami
helm install my-db bitnami/postgresql     # someone else's chart, same commands
```

## Why Helm, in one slide

1. **No copy-paste per environment** — one chart, many values files.
2. **Releases** — Helm tracks what it installed; `upgrade`, `rollback`, `uninstall`
   as single commands.
3. **Packaging & sharing** — a chart is versioned and installable from a repo,
   which is how you get Postgres/Prometheus/ingress-nginx in one line.
