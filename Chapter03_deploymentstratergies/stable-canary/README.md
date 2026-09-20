# Stable-Canary

**Idea:** Release the new version (v2) to a *small slice* of live traffic first.
The **stable** deployment (v1) keeps most of the load; the **canary** deployment
(v2) takes a fraction. If the canary looks healthy, you shift more traffic to it
until it fully replaces stable. If not, you scale it back to zero.

Traffic is split by **replica ratio**: one Service selects both deployments, and
Kubernetes load-balances evenly across every matching pod.
`4 stable + 1 canary` → about **80% v1 / 20% v2**.

- **NodePort:** `30084`
- **Namespace:** `stable-canary`
- **Mechanism:** two deployments sharing the label `app: canary-demo`; the
  Service selects only that label, so it hits both tracks.

---

## 1. Deploy stable + canary

```bash
cd stable-canary
kubectl apply -f application.yaml
kubectl -n stable-canary get pods -w
```
You'll get 4 stable pods (v1) and 1 canary pod (v2).

```bash
kubectl -n stable-canary get deploy
# canary-stable   4/4
# canary-canary   1/1
```

## 2. Open it in the browser

```bash
minikube service canary-demo -n stable-canary --url   # minikube
# OR direct:  http://<node-ip>:30084
# OR fallback: kubectl -n stable-canary port-forward svc/canary-demo 8088:80
```
Refresh **many** times. Roughly 1 in 5 refreshes shows **Version: 2.0.0**; the
rest show **1.0.0**.

## 3. Measure the split (clearer than eyeballing)

```bash
URL="http://<node-ip>:30084"
for i in $(seq 1 50); do curl -s $URL | grep Version; done | sort | uniq -c
# Example output:
#   40 Version: 1.0.0
#   10 Version: 2.0.0     (~20% canary)
```

## 4. Shift more traffic to the canary (progressive rollout)

Increase canary replicas and/or decrease stable, then commit. Editing
`manifests/deployment-canary.yaml` and `manifests/deployment-stable.yaml`:

| Goal split | stable replicas | canary replicas |
|---|---|---|
| ~20% v2 | 4 | 1 |
| 50% v2 | 3 | 3 |
| ~80% v2 | 1 | 4 |
| 100% v2 | 0 | 5 |

```bash
# example: move to 50/50
# edit deployment-stable.yaml  -> replicas: 3
# edit deployment-canary.yaml  -> replicas: 3
git add stable-canary/manifests/
git commit -m "canary: shift to 50/50"
git push
```
Re-run the measurement loop in step 3 and watch the ratio move.

> Quick test alternative (auto-sync may revert these):
> ```bash
> kubectl -n stable-canary scale deploy/canary-canary --replicas=3
> kubectl -n stable-canary scale deploy/canary-stable --replicas=3
> ```

## 5. Promote or roll back

- **Promote:** scale stable to 0 (or set the stable deployment's image to `:2.0`
  and remove the canary), commit, push. Now 100% of traffic is v2.
- **Roll back:** scale canary to 0, commit, push. All traffic returns to v1
  instantly — no redeploy needed.

## 6. Clean up
```bash
kubectl delete -f application.yaml
kubectl delete ns stable-canary --ignore-not-found
```

---

### Note on this "replica-ratio" canary
This is the simplest canary that needs no extra tools — pure Deployments +
Service. The split granularity is limited by replica counts (you can't easily do
5%). For percentage-precise, automated, metric-driven canaries, teams add
**Argo Rollouts** or a service mesh (Istio/Linkerd). This demo deliberately
sticks to vanilla Kubernetes + ArgoCD so it works on any cluster out of the box.
