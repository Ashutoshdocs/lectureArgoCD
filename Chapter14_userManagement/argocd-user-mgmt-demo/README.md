# Argo CD User & Permission Management Demo

A hands-on demo that creates **two local users** in Argo CD, logs in as each one, and shows how **RBAC** and **AppProjects** control what every user can see and do.

| User | Role | Project | Can do | Cannot do |
|------|------|---------|--------|-----------|
| **alice** | `alpha-developer` | `team-alpha` | View, create, edit, sync, delete team-alpha apps, view logs, generate API tokens | See team-beta apps, delete `alpha-protected`, deploy outside the `team-alpha` namespace |
| **bob** | `beta-operator` | `team-beta` | View and sync team-beta apps, view logs | Create, edit or delete apps, see team-alpha apps, generate API tokens |
| **admin** | `role:admin` | all | Everything | — |

---

## 1. Repository layout

```
argocd-user-mgmt-demo/
├── README.md
├── argocd-config/
│   ├── argocd-cm.yaml          # declares users alice & bob
│   ├── argocd-rbac-cm.yaml     # roles, permissions, user->role bindings
│   └── projects.yaml           # AppProjects team-alpha & team-beta
├── applications/
│   ├── team-alpha-apps.yaml    # alpha-nginx, alpha-protected
│   ├── team-beta-apps.yaml     # beta-httpd
│   └── out-of-bounds-app.yaml  # negative test (should be rejected)
└── manifests/
    ├── team-alpha/
    │   ├── nginx/              # Deployment + Service
    │   └── protected/          # ConfigMap + Deployment
    └── team-beta/
        └── httpd/              # Deployment + Service
```

### How the pieces fit together

```
  argocd-cm            argocd-rbac-cm                 AppProject
 (WHO exists)   --->   (WHAT they may do)    --->   (WHERE apps may deploy)
  alice, bob           alice -> alpha-developer       team-alpha -> ns team-alpha
                       bob   -> beta-operator         team-beta  -> ns team-beta
```

- **`argocd-cm`** – creates the accounts and their capabilities (`login`, `apiKey`).
- **`argocd-rbac-cm`** – maps users to roles and defines the allowed actions per project.
- **`AppProject`** – a hard boundary: allowed repos, destination namespaces and resource kinds. Even a user with full app permissions cannot go outside it.

---

## 2. Prerequisites

