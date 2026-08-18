# Part 3 — GitOps with Argo CD

Part 2 ended with you typing `helm upgrade` on your laptop.

Ask the class: **who else can type that? what did they type? when? did it work?**
Nobody knows. The cluster's real state lives in someone's terminal history.

GitOps replaces the human running commands with a robot watching git:

```
part 2:   you  --helm upgrade-->  cluster
part 3:   you  --git push-->  repo  <--watches--  Argo CD  --applies-->  cluster
```

Same chart. Same values files. Nobody runs `helm` any more.

---

## 0. What you need

- a running cluster (minikube / kind / Docker Desktop)
- **this repo pushed to GitHub** (public is fine — Argo CD has to be able to `git clone` it)

Argo CD cannot read your laptop's folder. If you haven't pushed yet:

```bash
cd /Users/skatz/helm_for_night_course
git init && git add . && git commit -m "helm + gitops course"
git remote add origin https://github.com/YOU/helm_for_night_course.git
git push -u origin main
```

Then point the Application files at your repo:

```bash
./03-gitops/set-repo.sh https://github.com/YOU/helm_for_night_course.git
git commit -am "point argocd at my repo" && git push
```

---

## 1. Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait -n argocd --for=condition=available --timeout=300s deploy/argocd-server
```

Open the UI (leave this running in its own terminal):

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

→ https://localhost:8080 (accept the self-signed cert warning)

user `admin`, password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d ; echo
```

**The point:** Argo CD is just pods in your cluster. It is not a SaaS, it is not a
CI server. It sits *inside* the cluster and pulls.

---

## 2. Tell Argo CD about the app

```
03-gitops/apps/
  webapp-dev.yaml     dev  -> namespace dev,  auto-sync ON
  webapp-prod.yaml    prod -> namespace prod, manual sync
```

Read `webapp-dev.yaml` out loud with the class — it is only three questions:

| block | question |
|---|---|
| `source` | which repo, which branch, which folder, which values file |
| `destination` | which cluster, which namespace |
| `syncPolicy` | should it fix drift by itself, or wait for a human |

Apply them:

```bash
kubectl apply -f 03-gitops/apps/
```

Watch the UI. Within seconds:

```bash
kubectl get pods -n dev
kubectl get pods -n prod     # empty - prod is still waiting for a human
```

`webapp-dev` goes **Synced / Healthy** on its own.
`webapp-prod` sits at **OutOfSync**. Press **Sync** in the UI, or:

```bash
kubectl patch app webapp-prod -n argocd --type merge \
  -p '{"operation":{"sync":{}}}'
```

**The point:** this is the last `kubectl apply` of the demo. Everything from
here on happens through git.

---

## 3. Demo A — change the app by changing git

Edit `02-helm/webapp/values-dev.yaml`:

```yaml
replicaCount: 3
message: "Hello from DEV - deployed by Argo CD"
```

```bash
git commit -am "dev: 3 replicas, new message" && git push
```

Now do nothing and watch:

```bash
kubectl get pods -n dev -w
```

Argo CD polls git every ~3 minutes. Nobody in a classroom waits 3 minutes, so
hit refresh in the UI (or `kubectl annotate app webapp-dev -n argocd
argocd.argoproj.io/refresh=normal --overwrite`) and the pods appear.

See the new page:

```bash
kubectl port-forward -n dev svc/dev 8081:80
open http://localhost:8081
```

**The point:** the diff in the pull request *is* the deployment.

---

## 4. Demo B — self-heal (the one they'll remember)

Sabotage the cluster by hand, like a tired engineer at 2am:

```bash
kubectl scale deploy/dev -n dev --replicas=10
kubectl get pods -n dev -w
```

They scale up... and then Argo CD scales them straight back to 3.

Try deleting something instead:

```bash
kubectl delete deploy/dev -n dev
kubectl get deploy -n dev      # it's back
```

Now do the same to prod (which has no `selfHeal`):

```bash
kubectl scale deploy/prod -n prod --replicas=10
```

Prod stays at 10 and the Application turns **OutOfSync** — Argo CD *tells* you
someone touched it, but doesn't overrule them until a human clicks Sync.

**The point:** git isn't a suggestion. Manual `kubectl` changes are drift, and
Argo CD either reports it or erases it — your choice, per environment.

---

## 5. Demo C — rollback is `git revert`

```bash
git revert HEAD --no-edit && git push
```

Refresh in the UI → dev goes back to 1 replica and the old message.

No `helm rollback`, no "which revision was good?". The good revision is the
commit before the bad one, and everyone can see it in the repo history.

---

## 6. Demo D — prune: deleting a file deletes the object

Add a throwaway template, `02-helm/webapp/templates/extra-configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-extra
data:
  note: "added in class"
```

```bash
git add . && git commit -m "add extra configmap" && git push
# refresh in the UI
kubectl get cm -n dev        # dev-extra is there
```

Now delete the file and push:

```bash
git rm 02-helm/webapp/templates/extra-configmap.yaml
git commit -m "remove extra configmap" && git push
# refresh
kubectl get cm -n dev        # dev-extra is gone
```

That deletion is `prune: true` doing its job. With `prune: false` the ConfigMap
would linger forever — an orphan nobody remembers creating.

**The point:** git is the whole list, not just a to-do list. Anything not in git
gets removed.

### One honest gap

Argo CD is watching `02-helm/webapp`. Nobody is watching `03-gitops/apps/` — you
applied those two Application files with `kubectl`, by hand. So removing an
environment is still manual:

```bash
kubectl delete -f 03-gitops/apps/webapp-prod.yaml
```

The fix is the **"app of apps"** pattern: one more Application whose `path` is
`03-gitops/apps/`, so the Applications are themselves GitOps'd. Mention it,
don't build it today.

---

## Cleanup

```bash
kubectl delete -f 03-gitops/apps/
kubectl delete namespace dev prod
kubectl delete namespace argocd
```

---

## The four rules of GitOps

1. **Declarative** — the desired state is data (YAML), not commands.
2. **Versioned in git** — git is the single source of truth, with history and review.
3. **Pulled automatically** — an agent inside the cluster applies it; no CI with cluster credentials.
4. **Continuously reconciled** — drift is detected and corrected, not just applied once.

## Helm vs Argo CD, in one line each

- **Helm** answers *what do the manifests look like?*
- **Argo CD** answers *who applies them, from where, and what happens when someone changes them by hand?*

They are not competitors. Argo CD ran your Helm chart — you never even repackaged it.

## Cheat sheet

```bash
kubectl apply  -f 03-gitops/apps/           # register apps
kubectl get app -n argocd                   # SYNC STATUS / HEALTH STATUS
kubectl describe app webapp-dev -n argocd   # why is it OutOfSync?

# with the argocd CLI (brew install argocd), after: argocd login localhost:8080
argocd app list
argocd app get  webapp-dev
argocd app diff webapp-dev      # git vs cluster
argocd app sync webapp-dev
argocd app history webapp-dev
```
