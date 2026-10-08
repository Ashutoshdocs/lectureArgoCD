<div align="center">

# ☸️ Chapter 04 — ArgoCD + Kustomize

### One base in Git. ArgoCD builds the overlays. Four live web pages prove it.

![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo&logoColor=white)
![Kustomize](https://img.shields.io/badge/Kustomize-v5-326CE5?logo=kubernetes&logoColor=white)
![nginx](https://img.shields.io/badge/nginx-alpine-009639?logo=nginx&logoColor=white)
![Services](https://img.shields.io/badge/Services-NodePort-orange)

</div>

---

## 🎯 Objective

Deploy the **same** application into **base**, **dev**, **prod** and **staging** with ArgoCD,
without editing the original YAML. ArgoCD detects `kustomization.yaml` in the Git path and runs
`kustomize build` itself — no `kubectl apply -k` needed.

Each environment gets its **own NodePort** and serves the **same HTML page**. The page reads live
values from its pod and badges every row **from base** 🟩 or **overlay** 🟧.

| ArgoCD App | Git path | Namespace | NodePort | Replicas | Image | Sync | Colour |
|---|---|---|---|---|---|---|---|
| `kustomize-base` | `base` | `base` | **30080** | 1 | nginx 1.25 | auto | ⚪ slate |
| `kustomize-dev` | `overlays/dev` | `dev` | **30081** | 1 | nginx 1.25 | auto | 🔵 blue |
| `kustomize-prod` | `overlays/prod` | `prod` | **30082** | 3 | nginx 1.27 | **manual** | 🟢 green |
| `kustomize-staging` | `base` + Application `kustomize:` | `staging` | **30083** | 2 | nginx 1.26 | auto | 🟣 purple |

> 💡 **The proof:** `index.html` exists **only** in `base/html/`. Four pages, four looks, one file.

---

## 🧭 Flow

```text
 ┌──────────────────────────────── Git: lectureArgoCD (main) ────────────────────────────────┐
 │  Chapter02_Ways_to_deploy/Chapter04_kustomize/                                            │
 │     base/ ◄──────────── overlays/dev ◄──┐                                                 │
 │       ▲  ◄──────────── overlays/prod    │                                                 │
 │       └────────────── (staging: no folder, overrides live in the Application spec)        │
 └──────────────────────────────────────────┬────────────────────────────────────────────────┘
                                            │  ArgoCD polls Git (~3 min) or you click Refresh
                                            ▼
                         ┌───────────────────────────────────────┐
                         │ ArgoCD repo-server: kustomize build   │
                         └──────┬─────────┬─────────┬─────────┬──┘
                                ▼         ▼         ▼         ▼
                              base       dev       prod     staging
                             :30080    :30081    :30082    :30083
```

---

## 📁 Structure

```text
Chapter02_Ways_to_deploy/Chapter04_kustomize/
├── README.md
├── argocd-apps/
│   ├── root-app.yaml            # App of Apps -> creates all apps below
│   ├── app-base.yaml            # base/            -> ns base,    30080
│   ├── app-dev.yaml             # overlays/dev     -> ns dev,     30081
│   ├── app-prod.yaml            # overlays/prod    -> ns prod,    30082 (manual sync)
│   └── app-staging-inline.yaml  # base + spec.source.kustomize -> ns staging, 30083
├── base/
│   ├── kustomization.yaml       # resources, labels, annotations, generators
│   ├── deployment.yaml          # nginx + Downward API env vars
│   ├── service.yaml             # NodePort 30080
│   ├── html/index.html          # the ONE page
│   └── nginx/default.conf.template   # serves / , /info , /healthz
└── overlays/
    ├── dev/kustomization.yaml
    └── prod/
        ├── kustomization.yaml
        └── resources-patch.yaml
```

---

## ✅ Prerequisites

```bash
kubectl get pods -n argocd                 # ArgoCD running (Chapter01)
argocd version                             # CLI (optional)
argocd login <ARGOCD_SERVER> --username admin --insecure
```

- This folder pushed to `main` of `https://github.com/Ashutoshdocs/lectureArgoCD`.
- Node ports **30080–30083** free. Check: `kubectl get svc -A | grep 3008`.

> Using a fork or another branch? Change `repoURL` / `targetRevision` in every file under `argocd-apps/`.

---

## 🔍 Step 1 — Preview locally (optional)

ArgoCD runs the same build. Preview it first:

```bash
cd Chapter02_Ways_to_deploy/Chapter04_kustomize
kubectl kustomize base
kubectl kustomize overlays/dev
kubectl kustomize overlays/prod
diff <(kubectl kustomize overlays/dev) <(kubectl kustomize overlays/prod)
```

---

## 🚀 Step 2 — Deploy with ArgoCD (pick one way)

### Way A — YAML (declarative)

```bash
kubectl apply -f argocd-apps/app-base.yaml
kubectl apply -f argocd-apps/app-dev.yaml
kubectl apply -f argocd-apps/app-prod.yaml
kubectl apply -f argocd-apps/app-staging-inline.yaml
```

### Way B — App of Apps (one command)

```bash
kubectl apply -f argocd-apps/root-app.yaml
```

### Way C — ArgoCD CLI

```bash
REPO=https://github.com/Ashutoshdocs/lectureArgoCD.git
P=Chapter02_Ways_to_deploy/Chapter04_kustomize

argocd app create kustomize-base --repo $REPO --revision main --path $P/base \
  --dest-server https://kubernetes.default.svc --dest-namespace base \
  --sync-policy automated --auto-prune --self-heal --sync-option CreateNamespace=true

argocd app create kustomize-dev --repo $REPO --revision main --path $P/overlays/dev \
  --dest-server https://kubernetes.default.svc --dest-namespace dev \
  --sync-policy automated --auto-prune --self-heal --sync-option CreateNamespace=true

argocd app create kustomize-prod --repo $REPO --revision main --path $P/overlays/prod \
  --dest-server https://kubernetes.default.svc --dest-namespace prod \
  --sync-option CreateNamespace=true

# Staging: overrides given to ArgoCD, no overlay folder
argocd app create kustomize-staging --repo $REPO --revision main --path $P/base \
  --dest-server https://kubernetes.default.svc --dest-namespace staging \
  --nameprefix staging- --kustomize-image nginx:1.26-alpine \
  --kustomize-replica student-app=2 --kustomize-namespace staging \
  --sync-policy automated --sync-option CreateNamespace=true
# (CLI can't add patches; use app-staging-inline.yaml for the NodePort 30083 + colour patch)
```

### Way D — ArgoCD UI

1. **+ NEW APP** → Name `kustomize-dev`, Project `default`, Sync **Automatic**, tick *Prune*, *Self Heal*, *Auto-Create Namespace*.
2. **Source** → Repo `https://github.com/Ashutoshdocs/lectureArgoCD.git`, Revision `main`,
   Path `Chapter02_Ways_to_deploy/Chapter04_kustomize/overlays/dev`.
3. **Destination** → `https://kubernetes.default.svc`, Namespace `dev`.
4. The form shows a **Kustomize** section automatically — ArgoCD detected `kustomization.yaml`.
5. **CREATE**. Repeat for `base` (ns `base`) and `overlays/prod` (ns `prod`, Sync *Manual*).

### Sync prod (manual on purpose)

```bash
argocd app diff kustomize-prod      # review first
argocd app sync kustomize-prod
```

---

## ✅ Step 3 — Verify

```bash
argocd app list | grep kustomize
kubectl get all -n base
kubectl get all -n dev
kubectl get all -n prod
kubectl get all -n staging
kubectl get svc -A | grep student-service
```

Expected names:

| | base | dev | prod | staging |
|---|---|---|---|---|
| Deployment | `student-app` | `dev-student-app` | `prod-student-app` | `staging-student-app` |
| Service | `student-service` | `dev-student-service` | `prod-student-service` | `staging-student-service` |
| ConfigMap | `student-config-<hash>` | `dev-student-config-<hash>` | `prod-student-config-<hash>` | `staging-student-config-<hash>` |

---

## 🌐 Step 4 — Open the pages

```bash
kubectl get nodes -o wide          # node IP
minikube ip                        # if minikube
```

| URL | You should see |
|---|---|
| `http://<node-ip>:30080` | ⚪ **Running as base** — 0 of 12 changed |
| `http://<node-ip>:30081` | 🔵 **development** — namespace, name, label, colour, port changed |
| `http://<node-ip>:30082` | 🟢 **production** — plus image 1.27, bigger limits, 3 replicas (click *Send 20 requests*) |
| `http://<node-ip>:30083` | 🟣 **staging** — changed by ArgoCD alone, no overlay folder |

Terminal check:

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
for p in 30080 30081 30082 30083; do echo "== $p"; curl -s http://$NODE:$p/info; echo; done
```

<details>
<summary><b>kind users: port mappings</b></summary>

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - { containerPort: 30080, hostPort: 30080 }
      - { containerPort: 30081, hostPort: 30081 }
      - { containerPort: 30082, hostPort: 30082 }
      - { containerPort: 30083, hostPort: 30083 }
```
</details>

---

## 🔁 Step 5 — GitOps in action

### 5.1 Change dev through Git

Edit `overlays/dev/kustomization.yaml`:

```yaml
      - "APP_COLOR=#f97316"
      - "APP_MESSAGE=Changed in Git. ArgoCD synced it. No kubectl used."
```

```bash
git add . && git commit -m "dev: orange theme" && git push
argocd app get kustomize-dev --refresh     # or wait ~3 min / click REFRESH in UI
```

Reload `:30081` → orange page. The ConfigMap got a **new hash**, so the Deployment rolled
automatically; `prune: true` deleted the old ConfigMap.

### 5.2 Self-heal

```bash
kubectl scale deployment dev-student-app -n dev --replicas=5
kubectl get deploy -n dev -w                # ArgoCD puts it back to 1
```

### 5.3 Prod waits for you

Change `count: 3` → `count: 4` in `overlays/prod/kustomization.yaml`, push.
ArgoCD shows `kustomize-prod` as **OutOfSync** but does nothing until you sync:

```bash
argocd app diff kustomize-prod
argocd app sync kustomize-prod
```

Click *Send 20 requests* on `:30082` → 4 pods answer.

---

## 🧱 Key files

### `base/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
labels:
  - pairs:
      environment: base
    includeSelectors: false
    includeTemplates: true
commonAnnotations:
  kustomize.demo/layer: base
configMapGenerator:
  - name: student-config
    literals:
      - APP_COURSE=DevOps
      - APP_TRAINER=Ashutosh
      - "APP_MESSAGE=Rendered straight from the base. No overlay applied."
      - "APP_COLOR=#64748b"
  - name: student-html
    files: [html/index.html]
  - name: student-nginx-conf
    files: [nginx/default.conf.template]
secretGenerator:
  - name: student-secret
    literals:
      - username=admin
      - password=Pass@123
```

### `overlays/dev/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: dev
namePrefix: dev-
labels:
  - pairs: { environment: development, owner: devops }
    includeSelectors: false
    includeTemplates: true
commonAnnotations:
  kustomize.demo/layer: dev-overlay
  createdBy: Ashutosh
replicas:
  - name: student-app
    count: 1
configMapGenerator:
  - name: student-config
    behavior: merge
    literals:
      - "APP_COLOR=#3b82f6"
      - "APP_MESSAGE=DEV overlay: namespace dev, prefix dev-, 1 replica, NodePort 30081."
patches:
  - target: { kind: Service, name: student-service }
    patch: |-
      - op: replace
        path: /spec/ports/0/nodePort
        value: 30081
```

### `overlays/prod/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: prod
namePrefix: prod-
labels:
  - pairs: { environment: production, owner: devops }
    includeSelectors: false
    includeTemplates: true
commonAnnotations:
  kustomize.demo/layer: prod-overlay
  createdBy: Ashutosh
replicas:
  - name: student-app
    count: 3
images:
  - name: nginx
    newTag: 1.27-alpine
configMapGenerator:
  - name: student-config
    behavior: merge
    literals:
      - "APP_COLOR=#22c55e"
      - "APP_MESSAGE=PROD overlay: namespace prod, prefix prod-, 3 replicas, nginx 1.27, bigger limits, NodePort 30082."
patches:
  - path: resources-patch.yaml
  - target: { kind: Service, name: student-service }
    patch: |-
      - op: replace
        path: /spec/ports/0/nodePort
        value: 30082
```

### `argocd-apps/app-dev.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kustomize-dev
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/Ashutoshdocs/lectureArgoCD.git
    targetRevision: main
    path: Chapter02_Ways_to_deploy/Chapter04_kustomize/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
```

### `argocd-apps/app-staging-inline.yaml` (ArgoCD does the customising)

```yaml
spec:
  source:
    path: Chapter02_Ways_to_deploy/Chapter04_kustomize/base
    kustomize:
      namePrefix: staging-
      namespace: staging
      commonLabels: { environment: staging }
      commonAnnotations: { kustomize.demo/layer: staging-argocd-inline }
      images: [nginx:1.26-alpine]
      replicas:
        - { name: student-app, count: 2 }
      patches:
        - target: { kind: Service, name: student-service }
          patch: |-
            - op: replace
              path: /spec/ports/0/nodePort
              value: 30083
        # + ConfigMap patch for purple colour and message
```

---

## ⚖️ Overlay folder vs ArgoCD inline `kustomize:`

| | Overlay folder (dev/prod) | Application `spec.source.kustomize` (staging) |
|---|---|---|
| Where changes live | Git, next to the base | The ArgoCD Application manifest |
| Works without ArgoCD | ✅ `kubectl apply -k` | ❌ ArgoCD only |
| Good for | Real environments | Quick tweaks, image bumps (Image Updater uses this) |
| Recommended | ✅ Yes | Use sparingly |

---

## 🧹 Cleanup

```bash
# finalizer deletes each app's Kubernetes resources too
argocd app delete kustomize-root -y        # if you used App of Apps
argocd app delete kustomize-base kustomize-dev kustomize-prod kustomize-staging -y
kubectl delete namespace base dev prod staging
```

---

## 🛠️ Troubleshooting

| Symptom | Fix |
|---|---|
| `app path does not exist` | Folder not pushed to `main`, or path typo. Check `targetRevision` and `path`. |
| `provided port is already allocated` | Another Service owns that NodePort: `kubectl get svc -A \| grep 3008`. Change the port in the overlay patch. |
| `cannot unmarshal object into ... literals` | Quote literals containing `: ` → `- "KEY=a: b"` |
| App stays **OutOfSync** after edit | Click **REFRESH** (ArgoCD caches Git ~3 min) or `argocd app get <app> --refresh` |
| Old `student-config-xxxx` ConfigMaps pile up | Enable `prune: true` |
| Page says *Couldn't reach /info* | Pod not ready: `kubectl get pods -n <ns>`, `kubectl logs -n <ns> deploy/<name>` |
| Only 1 pod answers on prod | Wait until all replicas are Ready, then *Send 20 requests* |

---

## 🎤 Interview questions

<details><summary><b>1. How does ArgoCD know a path is Kustomize?</b></summary>It finds <code>kustomization.yaml</code> (or <code>.yml</code> / <code>Kustomization</code>) in the path and runs <code>kustomize build</code> in the repo-server.</details>
<details><summary><b>2. Base vs overlay?</b></summary>Base = shared manifests. Overlay = references the base and adds environment changes.</details>
<details><summary><b>3. Overlay folder vs <code>spec.source.kustomize</code>?</b></summary>Overlay lives in Git and works with plain kubectl. Inline overrides live in the Application and only work through ArgoCD.</details>
<details><summary><b>4. Why do ConfigMap names have a hash?</b></summary>Content hash: a config change creates a new name, which changes the Deployment spec and triggers a rolling update.</details>
<details><summary><b>5. Why <code>prune: true</code> with generators?</b></summary>Every config change creates a new hashed ConfigMap; prune deletes the old one.</details>
<details><summary><b>6. What does <code>selfHeal</code> do?</b></summary>Reverts manual cluster changes back to what Git says.</details>
<details><summary><b>7. Why is prod manual sync?</b></summary>To review the diff and approve production changes deliberately.</details>
<details><summary><b>8. What is <code>CreateNamespace=true</code>?</b></summary>ArgoCD creates the destination namespace if it doesn't exist.</details>
<details><summary><b>9. What is App of Apps?</b></summary>One parent Application whose source folder holds other Application manifests.</details>
<details><summary><b>10. What does the resources finalizer do?</b></summary>Deleting the Application also deletes the resources it deployed (cascade delete).</details>
<details><summary><b>11. Helm vs Kustomize in ArgoCD?</b></summary>Both are native. Helm = templates + values; Kustomize = patches over plain YAML. ArgoCD can also run Helm through Kustomize (<code>helmCharts</code>) with a flag.</details>
<details><summary><b>12. <code>commonLabels</code> vs <code>labels</code>?</b></summary><code>commonLabels</code> also edits selectors (immutable after creation). <code>labels</code> with <code>includeSelectors: false</code> avoids that.</details>

---

<div align="center">

**Same `index.html`. Same `deployment.yaml`. Four environments. Zero `kubectl apply`.**
That's GitOps with Kustomize. 🎉

</div>
