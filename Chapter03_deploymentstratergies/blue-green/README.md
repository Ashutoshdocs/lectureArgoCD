# Blue-Green

**Idea:** Run two complete environments side by side — **blue** (current, v1) and
**green** (new, v2). Green is fully deployed and warmed up while blue still serves
100% of traffic. When you're ready, you flip a single Service selector and all
traffic moves to green **instantly**. Users never see a mix of versions, and
rollback is just flipping back to blue.

- **NodePort:** `30083`
- **Namespace:** `blue-green`
- **Mechanism:** one Service whose `selector.color` chooses blue or green.

---

## 1. Deploy both environments (traffic starts on blue)

```bash
cd blue-green
kubectl apply -f application.yaml
kubectl -n blue-green get pods -w
```
You'll get 3 blue pods (v1) and 3 green pods (v2), all Running. The Service
starts pointing at **blue**.

Confirm the split:
```bash
kubectl -n blue-green get deploy
kubectl -n blue-green get svc bluegreen-demo -o jsonpath='{.spec.selector}'; echo
# -> {"app":"bluegreen-demo","color":"blue"}
```

## 2. Open it in the browser

```bash
minikube service bluegreen-demo -n blue-green --url   # minikube
# OR direct:  http://<node-ip>:30083
# OR fallback: kubectl -n blue-green port-forward svc/bluegreen-demo 8088:80
```
You'll see **Version: 1.0.0** every time you refresh — green exists but receives
no traffic yet.

## 3. (Optional) live watch

```bash
URL="http://<node-ip>:30083"
while true; do curl -s $URL | grep Version; sleep 0.3; done
```
Currently all `1.0.0`.

## 4. Cut over to green (the GitOps way)

Edit `manifests/service.yaml` and change the selector color:
```yaml
selector:
  app: bluegreen-demo
  color: green        # was: blue
```
Commit and push:
```bash
git add blue-green/manifests/service.yaml
git commit -m "blue-green: cut over to green (v2)"
git push
```
ArgoCD syncs the Service. (Sync in the UI to make it instant.)

> Quick test alternative:
> `kubectl -n blue-green patch svc bluegreen-demo -p '{"spec":{"selector":{"app":"bluegreen-demo","color":"green"}}}'`

## 5. What you'll observe

The switch is **atomic**. Your watch loop jumps cleanly with no in-between mix:
```
Version: 1.0.0
Version: 1.0.0
Version: 2.0.0      <- the moment the selector flips
Version: 2.0.0
```
Refresh the browser: it now shows **Version: 2.0.0** on every request.

## 6. Instant rollback

Flip the selector back to `color: blue` (edit + commit + push, or re-patch).
Traffic returns to v1 immediately — no rebuild, because blue was never torn down.

## 7. Promote / clean up

Once green is trusted you would normally update blue to v2 for the next cycle.
To tear the demo down:
```bash
kubectl delete -f application.yaml
kubectl delete ns blue-green --ignore-not-found
```

---

### Takeaway
Blue-green gives zero downtime **and** zero version mixing, plus one-flip
rollback. The trade-off is cost: you run double the pods during the transition.
