# ArgoCD Image Updater — End-to-End Demo (Frontend + ACR + NodePort)

Teach **ArgoCD Image Updater**: when a new container image tag is pushed to a
registry, Image Updater detects it, **writes the new tag back to Git**, and
ArgoCD syncs it to the cluster — no manual `kubectl set image`, no manual commit.

This demo uses:
- a tiny **frontend app** (Node/Express) that **shows its own version on screen**,
- an image stored in **Azure Container Registry (ACR)**,
- **Kustomize** manifests (required for Git write-back),
- a **NodePort** Service to reach the app.

- **Repo:** `https://github.com/Ashutoshdocs/lectureArgoCD.git`
- **Path in repo:** `Chapter04_argoCD_Image_Updater/manifests`

---

## 🔁 The flow you're demonstrating

```
  You: az acr build frontend:1.0.1  ──►  ACR (myacrdemo.azurecr.io/frontend:1.0.1)
                                             │
                          Image Updater polls ACR every ~2 min
                                             │  finds a higher semver tag
                                             ▼
        Image Updater runs `kustomize edit set image` and
        COMMITS the new tag to Git (kustomization.yaml, branch main)
                                             │
                                             ▼
                 ArgoCD sees Git changed  ──►  auto-sync  ──►  new pods
                                             │
                                             ▼
              Browser (NodePort :30080) now shows  v1.0.1
```

Git stays the single source of truth — Image Updater just proposes the tag bump **into Git**.

---

## 📁 Files

```
Chapter04_argoCD_Image_Updater/
├── README.md
├── application.yaml          # ArgoCD Application + Image Updater annotations
├── build-push.sh             # build a version and push to ACR
├── create-secrets.sh         # create ACR pull secret + Git write-back secret
├── app/                      # the frontend application
│   ├── Dockerfile            # bakes APP_VERSION into the image
│   ├── package.json
│   ├── server.js             # shows version + pod name on a web page
│   └── .dockerignore
└── manifests/                # what ArgoCD syncs (Kustomize)
    ├── kustomization.yaml    # images: newTag is what gets rewritten
    ├── namespace.yaml
    ├── deployment.yaml       # image from ACR + imagePullSecret
    └── service.yaml          # NodePort 30080 -> container 3000
```

> **Replace `myacrdemo`** everywhere with your real ACR name. Quick one-liner from
> the repo root:
> ```bash
> grep -rl 'myacrdemo' Chapter04_argoCD_Image_Updater | \
>   xargs sed -i 's/myacrdemo/<your-acr-name>/g'
> ```

---

## ✅ Prerequisites

- Kubernetes cluster + `kubectl` (AKS, kind, minikube, k3s…).
- **Azure CLI** (`az`) logged in, and an **ACR** you can push to.
- ArgoCD installed (below).
- A **GitHub Personal Access Token** (scope: `repo`) for Git write-back.
- Nodes reachable on a NodePort (for kind/minikube see the note in step 8).

---

## 1. Create an ACR (skip if you already have one)

```bash
az group create -n argocd-demo-rg -l eastus
az acr create -n myacrdemo -g argocd-demo-rg --sku Basic
az acr update  -n myacrdemo --admin-enabled true   # simplest auth for a demo
```

## 2. Build & push the FIRST version (1.0.0) to ACR

`az acr build` builds in the cloud — no local Docker required:

```bash
cd Chapter04_argoCD_Image_Updater
bash build-push.sh 1.0.0
# (build-push.sh runs: az acr build --image frontend:1.0.0 --build-arg APP_VERSION=1.0.0 ./app)
```

Confirm the tag exists:

```bash
az acr repository show-tags -n myacrdemo --repository frontend -o table
```

## 3. Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

## 4. Install ArgoCD Image Updater

```bash
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
kubectl -n argocd rollout status deployment/argocd-image-updater
```

## 5. Push this demo to your Git repo

```bash
git clone https://github.com/Ashutoshdocs/lectureArgoCD.git
cd lectureArgoCD
# copy the Chapter04_argoCD_Image_Updater folder in here, then:
git add Chapter04_argoCD_Image_Updater
git commit -m "Chapter04: ArgoCD Image Updater demo"
git push origin main
```

## 6. Create credentials (ACR pull + Git write-back)

Edit the variables at the top of `create-secrets.sh` (ACR name, GitHub user, PAT),
then run it:

```bash
bash create-secrets.sh
```

This creates:
- `frontend-demo/acr-secret` — a docker-registry secret so the Deployment can
  **pull** from ACR **and** Image Updater can **read tags** from ACR
  (referenced by the `pull-secret: pullsecret:frontend-demo/acr-secret` annotation).
