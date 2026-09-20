# Chapter 8: ApplicationSet — Pull Request Generator (Preview Environments)

The **Pull Request generator** creates one ArgoCD Application **per open pull
request** and deletes it when the PR is merged or closed. This gives every PR its
own **ephemeral preview environment** — reviewers see the change running, not just
the diff.

- **Repo:** `https://github.com/Ashutoshdocs/lectureArgoCD.git`
- **Base path:** `Chapter08_ApplicationSet_PullRequest`

---

## 🔀 How it works

```
   Open PR #42 (label: preview)
            │
            ▼
   ApplicationSet PR generator  ── polls GitHub every 60s (or via webhook) ──►
            │  finds open PRs → one parameter set each: {number, branch, head_sha}
            ▼
   Template renders one Application per PR:
        name:      web-pr-42
        revision:  <PR's head commit>          ← deploys the PR branch's code
        namespace: preview-pr-42               ← isolated per PR
            │
            ▼
   ArgoCD syncs → preview app running for PR #42
            │
   Merge / close PR  ──►  generator drops it  ──►  Application + namespace removed
```

Key idea: `targetRevision: {{.head_sha}}` means the preview runs **the code on the
PR's branch**, so editing files in the PR updates its preview.

---

## 📁 Files

```
Chapter08_ApplicationSet_PullRequest/
├── README.md
├── pr-generator.yaml                    # the ApplicationSet (PR generator)
├── github-token-secret.example.yaml     # token template (DON'T commit real one)
└── preview-app/                         # 🩵 app deployed for each PR
    ├── configmap.yaml                   # the preview page
    ├── deployment.yaml
    └── service.yaml
```

---

## ✅ Prerequisites

- ArgoCD + the **ApplicationSet controller** running (bundled since v2.3+):
  ```bash
  kubectl -n argocd get deploy argocd-applicationset-controller
  ```
- `argocd` CLI logged in.
- A **GitHub Personal Access Token** to list PRs:
  - Public repo → classic PAT with **`public_repo`** (or fine-grained, read-only
    **Pull requests**). A token isn't strictly required for public repos but avoids
    rate limits.
  - Private repo → **`repo`** scope.
- This chapter pushed to your repo's `main`.

Push first:
```bash
git add Chapter08_ApplicationSet_PullRequest && git commit -m "Chapter08: PR preview envs" && git push origin main
```

---

## 1. Create the GitHub token secret

Create it imperatively so the token never lands in Git:

```bash
kubectl -n argocd create secret generic github-token \
  --from-literal=token='ghp_your_token' \
  --dry-run=client -o yaml | kubectl apply -f -

# label it so the ApplicationSet controller can use it as a credential
kubectl -n argocd label secret github-token argocd.argoproj.io/secret-type=repo-creds --overwrite
```

> Prefer a file? Copy `github-token-secret.example.yaml` → `github-token-secret.yaml`,
> fill it in, `kubectl apply -f` it. It's already in `.gitignore`.

## 2. Apply the ApplicationSet

```bash
kubectl apply -f Chapter08_ApplicationSet_PullRequest/pr-generator.yaml
kubectl -n argocd get applicationset web-pr-preview
argocd app list          # empty until a matching PR is open
```

The generator watches **open PRs labeled `preview`** on `Ashutoshdocs/lectureArgoCD`.

---

## 3. Demo: open a PR and watch a preview appear ⭐

```bash
# 1) branch + change the preview page so this PR looks distinct
git checkout -b feature/hero-copy
#   edit Chapter08_ApplicationSet_PullRequest/preview-app/configmap.yaml
#   (e.g. change the <h1> text to "🔀 Preview for my feature")
git commit -am "tweak preview hero copy"
git push -u origin feature/hero-copy
```

Open the PR on GitHub and **add the `preview` label** to it. Within ~60s:

```bash
argocd app list                     # → web-pr-<N> appears
kubectl get ns | grep preview-pr    # → preview-pr-<N> namespace created
```

View the PR's preview (its branch content):

```bash
kubectl -n preview-pr-<N> port-forward svc/web 8080:80   # open http://localhost:8080
```

Push more commits to the branch → the preview re-syncs to the new commit.

## 4. Demo: close/merge the PR → env destroyed

Merge or close the PR. Within ~60s the generator drops that element:

```bash
argocd app list                     # web-pr-<N> is gone
kubectl get ns | grep preview-pr    # namespace pruned
```

That's the whole lifecycle: **PR opens → env is born; PR closes → env dies.**

---

## Template variables (Pull Request generator)

| Variable | Meaning |
|----------|---------|
| `{{.number}}` | PR number (used for app name + namespace) |
| `{{.branch}}` | PR source branch name |
| `{{.branch_slug}}` | branch name sanitised for DNS/labels |
| `{{.target_branch}}` | the base branch (e.g. `main`) |
| `{{.head_sha}}` | PR's head commit (pin the deploy to it) |
| `{{.labels}}` | PR labels (GitHub) |

> Using `branch` in hostnames? Prefer `{{.branch_slug}}` — it's safe for DNS.

## Filtering which PRs get a preview

```yaml
generators:
  - pullRequest:
      github: { owner: ..., repo: ..., labels: [ preview ] }   # only labelled PRs
      filters:
        - branchMatch: "^feature/.*"     # only feature branches
```

Common patterns: require a `preview` label (used here), restrict to `feature/*`
branches, or only PRs targeting `main`.

## Instant updates with a webhook (optional)

Polling every `requeueAfterSeconds` is simplest. For instant reaction, point a
GitHub **webhook** (Pull request + Push events) at the ArgoCD ApplicationSet
webhook endpoint (`/api/webhook`) so previews appear/update the moment a PR
changes. Polling is fine for a classroom demo.

---

## 🧰 Troubleshooting

- **No app after opening a PR** — is the `preview` label on the PR? Check the
  controller logs:
  `kubectl -n argocd logs deploy/argocd-applicationset-controller -f`.
- **`401`/`403` to GitHub** — token missing/expired or wrong scope; recreate the
  `github-token` secret. Public repos still hit **rate limits** without a token.
- **App created but Sync fails** — `path` must exist **on the PR's branch/commit**.
  If your PR deleted or moved `preview-app/`, the preview can't render.
- **Preview not torn down** — the ApplicationSet controller isn't running, or the
  PR is still open/labelled. Confirm the label was removed or the PR closed.
- **Version differences** — older ArgoCD uses `{{number}}` (no dot). This chapter
  uses `goTemplate: true` (v2.5+) → `{{.number}}`.

## 🧹 Cleanup

```bash
kubectl delete -f Chapter08_ApplicationSet_PullRequest/pr-generator.yaml   # removes all previews
kubectl -n argocd delete secret github-token
# close any demo PRs; delete leftover namespaces if any:
kubectl get ns | grep preview-pr | awk '{print $1}' | xargs -r kubectl delete ns
```

---

### One-line recap for students
> The **Pull Request generator** turns every open PR into its own running preview
> app (from that PR's commit) and deletes it when the PR closes — automated,
> isolated review environments straight from GitOps.

Happy Learning!
