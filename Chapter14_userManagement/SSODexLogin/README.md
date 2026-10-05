# Chapter 14 – SSO Login to Argo CD with Dex (LDAP) – End to End

This demo replaces "a local password per user" with **Single Sign-On**:

- Argo CD's **bundled Dex** acts as the OIDC provider.
- Dex authenticates users against an **OpenLDAP** directory that runs inside the cluster, so you need no external accounts and the demo is fully repeatable.
- **LDAP groups** travel inside the SSO token, and Argo CD RBAC maps those **groups**, not individual users, to permissions.
- Users log in from a **Windows laptop** with `argocd login --sso`, which opens a browser to the Dex login page.

| LDAP user | Password | LDAP group | Argo CD role | What they can do |
|---|---|---|---|---|
| `charlie` | `Charlie@123` | `dev-team` | `role:dev` | create / sync / update / rollback **dev-app**, **no delete** |
| `diana` | `Diana@123` | `ops-team` | `role:readonly` | **see** everything, change **nothing** |
| `eve` | `Eve@123` | *(none)* | *(none)* | logs in successfully but sees **nothing** |

You will then **prove** that SSO is in control by changing group membership in LDAP **only**. Charlie loses access and Eve gains access, and no Argo CD config is touched.

> This demo is independent of `../RemoteUserPermissionHandle`, but it can run on the same Argo CD instance. Its RBAC lives in a separate `policy.sso.csv` key, so the alice/bob rules are kept.

---

## Table of Contents