- `argocd/git-creds` — username/token so Image Updater can **commit** back to Git
  (referenced by `write-back-method: git:secret:argocd/git-creds`).

## 7. Create the Application

```bash
kubectl apply -f Chapter04_argoCD_Image_Updater/application.yaml
```

Watch it sync and go Healthy:

```bash
kubectl -n argocd get applications
kubectl get all -n frontend-demo
```

## 8. Open the app (NodePort)

```bash
# Any node's IP works; NodePort is 30080.
kubectl get nodes -o wide          # grab an INTERNAL/EXTERNAL IP
curl http://<NODE_IP>:30080
```

You should see the page showing **v1.0.0**.

> **kind:** map the port when creating the cluster
> (`extraPortMappings` hostPort 30080 → containerPort 30080), or just
> `kubectl port-forward -n frontend-demo svc/frontend 8080:80` and open
> http://localhost:8080.
> **minikube:** `minikube service frontend -n frontend-demo --url`.

---

## 9. ⭐ Trigger an automatic update

Push a higher semver tag and let Image Updater do the rest:

```bash
bash build-push.sh 1.0.1
```

Within ~2 minutes Image Updater will:

1. Detect `1.0.1 > 1.0.0` in ACR.
2. Commit the new tag to `kustomization.yaml` on `main`
   (you'll see a commit authored by the Image Updater in your GitHub history).
3. ArgoCD auto-syncs; new pods roll out.

Watch it happen:

```bash
# Image Updater logs (the detection + git commit)
kubectl -n argocd logs deploy/argocd-image-updater -f

# The tag in Git after write-back
git pull && grep newTag Chapter04_argoCD_Image_Updater/manifests/kustomization.yaml

# The app now shows v1.0.1
curl http://<NODE_IP>:30080
```

Repeat with `1.0.2`, `1.1.0`, etc. to reinforce the loop.

> **Want Pull Requests instead of direct commits?** Image Updater's git
> write-back commits to a branch. To review changes as PRs, point
> `git-branch` at a dedicated branch (e.g. `image-updates`) and open PRs from
> it to `main`, or use a `write-back-target` branch and your Git provider's
> PR automation. (Direct commit to `main` is shown above for simplicity.)

---

## How the annotations map to behaviour

| Annotation | Purpose |
|-----------|---------|
| `image-list: frontend=myacrdemo.azurecr.io/frontend` | Which image to watch; `frontend` is an alias |
| `frontend.update-strategy: semver` | Pick the highest valid SemVer tag |
| `frontend.allow-tags: regexp:^\d+\.\d+\.\d+$` | Ignore `latest`/`dev`; only `x.y.z` |
| `frontend.kustomize.image-name` | Ties the alias to the kustomize image so write-back edits the right entry |
| `frontend.pull-secret: pullsecret:frontend-demo/acr-secret` | Creds to read tags from private ACR |
| `write-back-method: git:secret:argocd/git-creds` | Commit the change back to Git |
| `git-branch: main` / `write-back-target: kustomization` | Where and what to write |

**Why Kustomize?** Image Updater's Git write-back only edits Kustomize `images:`
or Helm `values` — it cannot rewrite arbitrary plain manifests. The
`kustomization.yaml` `newTag` field is the single line it changes.

---

## 🧰 Troubleshooting

- **No update after pushing a tag** — check `kubectl -n argocd logs deploy/argocd-image-updater`.
  Common causes: tag doesn't match `allow-tags` regex; `pull-secret` can't read ACR; strategy is `semver` but the new tag isn't higher.
- **`ImagePullBackOff`** — the `acr-secret` is missing/wrong in `frontend-demo`, or the Deployment's `imagePullSecrets` name doesn't match.
- **Write-back fails / no commit** — `argocd/git-creds` token lacks `repo` scope, or `git-branch` is protected. Check the Image Updater logs for `git push` errors.
- **App not reachable** — confirm `kubectl get svc -n frontend-demo` shows `NodePort 30080`; for kind/minikube use the port-forward/URL notes in step 8.
- **Force a check now** — `kubectl -n argocd rollout restart deploy/argocd-image-updater`.

## 🧹 Cleanup

```bash
kubectl delete -f Chapter04_argoCD_Image_Updater/application.yaml
kubectl delete namespace frontend-demo
# optional: remove the whole resource group (deletes the ACR too)
az group delete -n argocd-demo-rg --yes --no-wait
```

---

### One-line recap for students
> Push image → Image Updater notices → it **commits the tag to Git** → ArgoCD
> syncs Git → cluster runs the new version. Git is always the source of truth.
