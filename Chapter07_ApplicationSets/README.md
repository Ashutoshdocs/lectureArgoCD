# Chapter 7: ArgoCD ApplicationSets (Generators)

An **ApplicationSet** is a factory for Applications. You write **one template**
plus a **generator**, and the ApplicationSet controller stamps out many ArgoCD
Applications automatically — one per env, per folder, per cluster, etc.

This chapter covers **three generators** (plus a bonus):

| # | Generator | Idea | File |
|---|-----------|------|------|
| 1 | **List** (baseline) | You list the elements by hand | `generators/01-list-generator.yaml` |
| 2 | **Git — directory** ⭐ | Scan the repo, one app per folder | `generators/02-git-directory-generator.yaml` |
| 3 | **Cluster** ⭐ | One app per registered cluster | `generators/03-cluster-generator.yaml` |
| 4 | **Matrix** (bonus) | Clusters × Git folders (a grid) | `generators/04-matrix-generator.yaml` |

- **Repo:** `https://github.com/Ashutoshdocs/lectureArgoCD.git`
- **Base path:** `Chapter07_ApplicationSets`

---

## 📁 Files

```
Chapter07_ApplicationSets/
├── README.md
├── apps/                       # colourful per-env apps the generators template over
│   ├── dev/   { configmap, deployment, service }   # 🟢 green page
│   ├── qa/    { configmap, deployment, service }   # 🟠 amber page
│   └── prod/  { configmap, deployment, service }   # 🔴 red page
├── cluster-app/                # 🟣 one app used by the Cluster generator
│   { configmap, deployment, service }
└── generators/
    ├── 01-list-generator.yaml
    ├── 02-git-directory-generator.yaml
    ├── 03-cluster-generator.yaml
    └── 04-matrix-generator.yaml
```

Each app is stock `nginx:1.27-alpine` serving a page from a ConfigMap (no build).
Manifests have **no hardcoded namespace** — the generator's `destination.namespace`
places them.

---

## ✅ Prerequisites

- ArgoCD installed, `argocd` CLI logged in.
- The **ApplicationSet controller** running (bundled with ArgoCD since v2.3+):
  ```bash
  kubectl -n argocd get deploy argocd-applicationset-controller
  # If missing (very old ArgoCD):
  # kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/applicationset/master/manifests/install.yaml
  ```
- These templates use `goTemplate: true` (ArgoCD v2.5+). On older versions switch
  `{{.env}}` → `{{env}}` and remove `goTemplate`/`goTemplateOptions`.
- For the **Cluster** and **Matrix** generators: at least one extra cluster
  registered (`argocd cluster add <context>`) — see Chapter 5. With only the local
  cluster they still work (just the single `in-cluster`).
- This chapter pushed to your repo.

> ℹ️ **Apply ONE generator at a time.** Generators 1, 2 and 4 all deploy into the
> same `dev/qa/prod` namespaces, so running two at once causes ownership
> conflicts. Delete the previous ApplicationSet before trying the next.

Push first:
```bash
git add Chapter07_ApplicationSets && git commit -m "Chapter07: ApplicationSets" && git push origin main
```

---

## Generator 1 — List (baseline)

The simplest generator: you enumerate the elements. Each becomes one Application.

```bash
kubectl apply -f Chapter07_ApplicationSets/generators/01-list-generator.yaml
argocd appset list
argocd app list          # → web-dev, web-qa, web-prod
```

How the template maps:
- element `{ env: dev }` → app `web-dev`, path `apps/dev`, namespace `dev`.

View a page:
```bash
kubectl -n dev port-forward svc/web 8080:80    # open http://localhost:8080 (green)
```

Clean up before the next generator:
```bash
kubectl delete -f Chapter07_ApplicationSets/generators/01-list-generator.yaml
```

---

## Generator 2 — Git directory ⭐ ("check repo and try")

ArgoCD **scans the repo** and creates one Application per folder under
`apps/*`. The magic: **add a folder, get an app** — no edit to the generator.

```bash
kubectl apply -f Chapter07_ApplicationSets/generators/02-git-directory-generator.yaml
argocd app list          # → web-dev, web-qa, web-prod (discovered from folders)
```

