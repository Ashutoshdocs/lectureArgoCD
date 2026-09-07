# Recreate (Downtime)

**Idea:** Kill *all* the old pods first, then start the new ones. Between those
two phases there are **zero** running pods, so the app is briefly unreachable.
This demo exists to *prove* the downtime that naive deploys cause — contrast it
with the rolling-update demo, which has none.

- **NodePort:** `30082`
- **Namespace:** `recreate-downtime`
- **Strategy config:** `strategy.type: Recreate`

---

## 1. Deploy v1

```bash
cd recreate-downtime
kubectl apply -f application.yaml
kubectl -n recreate-downtime get pods -w   # wait for 4x Running/Ready
```

## 2. Open it in the browser

```bash
minikube service downtime-demo -n recreate-downtime --url   # minikube
# OR direct:  http://<node-ip>:30082
# OR fallback: kubectl -n recreate-downtime port-forward svc/downtime-demo 8088:80
```
You'll see **Version: 1.0.0**.

## 3. Start a live watch that will EXPOSE the downtime

In a separate terminal, run a probe that prints a timestamp and whether the
request succeeded:
```bash
URL="http://<node-ip>:30082"   # or minikube URL
while true; do
  printf '%s ' "$(date +%T)"
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 1 $URL || echo "DOWN"
  sleep 0.3
done
```

## 4. Trigger the recreate update

Edit `manifests/deployment.yaml`, change `:1.0` to `:2.0`, then:
```bash
git add recreate-downtime/manifests/deployment.yaml
git commit -m "recreate: v1 -> v2 (expect downtime)"
git push
```
(Or, to test immediately:
`kubectl -n recreate-downtime set image deployment/downtime-demo hello=gcr.io/google-samples/hello-app:2.0`)

## 5. What you'll observe

Your probe loop will show a clear **gap of failures** while all v1 pods are
gone and v2 pods are still starting:
```
14:03:01 200
14:03:02 200
14:03:02 000        <- DOWN: no pods running
14:03:03 DOWN
14:03:04 DOWN       <- app is unreachable here (the downtime window)
14:03:05 200        <- v2 is up
14:03:05 200
```
And in the browser: refresh during the gap and you'll get a **connection
error / cannot reach page**; refresh after and you'll see **Version: 2.0.0**.

Watch the pods to see them all disappear before new ones appear:
```bash
kubectl -n recreate-downtime get pods -w
```

## 6. Clean up
```bash
kubectl delete -f application.yaml
kubectl delete ns recreate-downtime --ignore-not-found
```

---

### Takeaway
`Recreate` is simple and guarantees only one version runs at a time (useful when
two versions can't coexist, e.g. incompatible DB schema). The cost is visible,
measurable downtime — which the other three strategies avoid.