1. [Architecture & Login Flow](#1-architecture--login-flow)
2. [Prerequisites](#2-prerequisites)
3. [Directory Layout](#3-directory-layout)
4. [Push the Files to GitHub](#4-push-the-files-to-github)
5. [Install and Expose Argo CD](#5-install-and-expose-argo-cd-skip-if-already-done)
6. [Deploy the LDAP Identity Provider](#6-deploy-the-ldap-identity-provider)
7. [Store the LDAP Bind Password](#7-store-the-ldap-bind-password-in-argocd-secret)
8. [Configure Dex SSO in argocd-cm](#8-configure-dex-sso-in-argocd-cm)
9. [Configure Group-Based RBAC](#9-configure-group-based-rbac)
10. [Create the Namespace and Project](#10-create-the-namespace-and-project)
11. [Restart and Verify Dex](#11-restart-and-verify-dex)
12. [Proof 1 – SSO in the Browser (UI)](#12-proof-1--sso-in-the-browser-ui)
13. [Install the Argo CD CLI on Windows](#13-install-the-argo-cd-cli-on-windows)
14. [Proof 2 – CLI SSO as Charlie (dev-team)](#14-proof-2--cli-sso-as-charlie-dev-team)
15. [Proof 3 – CLI SSO as Diana (ops-team)](#15-proof-3--cli-sso-as-diana-ops-team)
16. [Proof 4 – CLI SSO as Eve (no group)](#16-proof-4--cli-sso-as-eve-no-group)
17. [Proof 5 – Central Access Control via LDAP](#17-proof-5--central-access-control-via-ldap)
18. [Proof 6 – Server-Side Evidence](#18-proof-6--server-side-evidence-logs--token)
19. [Permission Test Matrix](#19-permission-test-matrix)
20. [Optional Hardening](#20-optional-hardening)
21. [Troubleshooting](#21-troubleshooting)
22. [Cleanup](#22-cleanup)
23. [Appendix A – Add GitHub Login](#appendix-a--add-github-login-optional)

> **Shortcut:** steps 5–11 are automated by `NODE_IP=<your-ip> ./scripts/admin-setup.sh`.

---

## 1. Architecture & Login Flow

```
 Windows laptop                                    kubeadm cluster
┌───────────────────────────┐            ┌──────────────────────────────────────────────┐
│ argocd login --sso        │            │ namespace: argocd                            │
│   │ (1) starts localhost  │            │                                              │
│   │     :8085 listener    │            │  argocd-server  :30443 (NodePort)            │
│   ▼                       │  (2) HTTPS │   ├─ /api/dex/*  ──proxy──► argocd-dex-server│
│ Browser ──────────────────┼───────────►│   │                           │ (3) LDAP bind│
│  Dex login page           │            │   │                           ▼   + search   │
│  "Log in with Company LDAP"│◄──────────┤   │                namespace: ldap           │
│   │ (5) redirect with code│            │   │                openldap:389              │
│   ▼                       │            │   │                 users  : charlie,diana,eve│
│ localhost:8085/auth/callback           │   │                 groups : dev-team,ops-team│
│   │ (6) CLI swaps code for│◄───────────┤   │ (4) Dex issues ID token                  │
│   │     an ID token with  │            │   │     { email, groups:[dev-team] }         │
│   │     groups:[dev-team] │            │   └─ (7) RBAC: g, dev-team, role:dev         │
└───────────────────────────┘            └──────────────────────────────────────────────┘
```

1. The CLI starts a temporary listener on `localhost:8085` and opens the browser.
2. The browser goes to `https://<NODE-IP>:30443/api/dex/auth`, and Argo CD proxies the request to Dex.
3. The user types an LDAP username and password. Dex **binds** to LDAP as that user to check the password, then searches the groups the user belongs to.
4. Dex issues an **OIDC ID token** containing `email`, `name` and `groups`.
5. The browser is redirected back to the CLI at `localhost:8085` with an authorization code.
6. The CLI exchanges the code for the token and saves it in its context.
7. On every API call, Argo CD reads `groups` from the token and evaluates `argocd-rbac-cm`.

Argo CD **stores no SSO user accounts**. Identity and group membership live in LDAP, and Argo CD only maps groups to roles.

---

## 2. Prerequisites

| Item | Notes |
|---|---|
| kubeadm cluster | with `kubectl` cluster-admin access on the control-plane VM |
| Internet from the cluster | pulls `quay.io/argoproj/*`, `osixia/openldap`, `nginx`, and reaches GitHub |
| Repo is **public** | `https://github.com/Ashutoshdocs/lectureArgoCD` |
| Windows laptop | PowerShell + a default browser; can reach `<NODE-IP>:30443` and `:31003` |
| Firewall | allow TCP **30443** (Argo CD + Dex) and **31003** (dev-app) |

> Only **one** port is needed for SSO. Dex is served by argocd-server under `/api/dex`, so it needs no NodePort of its own.

Find the node IP. This guide uses `192.168.1.50`, so replace it everywhere:

```bash
kubectl get nodes -o wide
export NODE_IP=192.168.1.50
```

---

## 3. Directory Layout

```
Chapter14_userManagement/
└── SSODexLogin/
    ├── README.md
    ├── ldap/                                   <- demo identity provider
    │   ├── kustomization.yaml                  <- kubectl apply -k ldap/
    │   ├── namespace.yaml
    │   ├── secret.yaml                         <- admin / readonly passwords
    │   ├── bootstrap-ldif-configmap.yaml       <- users charlie, diana, eve + groups
    │   ├── deployment.yaml                     <- osixia/openldap
    │   ├── service.yaml                        <- openldap.ldap.svc:389
    │   └── changes/                            <- LDIFs used in Proof 5
    │       ├── remove-charlie-from-dev-team.ldif
    │       ├── restore-dev-team.ldif
    │       └── add-eve-to-ops-team.ldif
    ├── argocd-config/
    │   ├── argocd-server-svc-patch.yaml        <- NodePort 30443
    │   ├── argocd-secret-patch.yaml            <- dex.ldap.bindPW
    │   ├── argocd-cm-sso-patch.yaml            <- url + dex.config (LDAP connector)
    │   ├── argocd-rbac-cm-sso-patch.yaml       <- group -> role mapping
    │   ├── namespaces.yaml                     <- dev-ns
    │   └── optional-github-connector-patch.yaml<- Appendix A
    ├── projects/
    │   └── dev-project.yaml                    <- only dev-ns
    ├── apps/
    │   └── dev-app/                            <- nginx, NodePort 31003
    │       ├── kustomization.yaml
    │       ├── configmap.yaml
    │       ├── deployment.yaml
    │       └── service.yaml
    ├── applications/
    │   └── dev-app.yaml                        <- optional admin-created Application
    └── scripts/
        ├── admin-setup.sh                      <- automates steps 5-11
        └── verify-sso.ps1                      <- test matrix from Windows
```

---

## 4. Push the Files to GitHub

```bash
git clone https://github.com/Ashutoshdocs/lectureArgoCD.git
cd lectureArgoCD
# unzip so files land at  lectureArgoCD/Chapter14_userManagement/SSODexLogin/
git add Chapter14_userManagement/SSODexLogin
git commit -m "Chapter 14: Argo CD SSO with Dex + LDAP demo"
git push origin main
```

On the **control-plane VM**:

```bash
git clone https://github.com/Ashutoshdocs/lectureArgoCD.git   # or git pull
cd lectureArgoCD/Chapter14_userManagement/SSODexLogin
```

---

## 5. Install and Expose Argo CD (skip if already done)

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd get pods -w        # wait for all Running, incl. argocd-dex-server

kubectl -n argocd patch svc argocd-server --patch-file argocd-config/argocd-server-svc-patch.yaml
kubectl -n argocd get svc argocd-server     # 443:30443/TCP
```

Install the CLI on the VM and log in as admin, which you need for verification commands:

```bash
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd /usr/local/bin/argocd && rm argocd

ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
argocd login $NODE_IP:30443 --username admin --password "$ADMIN_PASSWORD" --insecure --grpc-web --name admin
```

---

## 6. Deploy the LDAP Identity Provider

```bash
kubectl apply -k ldap/
kubectl -n ldap rollout status deploy/openldap
kubectl -n ldap get pods,svc
```

Check the directory contents using the read-only service account that Dex will use:

```bash
kubectl -n ldap exec deploy/openldap -- ldapsearch -x -H ldap://localhost \
  -D "cn=readonly,dc=example,dc=org" -w 'Readonly@123' \
  -b "dc=example,dc=org" "(|(objectClass=inetOrgPerson)(objectClass=groupOfNames))" dn mail member
```

Expected output (trimmed):

```
dn: uid=charlie,ou=people,dc=example,dc=org
mail: charlie@example.org
dn: uid=diana,ou=people,dc=example,dc=org
mail: diana@example.org
dn: uid=eve,ou=people,dc=example,dc=org
mail: eve@example.org
dn: cn=dev-team,ou=groups,dc=example,dc=org
member: uid=charlie,ou=people,dc=example,dc=org
dn: cn=ops-team,ou=groups,dc=example,dc=org
member: uid=diana,ou=people,dc=example,dc=org
```

Confirm a user's password works, which is exactly what Dex does at login:

```bash
kubectl -n ldap exec deploy/openldap -- ldapwhoami -x -H ldap://localhost \
  -D "uid=charlie,ou=people,dc=example,dc=org" -w 'Charlie@123'
# dn:uid=charlie,ou=people,dc=example,dc=org
```

---

## 7. Store the LDAP Bind Password in argocd-secret

Dex needs a service account to **search** LDAP. Its password goes in `argocd-secret` and never in the ConfigMap:

```bash
kubectl -n argocd patch secret argocd-secret --patch-file argocd-config/argocd-secret-patch.yaml
```

In `dex.config`, `bindPW: $dex.ldap.bindPW` means "read key `dex.ldap.bindPW` from `argocd-secret`".

---

## 8. Configure Dex SSO in argocd-cm

Put your node IP into the patch, then apply it:

```bash
sed -i "s/NODE_IP/$NODE_IP/" argocd-config/argocd-cm-sso-patch.yaml
grep url: argocd-config/argocd-cm-sso-patch.yaml      # url: https://192.168.1.50:30443
kubectl -n argocd patch configmap argocd-cm --patch-file argocd-config/argocd-cm-sso-patch.yaml
```

The two keys that matter:

| Key | Purpose |
|---|---|
| `url` | The **external** Argo CD URL. Dex derives its issuer (`<url>/api/dex`) and callback (`<url>/api/dex/callback`) from it. **SSO does not work without it.** |
| `dex.config` | Dex connectors. Here there is one `ldap` connector. |

LDAP connector, explained:

```yaml
userSearch:                       # "who is logging in?"
  baseDN: ou=people,dc=example,dc=org
  username: uid                   # login form field  ->  (uid=<typed value>)
  emailAttr: mail                 # -> token "email"
  nameAttr: cn                    # -> token "name"
groupSearch:                      # "which groups is this user in?"
  baseDN: ou=groups,dc=example,dc=org
  userMatchers:
    - userAttr: DN                # the user's DN ...
      groupAttr: member           # ... must appear in the group's "member"
  nameAttr: cn                    # -> token "groups": ["dev-team"]
```

Argo CD automatically registers two Dex clients: `argo-cd` for the UI and `argo-cd-cli` for the CLI. The CLI client's redirect URI is `http://localhost:8085/auth/callback`, so you don't configure clients yourself.

---

## 9. Configure Group-Based RBAC

```bash
kubectl -n argocd patch configmap argocd-rbac-cm --patch-file argocd-config/argocd-rbac-cm-sso-patch.yaml
```

```csv
# role:dev  -> full control of dev-project apps except delete
p, role:dev, applications, get,      dev-project/*, allow
p, role:dev, applications, create,   dev-project/*, allow
p, role:dev, applications, update,   dev-project/*, allow
p, role:dev, applications, sync,     dev-project/*, allow
p, role:dev, applications, override, dev-project/*, allow
p, role:dev, applications, action/*, dev-project/*, allow
p, role:dev, logs,         get,      dev-project/*, allow
p, role:dev, projects,     get,      dev-project,   allow
p, role:dev, applications, delete,   dev-project/*, deny

g, dev-team, role:dev          # LDAP group -> role
g, ops-team, role:readonly     # built-in read-only role
```

| Setting | Why |
|---|---|
| `scopes: "[groups, email]"` | `g,` lines are matched against the token's `groups` **and** `email` claims |
| `policy.default: ""` | users in no mapped group (Eve) get **nothing** |
| `policy.sso.csv` key | merged with `policy.csv`, so other demos' rules are kept |

Validate the policy offline as admin. Group subjects are checked by group name:

```bash
argocd admin settings rbac can dev-team create applications 'dev-project/dev-app' --namespace argocd   # Yes
argocd admin settings rbac can dev-team delete applications 'dev-project/dev-app' --namespace argocd   # No
argocd admin settings rbac can ops-team get    applications 'dev-project/dev-app' --namespace argocd   # Yes
argocd admin settings rbac can ops-team sync   applications 'dev-project/dev-app' --namespace argocd   # No
```

---

## 10. Create the Namespace and Project

```bash
kubectl apply -f argocd-config/namespaces.yaml
kubectl apply -f projects/dev-project.yaml
```

---

## 11. Restart and Verify Dex

Dex reloads on config changes, but a restart makes the demo deterministic:

```bash
kubectl -n argocd rollout restart deploy/argocd-dex-server deploy/argocd-server
kubectl -n argocd rollout status deploy/argocd-dex-server
kubectl -n argocd logs deploy/argocd-dex-server | grep -iE "connector|listening|error"
```

You should see the LDAP connector loaded and **no** errors. Then check that Dex's discovery document is reachable through Argo CD:

```bash
curl -sk https://$NODE_IP:30443/api/dex/.well-known/openid-configuration | head -5
# "issuer": "https://192.168.1.50:30443/api/dex", ...
```

**The admin side is complete.**

---

## 12. Proof 1 – SSO in the Browser (UI)

1. On the laptop, open `https://192.168.1.50:30443` and accept the self-signed certificate.
2. The login page now shows a **LOG IN VIA COMPANY LDAP** button under the username and password form.
3. Click it. You are redirected to the **Dex** page `…/api/dex/auth/ldap…`.
4. Log in as `charlie` / `Charlie@123`. You land in Argo CD.
5. Click **User Info** in the left sidebar. It shows the SSO identity and **Groups: dev-team**.
6. Log out, then log in again as `diana` / `Diana@123`. User Info shows **Groups: ops-team**.
7. Try a wrong password. Dex shows *Invalid username and password* and Argo CD is never reached.

> Use a private or incognito window per user if the browser auto-reuses a previous session.

---

## 13. Install the Argo CD CLI on Windows

PowerShell:

```powershell
New-Item -ItemType Directory -Force -Path C:\argocd | Out-Null
$version = (Invoke-RestMethod https://api.github.com/repos/argoproj/argo-cd/releases/latest).tag_name
Invoke-WebRequest -Uri "https://github.com/argoproj/argo-cd/releases/download/$version/argocd-windows-amd64.exe" `
                  -OutFile C:\argocd\argocd.exe
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\argocd", "User")
$env:Path += ";C:\argocd"
argocd version --client

Test-NetConnection 192.168.1.50 -Port 30443      # TcpTestSucceeded : True
```

---

## 14. Proof 2 – CLI SSO as Charlie (dev-team)

### 14.1 SSO login

```powershell
argocd login 192.168.1.50:30443 --sso --insecure --grpc-web --name charlie
```

What happens:

```
Opening browser for authentication
Performing authorization_code flow login: https://192.168.1.50:30443/api/dex/auth?...
```

1. Your default browser opens the Dex page. Choose **Log in with Company LDAP**, then enter `charlie` / `Charlie@123`.
2. The browser shows *"Authentication successful! You may now close this tab."*
3. The CLI prints:

```
Authentication successful
'charlie@example.org' logged in successfully
Context 'charlie' updated
```

> No password is ever typed into the CLI, and no password exists for Charlie in Argo CD.
>
> If Windows Firewall prompts for `argocd.exe`, allow it, because the CLI must listen on `localhost:8085`. If that port is busy, add `--sso-port 8086`.

### 14.2 Check the identity

```powershell
argocd account get-user-info
```

Expected output:

```
Logged In: true
Username: charlie@example.org
Issuer: https://192.168.1.50:30443/api/dex
Groups: dev-team
```

**The groups came from LDAP via Dex. This is the core proof of SSO.**

### 14.3 Work as a developer

```powershell
argocd proj list                     # dev-project

argocd app create dev-app `
  --project dev-project `
  --repo https://github.com/Ashutoshdocs/lectureArgoCD.git `
  --revision main `
  --path Chapter14_userManagement/SSODexLogin/apps/dev-app `
  --dest-server https://kubernetes.default.svc `
  --dest-namespace dev-ns

argocd app sync dev-app
argocd app wait dev-app --health --timeout 120
```

Open **http://192.168.1.50:31003**, which shows *"dev-app deployed by an SSO user"*.

```powershell
argocd app set dev-app --kustomize-replica dev-web=3   # ✅ change
argocd app sync dev-app                                 # ✅ sync
argocd app history dev-app
argocd app rollback dev-app 0                           # ✅ rollback
argocd app actions run dev-app restart --kind Deployment --resource-name dev-web   # ✅
argocd app logs dev-app --kind Deployment --name dev-web --tail 10                  # ✅

argocd app delete dev-app --yes
# ❌ PermissionDenied ... applications, delete, dev-project/dev-app, sub: ..., iat: ...
```

---

## 15. Proof 3 – CLI SSO as Diana (ops-team)

```powershell
argocd login 192.168.1.50:30443 --sso --insecure --grpc-web --name diana
# browser -> diana / Diana@123

argocd account get-user-info          # Groups: ops-team
argocd app list                       # ✅ sees dev-app (read-only role sees all apps)
argocd app get dev-app                # ✅
argocd app sync dev-app               # ❌ permission denied
argocd app set dev-app --kustomize-replica dev-web=1   # ❌ permission denied
argocd app delete dev-app --yes       # ❌ permission denied
```

Same app, different SSO user, different LDAP group, and therefore different permissions.

---

## 16. Proof 4 – CLI SSO as Eve (no group)

```powershell
argocd login 192.168.1.50:30443 --sso --insecure --grpc-web --name eve
# browser -> eve / Eve@123

argocd account get-user-info          # Logged In: true, Groups: (empty)
argocd app list                       # empty
argocd app get dev-app                # ❌ permission denied
```

**Authentication ≠ authorization.** Eve is a valid company user, so SSO succeeds. She belongs to no mapped group, so `policy.default: ""` gives her nothing.

You now have three contexts:

```powershell
argocd context
#   CURRENT  NAME     SERVER
#            charlie  192.168.1.50:30443
#            diana    192.168.1.50:30443
#   *        eve      192.168.1.50:30443
```

---

## 17. Proof 5 – Central Access Control via LDAP

Change **only LDAP**. No Argo CD config is touched.

### 17.1 Grant Eve access by adding her to ops-team

On the VM:

```bash
kubectl -n ldap exec -i deploy/openldap -- ldapmodify -x -H ldap://localhost \
  -D "cn=admin,dc=example,dc=org" -w 'Admin@123' < ldap/changes/add-eve-to-ops-team.ldif
```

On the laptop:

```powershell
argocd context eve
argocd relogin                        # browser SSO again -> fresh token
argocd account get-user-info          # Groups: ops-team
argocd app list                       # ✅ now sees dev-app (read-only)
```

### 17.2 Revoke Charlie by removing him from dev-team

```bash
kubectl -n ldap exec -i deploy/openldap -- ldapmodify -x -H ldap://localhost \
  -D "cn=admin,dc=example,dc=org" -w 'Admin@123' < ldap/changes/remove-charlie-from-dev-team.ldif
```

```powershell
argocd context charlie
argocd relogin
argocd account get-user-info          # Groups: (empty)
argocd app list                       # empty - access gone
argocd app sync dev-app               # ❌ permission denied
```

> Group changes apply at the **next login**, because groups are baked into the token. A token issued before the change stays valid until it expires. Argo CD's default session duration is 24h, set by `users.session.duration` in `argocd-cm`.

Restore Charlie:

```bash
kubectl -n ldap exec -i deploy/openldap -- ldapmodify -x -H ldap://localhost \
  -D "cn=admin,dc=example,dc=org" -w 'Admin@123' < ldap/changes/restore-dev-team.ldif
```

> The LDAP data lives in `emptyDir`. Running `kubectl -n ldap rollout restart deploy/openldap` resets the directory to the original seed data.

---

## 18. Proof 6 – Server-Side Evidence (logs & token)

**Dex login log.** Every successful SSO login is recorded with the connector and groups:

```bash
kubectl -n argocd logs deploy/argocd-dex-server | grep -i "login successful"
# ... login successful: connector "ldap", username="Charlie Developer",
#     preferred_username="charlie", email="charlie@example.org", groups=["dev-team"]
```

**Failed login:**

```bash
kubectl -n argocd logs deploy/argocd-dex-server | grep -iE "invalid|failed"
```

**RBAC denials in argocd-server:**

```bash
kubectl -n argocd logs deploy/argocd-server | grep -i "permission denied"
```

**Decode the token on Windows** to see the claims Argo CD uses:

```powershell
$cfg   = Get-Content "$env:USERPROFILE\.config\argocd\config" -Raw
$token = ([regex]'auth-token:\s*(\S+)').Matches($cfg) | Select-Object -Last 1 | ForEach-Object { $_.Groups[1].Value }
# The config holds one token per user; pick the one you want. Then decode its payload:
$p = $token.Split('.')[1].Replace('-','+').Replace('_','/'); while ($p.Length % 4) { $p += '=' }
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p))
# {"iss":"https://192.168.1.50:30443/api/dex", "email":"...", "groups":["dev-team"], ...}
```

**No local accounts were created.** Run this as admin on the VM:

```bash
argocd context admin
argocd account list     # charlie / diana / eve do NOT appear - they live only in LDAP
```

---

## 19. Permission Test Matrix

After logging in once as each user (steps 14–16), run:

```powershell
.\scripts\verify-sso.ps1
```

| Check | charlie (dev-team) | diana (ops-team) | eve (none) |
|---|---|---|---|
| SSO login via Dex | ✅ | ✅ | ✅ |
| `get-user-info` groups | `dev-team` | `ops-team` | *(empty)* |
| `app list` | dev-app | dev-app | *(empty)* |
| `app create` in dev-project | ✅ | ❌ | ❌ |
| `app sync` / `app set` / `rollback` | ✅ | ❌ | ❌ |
| `app logs` | ✅ | ✅ | ❌ |
| `app delete` | ❌ | ❌ | ❌ |
| After LDAP change + relogin | loses access | – | gains read-only |

---

## 20. Optional Hardening

Once SSO is proven, you can lock things down:

```bash
# Disable the built-in admin user (keep a break-glass procedure!)
kubectl -n argocd patch configmap argocd-cm -p '{"data":{"admin.enabled":"false"}}'

# Give an LDAP group full admin instead
kubectl -n argocd patch configmap argocd-rbac-cm --type merge \
  -p '{"data":{"policy.admins.csv":"g, ops-team, role:admin\n"}}'

# Shorter sessions, so group changes take effect sooner
kubectl -n argocd patch configmap argocd-cm -p '{"data":{"users.session.duration":"1h"}}'
```

In production, also use **LDAPS** (`host: ldap.company.com:636`, remove `insecureNoSSL`, and set `rootCA`) and a real TLS certificate for Argo CD.

---

## 21. Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| No **LOG IN VIA …** button | `url` or `dex.config` is missing or invalid. Check `kubectl -n argocd get cm argocd-cm -o yaml` and the Dex logs. |
| Browser: `Invalid redirect_uri` / `unregistered redirect_uri` | `url` doesn't match how you open Argo CD. It must be exactly `https://<NODE-IP>:30443`. Restart Dex and argocd-server. |
| Dex log: `ldap: failed to connect` | The openldap pod isn't ready, or there's a DNS issue. Run `kubectl -n ldap get pods` and test from the dex pod. |
| Dex log: `ldap: initial bind ... Invalid Credentials` | `dex.ldap.bindPW` in `argocd-secret` ≠ `LDAP_READONLY_USER_PASSWORD`. |
| Login OK but `Groups:` empty for charlie | `groupSearch` is misconfigured, or the user isn't in `member`. Re-run the `ldapsearch` in step 6. |
| Login OK but everything `permission denied` | Group name mismatch: RBAC `g, dev-team, …` must equal the LDAP `cn`. Check that `scopes` includes `groups`. |
| CLI: browser doesn't open | Copy the printed `https://…/api/dex/auth?...` URL into a browser manually. |
| CLI hangs after browser login | Windows Firewall blocked `argocd.exe` on localhost:8085. Allow it, or use `--sso-port 8086`. |
| `x509: certificate signed by unknown authority` (CLI) | Add `--insecure`. |
| openldap pod stuck / high memory | Make sure the `ulimit -n 1024` wrapper in `ldap/deployment.yaml` is present (containerd nofile issue). |
| LDAP changes "lost" | The pod restarted, because emptyDir re-seeds the data. Re-apply the LDIF. |
| Group change not reflected | Run `argocd relogin`. The old token keeps the old groups until it expires. |

Useful commands:

```bash
kubectl -n argocd logs deploy/argocd-dex-server -f
kubectl -n argocd logs deploy/argocd-server -f | grep -iE "sso|oidc|permission"
argocd admin settings rbac validate --namespace argocd
```

---

## 22. Cleanup

```bash
argocd context admin
argocd app delete dev-app --yes          # only admin can delete
kubectl delete -f projects/dev-project.yaml
kubectl delete -f argocd-config/namespaces.yaml
kubectl delete -k ldap/

# Remove SSO config
kubectl -n argocd patch configmap argocd-cm --type json \
  -p '[{"op":"remove","path":"/data/dex.config"}]'
kubectl -n argocd patch configmap argocd-rbac-cm --type json \
  -p '[{"op":"remove","path":"/data/policy.sso.csv"}]'
kubectl -n argocd patch secret argocd-secret --type json \
  -p '[{"op":"remove","path":"/data/dex.ldap.bindPW"}]'
kubectl -n argocd rollout restart deploy/argocd-dex-server deploy/argocd-server
```

Windows:

```powershell
foreach ($c in "charlie","diana","eve") { argocd logout $c; argocd context --delete $c }
```

---

## Appendix A – Add GitHub Login (optional)

Dex supports multiple connectors at once. To offer **"Log in with GitHub"** next to LDAP:

1. **Create a GitHub OAuth App.** Go to GitHub → *Settings* → *Developer settings* → *OAuth Apps* → *New OAuth App*:
   - Homepage URL: `https://192.168.1.50:30443`
   - Authorization callback URL: `https://192.168.1.50:30443/api/dex/callback`

   A private IP works, because the redirect happens in **your** browser.
2. **Store the client secret:**
   ```bash
   kubectl -n argocd patch secret argocd-secret -p '{"stringData":{"dex.github.clientSecret":"<CLIENT_SECRET>"}}'
   ```
3. **Edit and apply** `argocd-config/optional-github-connector-patch.yaml`. Set `NODE_IP`, `<GITHUB_CLIENT_ID>` and `<YOUR_GITHUB_ORG>`, then:
   ```bash
   kubectl -n argocd patch configmap argocd-cm --patch-file argocd-config/optional-github-connector-patch.yaml
   kubectl -n argocd rollout restart deploy/argocd-dex-server
   ```
4. **Map GitHub teams to roles.** Groups arrive as `<org>:<team-slug>`:
   ```bash
   kubectl -n argocd patch configmap argocd-rbac-cm --type merge \
     -p '{"data":{"policy.github.csv":"g, <YOUR_GITHUB_ORG>:dev-team, role:dev\n"}}'
   ```
5. **Log in.** Run `argocd login 192.168.1.50:30443 --sso --insecure --grpc-web --name gh-user`. The Dex page now lists **both** *Company LDAP* and *GitHub*.