Template variables (Git directory generator):
- `{{.path.path}}` → full folder path (used as the app's `source.path`)
- `{{.path.basename}}` → just the folder name (used as app name + namespace)

**Try the self-service flow** — create a 4th env and watch an app appear:
```bash
# make a new folder by copying qa, tweak the page text, then:
cp -r Chapter07_ApplicationSets/apps/qa Chapter07_ApplicationSets/apps/uat
#   (edit apps/uat/* labels/text to 'uat' if you like)
git add Chapter07_ApplicationSets/apps/uat && git commit -m "add uat env" && git push
# within a minute:
argocd app list          # → web-uat now exists, no generator change!
```

Clean up:
```bash
kubectl delete -f Chapter07_ApplicationSets/generators/02-git-directory-generator.yaml
```

---

## Generator 3 — Cluster ⭐

Creates one Application **per registered cluster**, deploying the same
`cluster-app/` to each. Add a cluster later → it self-populates.

```bash
argocd cluster list      # what will be generated (incl. local "in-cluster")
kubectl apply -f Chapter07_ApplicationSets/generators/03-cluster-generator.yaml
argocd app list          # → web-in-cluster, web-qa, web-prod (one per cluster)
```

Template variables (Cluster generator): `{{.name}}` (cluster name),
`{{.server}}` (API URL), plus any cluster labels.

**Target a subset with labels** (e.g. only prod clusters) — label the cluster then
use a `selector` (commented example is in the file):
```bash
argocd cluster set <cluster-name> --label environment=prod    # or label the secret
```

View the purple page on any cluster:
```bash
kubectl --context <ctx> -n appset-cluster port-forward svc/web 8080:80
```

Clean up:
```bash
kubectl delete -f Chapter07_ApplicationSets/generators/03-cluster-generator.yaml
```

---

## Generator 4 — Matrix (bonus): Clusters × Git

The **matrix** generator multiplies two generators. Here: **every env folder** on
**every cluster** → a grid. Parameters from both children are available together.

```bash
kubectl apply -f Chapter07_ApplicationSets/generators/04-matrix-generator.yaml
argocd app list
# e.g. 3 envs × 3 clusters = 9 apps:
#   web-dev-in-cluster, web-qa-in-cluster, web-prod-in-cluster,
#   web-dev-qa, web-qa-qa, ...  (name = env + cluster)
```

App name template `web-{{.path.basename}}-{{.name}}` keeps every combination
unique. Clean up:
```bash
kubectl delete -f Chapter07_ApplicationSets/generators/04-matrix-generator.yaml
```

---

## How ApplicationSets work (mental model)

```
  generator  ──►  produces a list of parameter sets  ──►  template renders one
                  e.g. {env: dev}, {env: qa}              Application per set
                       {path:apps/dev,...}                 (managed by ArgoCD)
                       {name: qa, server: ...}
```

- **One ApplicationSet owns many Applications.** Delete the ApplicationSet →
  its generated Applications are removed too.
- Change the **template** once → every generated app updates.
- Change the **generator input** (add a folder / cluster / list item) → apps are
  added or removed automatically.

## Other generators (for reference)

| Generator | Produces one app per… |
|-----------|-----------------------|
| List | inline element |
| Git directory | folder in a repo |
| Git file | entry in a config file (e.g. `config.json` per app) |
| Cluster | registered cluster |
| Cluster decision resource | cluster chosen by a placement resource |
| SCM Provider | repo in a GitHub/GitLab org |
| Pull Request | open PR (great for preview envs) |
| Matrix | cross-product of two generators |
| Merge | combine generators, overriding by key |

---

## 🧰 Troubleshooting

- **ApplicationSet created but no apps** — check the controller:
  `kubectl -n argocd logs deploy/argocd-applicationset-controller`. Common cause:
  template path doesn't exist in the repo, or the branch is wrong.
- **`map has no entry for key "env"` / template errors** — version mismatch with
  `goTemplate`. Use `{{.env}}` with `goTemplate: true` (v2.5+) or `{{env}}` without.
- **Git generator finds nothing** — the `path:` glob doesn't match; it's relative
  to the repo root (`Chapter07_ApplicationSets/apps/*`), and only **directories**
  are matched by the directory generator.
- **Cluster generator only shows `in-cluster`** — no remote clusters registered;
  run `argocd cluster add <context>` (Chapter 5).
- **Ownership conflict / OutOfSync flapping** — two ApplicationSets targeting the
  same namespace+names. Apply one at a time; delete before switching.

## 🧹 Cleanup

```bash
kubectl delete -f Chapter07_ApplicationSets/generators/     # removes whichever ones are applied
kubectl delete ns dev qa prod appset-cluster --ignore-not-found
```

---

### One-line recap for students
> An **ApplicationSet** = one template + a **generator**. The generator decides the
> set (a list, repo folders, clusters, or a matrix of them), and ArgoCD creates one
> Application for each — automatically kept in sync as the set changes.

Happy Learning!