| Tool | Purpose |
|------|---------|
| Kubernetes cluster | `kind`, `minikube`, `k3d`, Docker Desktop, or any cloud cluster |
| `kubectl` | Talk to the cluster |
| `argocd` CLI | Log in and run the demo commands ([install guide](https://argo-cd.readthedocs.io/en/stable/cli_installation/)) |
| GitHub account | Host this repo so Argo CD can pull the manifests |

Quick local cluster (optional):

```bash
kind create cluster --name argocd-demo
```

---

## 3. Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait until all pods are Running
kubectl get pods -n argocd -w
```

Expose the UI/API (keep this terminal open):

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

UI: **https://localhost:8080** (accept the self-signed certificate).

---

## 4. Log in as admin

```bash
# Get the initial admin password
ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo $ADMIN_PASSWORD

# CLI login
argocd login localhost:8080 --username admin --password "$ADMIN_PASSWORD" --insecure
```

---

## 5. Push this repo to GitHub

Argo CD pulls manifests from Git, so the repo must be reachable.

1. Create a **public** GitHub repo named `argocd-user-mgmt-demo`.
2. Replace the placeholder repo URL in every file:

   ```bash
   # Linux
   grep -rl "YOUR-GITHUB-USER" . | xargs sed -i 's/YOUR-GITHUB-USER/<your-github-username>/g'
   # macOS
   grep -rl "YOUR-GITHUB-USER" . | xargs sed -i '' 's/YOUR-GITHUB-USER/<your-github-username>/g'
   ```

3. Push:

   ```bash
   git init
   git add .
   git commit -m "Argo CD user management demo"
   git branch -M main
   git remote add origin https://github.com/<your-github-username>/argocd-user-mgmt-demo.git
   git push -u origin main
   ```

---

## 6. Create the users (alice & bob)

The users are declared in `argocd-config/argocd-cm.yaml`:

```yaml
data:
  accounts.alice: apiKey, login   # UI/CLI login + API tokens
  accounts.bob: login             # UI/CLI login only
```

Apply it as a **merge patch** so existing settings in `argocd-cm` are kept:

```bash
kubectl patch configmap argocd-cm -n argocd --type merge \
  --patch-file argocd-config/argocd-cm.yaml
```

Verify the users exist:

```bash
argocd account list
```

Expected:

```
NAME   ENABLED  CAPABILITIES
admin  true     login
alice  true     apiKey, login
bob    true     login
```

### Set passwords

New users have **no password** until one is set. While logged in as admin, `--current-password` is the **admin's** password:

```bash
argocd account update-password --account alice \
  --current-password "$ADMIN_PASSWORD" --new-password 'Alice@12345'

argocd account update-password --account bob \
  --current-password "$ADMIN_PASSWORD" --new-password 'Bob@12345'
```

> Demo passwords only. Use strong passwords (or SSO) in real environments.

---

## 7. Apply permissions (RBAC) and projects

```bash
# Roles + user bindings
kubectl patch configmap argocd-rbac-cm -n argocd --type merge \
  --patch-file argocd-config/argocd-rbac-cm.yaml

# AppProjects (team boundaries)
kubectl apply -f argocd-config/projects.yaml
```

RBAC changes take effect immediately; no restart needed.

Check them as admin, without logging in as each user:

```bash
argocd admin settings rbac can alice get applications 'team-alpha/alpha-nginx' --namespace argocd   # Yes
argocd admin settings rbac can alice get applications 'team-beta/beta-httpd'   --namespace argocd   # No
argocd admin settings rbac can bob   sync applications 'team-beta/beta-httpd'  --namespace argocd   # Yes
argocd admin settings rbac can bob   delete applications 'team-beta/beta-httpd' --namespace argocd  # No
argocd admin settings rbac can alice delete applications 'team-alpha/alpha-protected' --namespace argocd  # No (explicit deny)
```

---

## 8. Create the applications (as admin)

```bash
kubectl apply -f applications/team-alpha-apps.yaml
kubectl apply -f applications/team-beta-apps.yaml

argocd app list
```

Admin sees all three apps: `alpha-nginx`, `alpha-protected`, `beta-httpd`. They start **OutOfSync** because sync is manual, so we can demo who is allowed to sync.

---

## 9. Demo: log in as each user

Open a **private/incognito window** per user so the sessions don't mix. In the CLI, logging in again simply replaces the current session.

### 9.1 alice (developer on team-alpha)

**UI:** https://localhost:8080 → username `alice`, password `Alice@12345`

**CLI:**

```bash
argocd login localhost:8080 --username alice --password 'Alice@12345' --insecure
argocd account get-user-info
```

| # | Try this | Command | Expected |
|---|----------|---------|----------|
| A1 | List apps | `argocd app list` | Only `alpha-nginx` and `alpha-protected` |
| A2 | Sync own app | `argocd app sync alpha-nginx` | ✅ Synced, pods come up in `team-alpha` |
| A3 | Sync protected app | `argocd app sync alpha-protected` | ✅ Allowed |
| A4 | View logs | `argocd app logs alpha-nginx` | ✅ nginx logs |
| A5 | Edit app settings | `argocd app set alpha-nginx --sync-policy automated` *(or UI → App Details → Edit)* | ✅ Allowed (update permission) |
| A6 | See team-beta app | `argocd app get beta-httpd` | ❌ `permission denied` |
| A7 | Delete protected app | `argocd app delete alpha-protected` | ❌ `permission denied` (explicit deny) |
| A8 | Generate API token | `argocd account generate-token --account alice` | ✅ Token printed (alice has `apiKey`) |
| A9 | Check own permissions | `argocd account can-i sync applications 'team-alpha/*'` | `yes` |
| A10 | Check own permissions | `argocd account can-i get applications 'team-beta/*'` | `no` |

#### Project boundary test (alice)

alice has `create` on `team-alpha/*`, but the AppProject only allows namespace `team-alpha`:

```bash
argocd app create alpha-escape-attempt \
  --project team-alpha \
  --repo https://github.com/<your-github-username>/argocd-user-mgmt-demo.git \
  --path manifests/team-alpha/nginx \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default
```

Expected: ❌ rejected — *destination ... namespace default is not permitted in project 'team-alpha'*.
(The same app is in `applications/out-of-bounds-app.yaml` if you prefer `kubectl apply`; it will be created but show an **InvalidSpecError** condition and never sync.)

### 9.2 bob (operator on team-beta)

**UI:** https://localhost:8080 → username `bob`, password `Bob@12345`

**CLI:**

```bash
argocd login localhost:8080 --username bob --password 'Bob@12345' --insecure
argocd account get-user-info
```

| # | Try this | Command | Expected |
|---|----------|---------|----------|
| B1 | List apps | `argocd app list` | Only `beta-httpd` |
| B2 | Sync own app | `argocd app sync beta-httpd` | ✅ Synced, pods come up in `team-beta` |
| B3 | View logs | `argocd app logs beta-httpd` | ✅ httpd logs |
| B4 | Delete app | `argocd app delete beta-httpd` | ❌ `permission denied` |
| B5 | Change app | `argocd app set beta-httpd --revision HEAD` | ❌ `permission denied` (no update) |
| B6 | Create app | `argocd app create test --project team-beta ...` | ❌ `permission denied` |
| B7 | See team-alpha app | `argocd app get alpha-nginx` | ❌ `permission denied` |
| B8 | Generate API token | `argocd account generate-token --account bob` | ❌ fails — bob has no `apiKey` capability |
| B9 | Check own permissions | `argocd account can-i delete applications 'team-beta/*'` | `no` |

In the **UI**, bob will see the Sync button on `beta-httpd`, but Delete and Edit actions fail with a permission error.

---

## 10. More user-management operations (as admin)

Log back in as admin first:

```bash
argocd login localhost:8080 --username admin --password "$ADMIN_PASSWORD" --insecure
```

### 10.1 Disable / re-enable a user

```bash
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"accounts.bob.enabled":"false"}}'

argocd account list                 # bob ENABLED=false
# Try logging in as bob -> fails

kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"accounts.bob.enabled":"true"}}'
```

### 10.2 Change a user's role (promote bob to read-only on everything)

Add this line to `policy.csv` in `argocd-config/argocd-rbac-cm.yaml` and re-apply:

```
g, bob, role:readonly
```

```bash
kubectl patch configmap argocd-rbac-cm -n argocd --type merge \
  --patch-file argocd-config/argocd-rbac-cm.yaml
```

bob can now **see** team-alpha apps too (but still not change them). Remove the line and re-apply to revert.

### 10.3 Reset a user's password

```bash
argocd account update-password --account alice \
  --current-password "$ADMIN_PASSWORD" --new-password 'NewAlice@2026'
```

### 10.4 List and revoke API tokens

```bash
argocd account get --account alice          # shows token IDs
argocd account delete-token --account alice <TOKEN_ID>
```

### 10.5 Project-scoped token for CI (no user needed)

`projects.yaml` defines a role `ci-sync` inside `team-alpha` that can only get/sync team-alpha apps:

```bash
argocd proj role create-token team-alpha ci-sync
# Use it from a pipeline:
argocd app sync alpha-nginx --auth-token <TOKEN> --server localhost:8080 --insecure
argocd app get  beta-httpd  --auth-token <TOKEN> --server localhost:8080 --insecure   # denied
```

### 10.6 (Optional) Disable the built-in admin

Only after another user has `role:admin`:

```bash
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"admin.enabled":"false"}}'
```

---

## 11. RBAC quick reference

```
p, <subject>, <resource>, <action>, <project>/<object>, <allow|deny>
g, <user-or-group>, <role>
```

| Resource | Common actions |
|----------|----------------|
| `applications` | `get`, `create`, `update`, `delete`, `sync`, `override`, `action/*` |
| `logs` | `get` |
| `exec` | `create` (web terminal, also needs `exec.enabled: "true"` in argocd-cm) |
| `projects` | `get`, `create`, `update`, `delete` |
| `repositories`, `clusters`, `certificates`, `gpgkeys` | `get`, `create`, `update`, `delete` |
| `accounts` | `get`, `update` |

Rules to remember:
- `deny` always wins over `allow`.
- `policy.default` applies to any authenticated user with no matching rule (`""` = no access, `role:readonly` = view everything).
- Built-in roles: `role:admin`, `role:readonly`.
- RBAC says *what* a user can do; the AppProject says *where* apps can go. Both must allow an action.

---

## 12. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `account alice does not exist` | Patch `argocd-cm` (step 6) and check `argocd account list` |
| Login fails right after creating a user | Set the password first (step 6) |
| `update-password` fails with *current password does not match* | Use the **admin** password as `--current-password` while logged in as admin |
| User sees **no apps** | Check the `g, user, role:...` line in `argocd-rbac-cm` and the project name in the policy |
| App stuck with `repository not permitted` | Repo URL in the Application must exactly match `sourceRepos` in the AppProject |
| App `Unknown`/`ComparisonError` | The GitHub repo is private or the URL placeholder wasn't replaced |
| Test permissions without logging in | `argocd admin settings rbac can <user> <action> <resource> '<proj>/<app>' --namespace argocd` |

Validate the RBAC file offline before applying:

```bash
argocd admin settings rbac validate --policy-file <(kubectl get cm argocd-rbac-cm -n argocd -o jsonpath='{.data.policy\.csv}')
```

---

## 13. Clean up

```bash
kubectl delete -f applications/ --ignore-not-found
kubectl delete -f argocd-config/projects.yaml
kubectl delete namespace team-alpha team-beta --ignore-not-found

# Remove the demo users
kubectl patch configmap argocd-cm -n argocd --type json -p '[
  {"op":"remove","path":"/data/accounts.alice"},
  {"op":"remove","path":"/data/accounts.alice.enabled"},
  {"op":"remove","path":"/data/accounts.bob"},
  {"op":"remove","path":"/data/accounts.bob.enabled"}
]'

# Or remove Argo CD completely
kubectl delete namespace argocd
kind delete cluster --name argocd-demo   # if you used kind
```
