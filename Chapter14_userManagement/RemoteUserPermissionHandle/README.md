# Chapter 14 – Remote User Permission Handling in Argo CD (Alice vs Bob)

This demo creates **two local Argo CD users, `alice` and `bob`**, on a **kubeadm** Kubernetes cluster. Both log in **from a Windows laptop with the `argocd` CLI**. RBAC and AppProjects then prove that each user is isolated:

| Capability | Alice | Bob |
|---|---|---|
| See / manage `alice-app` | ✅ | ❌ (invisible) |
| See / manage `bob-app` | ❌ (invisible) | ✅ |
| Create, sync, update, rollback, override, view logs, run resource actions (restart) on **own** app | ✅ | ✅ |
| **Delete** own app | ❌ | ❌ |
| Deploy outside own namespace | ❌ | ❌ |
| Create cluster-scoped resources | ❌ | ❌ |

Each app is a different workload with its own NodePort:

| App | Image | Namespace | NodePort | URL |
|---|---|---|---|---|
| `alice-app` | nginx | `alice-ns` | **31001** | `http://<NODE-IP>:31001` |
| `bob-app` | Apache httpd | `bob-ns` | **31002** | `http://<NODE-IP>:31002` |

---

## Table of Contents

1. [Architecture](#1-architecture)
2. [Prerequisites](#2-prerequisites)
3. [Directory Layout](#3-directory-layout)
4. [Push the Files to GitHub](#4-push-the-files-to-github)
5. [Install Argo CD on the Cluster](#5-install-argo-cd-on-the-cluster)
6. [Expose Argo CD with a NodePort](#6-expose-argo-cd-with-a-nodeport)
7. [Log In as Admin on the VM](#7-log-in-as-admin-on-the-vm)
8. [Create Namespaces](#8-create-namespaces)
9. [Create Users Alice and Bob](#9-create-users-alice-and-bob)
10. [Set Passwords for the Users](#10-set-passwords-for-the-users)
11. [Create AppProjects](#11-create-appprojects-the-fences)
12. [Configure RBAC](#12-configure-rbac-the-permissions)
13. [Install the Argo CD CLI on Windows](#13-install-the-argo-cd-cli-on-windows)
14. [Demo as Alice](#14-demo-as-alice)
15. [Demo as Bob](#15-demo-as-bob)
16. [Permission Test Matrix](#16-permission-test-matrix)
17. [How It Works](#17-how-it-works)
18. [Troubleshooting](#18-troubleshooting)
19. [Cleanup](#19-cleanup)

> **Shortcut:** steps 5–12 are automated in `scripts/admin-setup.sh`. Read through them once anyway, because they explain what the script does.

---

## 1. Architecture

```
  Windows laptop                               kubeadm cluster (VM)
 ┌──────────────────────┐                ┌──────────────────────────────────────────┐
 │ argocd CLI           │  HTTPS :30443  │  namespace: argocd                       │
 │  context "alice" ────┼───────────────►│   argocd-server  (NodePort 30443)        │
 │  context "bob"   ────┼───────────────►│     ├─ argocd-cm       -> users          │
 │                      │                │     ├─ argocd-rbac-cm  -> permissions    │
 │ Browser              │                │     └─ AppProjects     -> fences         │
 │  :31001 ─────────────┼───────────────►│  namespace: alice-ns  alice-web (nginx)  │
 │  :31002 ─────────────┼───────────────►│  namespace: bob-ns    bob-web   (httpd)  │
 └──────────────────────┘                └──────────────────────────────────────────┘
                                                        ▲
                                                        │ pulls manifests
                                    github.com/Ashutoshdocs/lectureArgoCD
                                    └─ Chapter14_userManagement/RemoteUserPermissionHandle/apps/{alice-app,bob-app}
```

Three layers of control work together:

1. **`argocd-cm`** defines *who* can log in (`alice`, `bob`).
2. **`argocd-rbac-cm`** defines *what* they can do, and on *which* project.
3. **`AppProject`** defines *where* apps in a project may deploy from and to, and *which kinds* of resources they may create.

---

## 2. Prerequisites

| Item | Notes |
|---|---|
| kubeadm cluster | 1 control plane + ≥1 worker (single node with the control-plane taint removed is fine) |
| `kubectl` on the control-plane VM | with cluster-admin kubeconfig |
| Outbound internet from the cluster | to pull Argo CD images and reach GitHub |
| GitHub repo **public** | `https://github.com/Ashutoshdocs/lectureArgoCD` (otherwise add repo credentials, see Troubleshooting) |
| Windows laptop | PowerShell, network route to the node IP |
| Firewall | allow TCP **30443**, **31001**, **31002** to the node from the laptop |

Find the node IP. This document uses `192.168.1.50` as the example, so replace it everywhere:

```bash
kubectl get nodes -o wide      # look at INTERNAL-IP
```

---

## 3. Directory Layout

```
Chapter14_userManagement/
└── RemoteUserPermissionHandle/
    ├── README.md                          <- this guide
    ├── argocd-config/
    │   ├── argocd-server-svc-patch.yaml   <- exposes Argo CD on NodePort 30443/30080
    │   ├── namespaces.yaml                <- alice-ns, bob-ns
    │   ├── argocd-cm-patch.yaml           <- creates users alice & bob
    │   └── argocd-rbac-cm-patch.yaml      <- RBAC policy (roles + bindings)
    ├── projects/
    │   ├── alice-project.yaml             <- AppProject: only alice-ns
    │   └── bob-project.yaml               <- AppProject: only bob-ns
    ├── apps/                              <- what Argo CD deploys (Git source)
    │   ├── alice-app/
    │   │   ├── kustomization.yaml
    │   │   ├── configmap.yaml             <- "Hello from ALICE" page
    │   │   ├── deployment.yaml            <- nginx, 2 replicas
    │   │   └── service.yaml               <- NodePort 31001
    │   └── bob-app/
    │       ├── kustomization.yaml
    │       ├── configmap.yaml             <- "Hello from BOB" page
    │       ├── deployment.yaml            <- httpd, 1 replica
    │       └── service.yaml               <- NodePort 31002
    ├── applications/                      <- OPTIONAL: admin-created Application CRs
    │   ├── alice-app.yaml
    │   └── bob-app.yaml
    └── scripts/
        ├── admin-setup.sh                 <- automates steps 5-12 on the VM
        └── verify-permissions.ps1         <- runs the test matrix from Windows
```

---

## 4. Push the Files to GitHub

Argo CD pulls `apps/alice-app` and `apps/bob-app` from Git, so the files must be in the repo before the users create their apps.

```bash
git clone https://github.com/Ashutoshdocs/lectureArgoCD.git
cd lectureArgoCD
# unzip so the files land at  lectureArgoCD/Chapter14_userManagement/RemoteUserPermissionHandle/  then:
git add Chapter14_userManagement/RemoteUserPermissionHandle
git commit -m "Chapter 14: remote user permission handling demo"
git push origin main
```

Then clone or pull the repo on the **control-plane VM** too, because the admin steps below run from inside `Chapter14_userManagement/RemoteUserPermissionHandle/`:

```bash
git clone https://github.com/Ashutoshdocs/lectureArgoCD.git
cd lectureArgoCD/Chapter14_userManagement/RemoteUserPermissionHandle
```

---

## 5. Install Argo CD on the Cluster

*Run on the control-plane VM.*

```bash
kubectl create namespace argocd

kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

> `--server-side` is needed because recent Argo CD CRDs are too large for client-side apply's annotation.

Wait until everything is `Running`:

```bash
kubectl -n argocd get pods -w
```

---

## 6. Expose Argo CD with a NodePort

```bash
kubectl -n argocd patch svc argocd-server --patch-file argocd-config/argocd-server-svc-patch.yaml
kubectl -n argocd get svc argocd-server
```

Expected output:

```
NAME            TYPE       CLUSTER-IP     PORT(S)                      AGE
argocd-server   NodePort   10.96.x.x      80:30080/TCP,443:30443/TCP   5m
```

The Argo CD UI and API are now at `https://192.168.1.50:30443`.

---

## 7. Log In as Admin on the VM

Install the Linux CLI on the VM:

```bash
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd /usr/local/bin/argocd && rm argocd
argocd version --client
```

Get the initial admin password and log in:

```bash
ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)
echo $ADMIN_PASSWORD

argocd login 192.168.1.50:30443 --username admin --password "$ADMIN_PASSWORD" \
  --insecure --grpc-web --name admin
```

> `--insecure` accepts Argo CD's self-signed certificate. `--grpc-web` makes the CLI work reliably over NodePorts and proxies.

---

## 8. Create Namespaces

The AppProjects forbid cluster-scoped resources, so users can't create namespaces themselves. The admin creates them:

```bash
kubectl apply -f argocd-config/namespaces.yaml
kubectl get ns alice-ns bob-ns
```

---

## 9. Create Users Alice and Bob

Argo CD *local users* are declared in the `argocd-cm` ConfigMap:

```yaml
# argocd-config/argocd-cm-patch.yaml
data:
  accounts.alice: login            # may log in with a password (UI + CLI)
  accounts.alice.enabled: "true"
  accounts.bob: login
  accounts.bob.enabled: "true"
```

```bash
kubectl -n argocd patch configmap argocd-cm --patch-file argocd-config/argocd-cm-patch.yaml
argocd account list
```

Expected output:

```
NAME   ENABLED  CAPABILITIES
admin  true     login
alice  true     login
bob    true     login
```

> Capabilities: `login` allows a username and password. `apiKey` allows generating tokens (`argocd account generate-token`). You can combine them as `login, apiKey`.

---

## 10. Set Passwords for the Users

New accounts have **no password**, so the admin sets one. `--current-password` is the **admin's** password, because admin is the user who is logged in.

```bash
argocd account update-password --account alice \
  --current-password "$ADMIN_PASSWORD" --new-password 'Alice@12345'

argocd account update-password --account bob \
  --current-password "$ADMIN_PASSWORD" --new-password 'Bob@12345'
```

> Passwords must be 8–32 characters. After their first login, users can change their own password with `argocd account update-password`.

---

## 11. Create AppProjects (the "fences")

```bash
kubectl apply -f projects/alice-project.yaml
kubectl apply -f projects/bob-project.yaml
argocd proj list
```

What `alice-project` enforces (`bob-project` is the same, but for `bob-ns`):

| Field | Value | Effect |
|---|---|---|
| `sourceRepos` | lectureArgoCD repo only | can't deploy from arbitrary Git repos |
| `destinations` | `in-cluster` / `alice-ns` | can't deploy into `bob-ns`, `kube-system`, etc. |
| `clusterResourceWhitelist` | `[]` | no Namespaces, ClusterRoles, CRDs… |
| `namespaceResourceWhitelist` | Deployment, Service, ConfigMap | only these kinds may be created |

---

## 12. Configure RBAC (the permissions)

```bash
kubectl -n argocd patch configmap argocd-rbac-cm --patch-file argocd-config/argocd-rbac-cm-patch.yaml
```

The policy for Alice (Bob's policy mirrors it):

```csv
p, role:alice-role, applications, get,      alice-project/*, allow   # see / list
p, role:alice-role, applications, create,   alice-project/*, allow   # create apps
p, role:alice-role, applications, update,   alice-project/*, allow   # change spec (image, replicas, revision...)
p, role:alice-role, applications, sync,     alice-project/*, allow   # sync + rollback
p, role:alice-role, applications, override, alice-project/*, allow   # local/parameter overrides
p, role:alice-role, applications, action/*, alice-project/*, allow   # e.g. restart Deployment
p, role:alice-role, logs,         get,      alice-project/*, allow   # pod logs
p, role:alice-role, projects,     get,      alice-project,   allow   # see own project
p, role:alice-role, applications, delete,   alice-project/*, deny    # NEVER delete
g, alice, role:alice-role
```

Plus `policy.default: ""`, which means **no** default role. Anything not listed is denied.

Validate the policy with the admin account:

```bash
argocd admin settings rbac can alice get    applications 'alice-project/alice-app' --namespace argocd   # Yes
argocd admin settings rbac can alice delete applications 'alice-project/alice-app' --namespace argocd   # No
argocd admin settings rbac can alice get    applications 'bob-project/bob-app'     --namespace argocd   # No
argocd admin settings rbac can bob   sync   applications 'bob-project/bob-app'     --namespace argocd   # Yes
```

> RBAC changes take effect immediately. No restart is needed.

**The admin side is done.** Everything below happens on the **Windows laptop**.

---

## 13. Install the Argo CD CLI on Windows

Open **PowerShell**:

```powershell
# Create a folder for the binary
New-Item -ItemType Directory -Force -Path C:\argocd | Out-Null

# Download the latest Windows CLI
$version = (Invoke-RestMethod https://api.github.com/repos/argoproj/argo-cd/releases/latest).tag_name
Invoke-WebRequest -Uri "https://github.com/argoproj/argo-cd/releases/download/$version/argocd-windows-amd64.exe" `
                  -OutFile C:\argocd\argocd.exe

# Add it to the user PATH (permanent) and to this session
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\argocd", "User")
$env:Path += ";C:\argocd"

argocd version --client
```

> Alternative: `choco install argocd-cli` if you use Chocolatey.

Check connectivity to the cluster:

```powershell
Test-NetConnection 192.168.1.50 -Port 30443
```

Expected output: `TcpTestSucceeded : True`

---

## 14. Demo as Alice

### 14.1 Log in

```powershell
argocd login 192.168.1.50:30443 --username alice --password 'Alice@12345' --insecure --grpc-web --name alice
```

Expected output:

```
'alice:login' logged in successfully
Context 'alice' updated
```

Confirm who you are:

```powershell
argocd account get-user-info
```

Expected output:

```
Logged In: true
Username: alice
Issuer: argocd
Groups:
```

### 14.2 What can Alice see?

```powershell
argocd proj list   # only alice-project
argocd app list    # empty for now (bob-app is invisible to her)
```

### 14.3 Create her application

```powershell
argocd app create alice-app `
  --project alice-project `
  --repo https://github.com/Ashutoshdocs/lectureArgoCD.git `
  --revision main `
  --path Chapter14_userManagement/RemoteUserPermissionHandle/apps/alice-app `
  --dest-server https://kubernetes.default.svc `
  --dest-namespace alice-ns
```

> If you prefer the admin to pre-create the apps, run `kubectl apply -f applications/` on the VM instead and skip this step.

### 14.4 Sync and check

```powershell
argocd app sync alice-app
argocd app wait alice-app --health --timeout 120
argocd app get  alice-app
```

Open **http://192.168.1.50:31001**, which shows *"Hello from ALICE's application"*.

### 14.5 Make changes (allowed)

```powershell
# Scale from 2 to 3 replicas (kustomize override stored in the Application spec)
argocd app set alice-app --kustomize-replica alice-web=3
argocd app sync alice-app

# Change the image version
argocd app set alice-app --kustomize-image nginx=nginx:1.26-alpine
argocd app sync alice-app

# See history and roll back to the first deployment
argocd app history alice-app
argocd app rollback alice-app 0        # use an ID from the history output

# Restart the Deployment (resource action)
argocd app actions run alice-app restart --kind Deployment --resource-name alice-web

# View logs
argocd app logs alice-app --kind Deployment --name alice-web --tail 20

# Live diff / manifests
argocd app diff alice-app
argocd app manifests alice-app
```

> `argocd app rollback` only works while auto-sync is disabled. This demo uses manual sync on purpose.

### 14.6 Try forbidden things (denied)

```powershell
argocd app delete alice-app --yes
#  -> PermissionDenied ... permission denied: applications, delete, alice-project/alice-app, sub: alice

argocd account can-i delete applications 'alice-project/alice-app'
#  -> no

# Try to create an app in Bob's project
argocd app create sneaky --project bob-project `
  --repo https://github.com/Ashutoshdocs/lectureArgoCD.git --path Chapter14_userManagement/RemoteUserPermissionHandle/apps/alice-app `
  --dest-server https://kubernetes.default.svc --dest-namespace bob-ns
#  -> PermissionDenied (no rights on bob-project)

# Try to deploy into Bob's namespace from her own project
argocd app create sneaky --project alice-project `
  --repo https://github.com/Ashutoshdocs/lectureArgoCD.git --path Chapter14_userManagement/RemoteUserPermissionHandle/apps/alice-app `
  --dest-server https://kubernetes.default.svc --dest-namespace bob-ns
#  -> InvalidArgument: destination ... bob-ns is not permitted in project 'alice-project'
```

---

## 15. Demo as Bob

Log in as Bob. This creates a **second context**, so Alice's session is kept:

```powershell
argocd login 192.168.1.50:30443 --username bob --password 'Bob@12345' --insecure --grpc-web --name bob

argocd context           # lists contexts; * marks the active one
#   CURRENT  NAME   SERVER
#            alice  192.168.1.50:30443
#   *        bob    192.168.1.50:30443
```

Create, sync and verify his app:

```powershell
argocd app create bob-app `
  --project bob-project `
  --repo https://github.com/Ashutoshdocs/lectureArgoCD.git `
  --revision main `
  --path Chapter14_userManagement/RemoteUserPermissionHandle/apps/bob-app `
  --dest-server https://kubernetes.default.svc `
  --dest-namespace bob-ns

argocd app sync bob-app
argocd app wait bob-app --health --timeout 120
argocd app list          # ONLY bob-app, alice-app is invisible
```

Open **http://192.168.1.50:31002**, which shows *"Hello from BOB's application"*.

Prove the isolation:

```powershell
argocd app get alice-app            # -> permission denied
argocd app delete alice-app --yes   # -> permission denied
argocd app delete bob-app --yes     # -> permission denied (can't delete his own either)

argocd app set bob-app --kustomize-replica bob-web=2   # allowed
argocd app sync bob-app                                 # allowed
```

Switch back to Alice at any time:

```powershell
argocd context alice
argocd app list          # ONLY alice-app
```

---

## 16. Permission Test Matrix

Run all checks automatically from the laptop, after both logins (steps 14.1 and 15) and after both apps exist:

```powershell
.\scripts\verify-permissions.ps1
```

| # | Command | As Alice | As Bob |
|---|---|---|---|
| 1 | `argocd app list` | `alice-app` only | `bob-app` only |
| 2 | `argocd proj list` | `alice-project` only | `bob-project` only |
| 3 | `argocd app get alice-app` | ✅ | ❌ denied |
| 4 | `argocd app get bob-app` | ❌ denied | ✅ |
| 5 | `argocd app sync <own-app>` | ✅ | ✅ |
| 6 | `argocd app set <own-app> --kustomize-replica …` | ✅ | ✅ |
| 7 | `argocd app rollback <own-app> <id>` | ✅ | ✅ |
| 8 | `argocd app actions run <own-app> restart …` | ✅ | ✅ |
| 9 | `argocd app logs <own-app> …` | ✅ | ✅ |
| 10 | `argocd app delete <own-app>` | ❌ denied | ❌ denied |
| 11 | `argocd app delete <other-app>` | ❌ denied | ❌ denied |
| 12 | `argocd app create … --dest-namespace <other-ns>` | ❌ not permitted in project | ❌ not permitted in project |

The same isolation applies in the **web UI**. Log in at `https://192.168.1.50:30443` as each user and you will see only that user's app tile, and the **Delete** button fails with a permission error.

> Note: the users only have **Argo CD** access, not `kubectl` access. All their interaction with the cluster goes through Argo CD, which is exactly what makes this permission model enforceable.

---

## 17. How It Works

**Authentication.** `argocd login` sends the username and password to `argocd-server`. The server checks the bcrypt hash stored in the `argocd-secret` Secret (`accounts.alice.password`) and returns a JWT. The CLI saves it per context in `%USERPROFILE%\.config\argocd\config`.

**Authorization.** On every API call, Argo CD's RBAC enforcer evaluates `argocd-rbac-cm`:

```
subject=alice  resource=applications  action=delete  object=alice-project/alice-app
  -> matches "allow"? (no delete-allow rule)       
  -> matches "deny"?  yes  ->  DENIED
```

**Visibility.** `argocd app list` returns only apps for which the caller passes `applications, get`. Bob has no `get` rule on `alice-project/*`, so Alice's app is filtered out entirely.

**Defense in depth.** Even if someone added a too-broad RBAC rule by mistake, the **AppProject** still blocks deploying outside the project's namespace, from other repos, or creating cluster-scoped resources.

**Moving apps between projects.** Changing an app's project requires `update` permission on **both** the old and new project. Alice can't move her app into `bob-project`, and she can't steal Bob's app.

### Useful RBAC resources and actions

| Resource | Actions |
|---|---|
| `applications` | `get`, `create`, `update`, `delete`, `sync`, `override`, `action/<group>/<kind>/<action>` |
| `logs` | `get` |
| `exec` | `create` (needs `exec.enabled: "true"` in `argocd-cm`) |
| `projects` | `get`, `create`, `update`, `delete` |
| `repositories`, `clusters`, `certificates`, `gpgkeys`, `accounts` | `get`, `create`, `update`, `delete` |

---

## 18. Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `Invalid username or password` | Password not set (step 10), or the account is disabled. Run `argocd account list` as admin. |
| `account 'alice' does not exist` | The `argocd-cm` patch wasn't applied in the `argocd` namespace. |
| Login hangs or times out from Windows | Check `Test-NetConnection <ip> -Port 30443`, the VM firewall (`sudo ufw allow 30443/tcp`), and cloud security groups. |
| `transport: authentication handshake failed` | Add `--insecure` (self-signed cert) and `--grpc-web`. |
| `app list` shows nothing for Alice even after create | `policy.csv` has a typo in the project name. Run `argocd admin settings rbac validate --namespace argocd` on the VM. |
| Alice can see Bob's app | `policy.default` is set to `role:readonly`. Set it to `""`. |
| `repository not accessible` | The repo is private. As admin, run `argocd repo add https://github.com/Ashutoshdocs/lectureArgoCD.git --username <gh-user> --password <PAT>`. |
| `resource :Namespace is not permitted in project` | Don't use `CreateNamespace=true`. Namespaces are pre-created by the admin (step 8). |
| `provided port is already allocated` | NodePort 31001/31002/30443 is already in use. Change it in the YAML. |
| Pods `Pending` on a single-node cluster | Remove the control-plane taint: `kubectl taint nodes --all node-role.kubernetes.io/control-plane-` |
| Kustomize override disappears | Admin re-applied `applications/*.yaml`, which overwrites the spec. Either let users manage the app, or put changes in Git. |

See the Argo CD server log for RBAC decisions:

```bash
kubectl -n argocd logs deploy/argocd-server | grep -i "permission denied"
```

---

## 19. Cleanup

Users can't delete their apps, so the **admin** does it on the VM:

```bash
argocd context admin
argocd app delete alice-app --yes
argocd app delete bob-app   --yes

kubectl delete -f projects/
kubectl delete -f argocd-config/namespaces.yaml

# Remove the users
kubectl -n argocd patch configmap argocd-cm --type json -p '[
  {"op":"remove","path":"/data/accounts.alice"},
  {"op":"remove","path":"/data/accounts.alice.enabled"},
  {"op":"remove","path":"/data/accounts.bob"},
  {"op":"remove","path":"/data/accounts.bob.enabled"}]'

# Reset RBAC
kubectl -n argocd patch configmap argocd-rbac-cm --type json -p '[
  {"op":"remove","path":"/data/policy.csv"}]'
```

On Windows, remove the saved contexts:

```powershell
argocd logout alice
argocd logout bob
argocd context --delete alice
argocd context --delete bob
```
