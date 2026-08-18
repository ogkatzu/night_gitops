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

apply the apps:
```bash
kubectl apply -f webapp-dev.yaml
kubectl apply -f webapp-prod.yaml

```


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
