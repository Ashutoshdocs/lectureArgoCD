# Rolling Update

**Idea:** Replace pods gradually — a few new ones come up and pass their
readiness checks before old ones are removed. The app stays available the whole
time, but **during** the rollout both v1 and v2 serve traffic at once.

- **NodePort:** `30081`
- **Namespace:** `rolling-update`
- **Strategy config:** `strategy.type: RollingUpdate`, `maxSurge: 1`, `maxUnavailable: 0`

---

## 1. Deploy v1

```bash
cd rolling-update
kubectl apply -f application.yaml
```

ArgoCD syncs `manifests/` into the `rolling-update` namespace. Watch it:
```bash
kubectl -n rolling-update get pods -w
```
Wait until all 4 pods are `Running` and `Ready`.

## 2. Open it in the browser

```bash
minikube service rolling-demo -n rolling-update --url   # minikube
# OR direct:  http://<node-ip>:30081
# OR fallback: kubectl -n rolling-update port-forward svc/rolling-demo 8088:80
```
You should see **Version: 1.0.0**. Refresh a few times — the `Hostname` changes
because the Service load-balances across the 4 pods, but the version stays 1.0.0.

## 3. Start a live watch (so you can SEE the rollout)

In a separate terminal:
```bash
URL="http://<node-ip>:30081"   # or your port-forward / minikube URL
while true; do curl -s $URL | grep Version; sleep 0.3; done
```

## 4. Trigger the rolling update (the GitOps way)

Edit `manifests/deployment.yaml` and change the image tag `:1.0` to `:2.0`:
```yaml
image: gcr.io/google-samples/hello-app:2.0
```
Commit and push:
```bash
git add rolling-update/manifests/deployment.yaml
git commit -m "rolling-update: v1 -> v2"
git push
```
ArgoCD detects the change and syncs. (Click **Refresh/Sync** in the ArgoCD UI to
speed it up, or it auto-syncs within a few minutes.)

> Quick alternative without Git (for testing only):
> `kubectl -n rolling-update set image deployment/rolling-demo hello=gcr.io/google-samples/hello-app:2.0`
> Note: with auto-sync + selfHeal, ArgoCD may revert this to match Git.

## 5. What you'll observe

In your watch loop and in the browser (keep refreshing), you'll see a **mix**:
```
Version: 1.0.0
Version: 2.0.0
Version: 1.0.0
Version: 2.0.0   <- old and new served at the same time during the rollout
...
Version: 2.0.0
Version: 2.0.0   <- eventually everything is v2
```
No request ever fails — that's the point of a rolling update.

Watch the pods roll:
```bash
kubectl -n rolling-update get pods -w
kubectl -n rolling-update rollout status deployment/rolling-demo
```

## 6. Reset / clean up
```bash
# revert the tag back to :1.0 in Git and push, or:
kubectl delete -f application.yaml
kubectl delete ns rolling-update --ignore-not-found
```

---

### Knobs to experiment with
- `maxUnavailable: 1` → faster rollout, but capacity dips during it.
- `maxSurge: 2` → more new pods spun up at once.
- Add more `replicas` to make the mixed-version window longer and easier to see.
