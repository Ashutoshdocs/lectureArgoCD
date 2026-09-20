# ArgoCD Notifications — Email-Only Demo (detailed)

Set up **ArgoCD Notifications** so Application events — *sync succeeded*,
*sync failed*, *health degraded* — are emailed via **SMTP**. **No Slack required.**

- **Repo:** `https://github.com/Ashutoshdocs/lectureArgoCD.git`
- **Path in repo:** `Chapter05_argoCD_Notifications_Email/manifests`

---

## 📧 How it works

```
   Application state changes (Synced / Failed / Degraded)
                     │
                     ▼
        argocd-notifications-controller   (runs in the argocd namespace)
                     │  evaluates TRIGGERS (when: …)
                     │  renders TEMPLATES (subject + body)
                     ▼
              Email (SMTP) service
              (username/password from secret)
                     │
                     ▼
              team@example.com
```

Three pieces of configuration:
1. **Service** — *how* to reach SMTP (in `argocd-notifications-cm`, creds in `argocd-notifications-secret`).
2. **Triggers + Templates** — *when* to notify and *what* the email says (in the ConfigMap).
3. **Subscriptions** — *which* app emails *which* address (annotations on the Application).

---

## 📁 Files

```
Chapter05_argoCD_Notifications_Email/
├── README.md
├── application.yaml                              # sample app + email subscriptions
├── notifications/
│   ├── argocd-notifications-cm.yaml              # email service, triggers, templates
│   └── argocd-notifications-secret.example.yaml  # SMTP creds template (DON'T commit real one)
└── manifests/                                    # a small nginx app to watch
    ├── namespace.yaml
    ├── configmap.yaml
    ├── deployment.yaml
    └── service.yaml
```

---

## ✅ Prerequisites

- Kubernetes cluster + `kubectl`.
- **ArgoCD installed** (the notifications controller ships with it).
- An **SMTP account**. Gmail is used below (needs an *App Password*); any provider
  works (SendGrid, Amazon SES, Outlook/Office365, your company relay).

---

## 1. Install ArgoCD (includes the notifications controller)

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Confirm the notifications controller is present:
kubectl -n argocd get deploy argocd-notifications-controller
```

> Older ArgoCD? Install it separately:
> `kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-notifications/stable/manifests/install.yaml`

---

## 2. Get SMTP credentials

**Gmail (used in this demo):**
1. Enable **2-Step Verification** on the Google account.
2. Create an **App Password**: Google Account → Security → App passwords.
3. Use that 16-character password for `email-password`, host `smtp.gmail.com`, port `587`.

**Other providers** — edit `host`/`port` in `argocd-notifications-cm.yaml`:
| Provider | host | port |
|----------|------|------|
| Gmail | smtp.gmail.com | 587 |
| Outlook/Office365 | smtp.office365.com | 587 |
| Amazon SES | email-smtp.<region>.amazonaws.com | 587 |
| SendGrid | smtp.sendgrid.net | 587 (username is literally `apikey`) |

---

## 3. Apply the notifications config + secret

Apply the ConfigMap (email service, triggers, templates):

```bash
kubectl apply -f Chapter05_argoCD_Notifications_Email/notifications/argocd-notifications-cm.yaml
```

Create the secret **imperatively** so credentials never go into Git (recommended):

```bash
kubectl -n argocd create secret generic argocd-notifications-secret \
  --from-literal=email-username='you@gmail.com' \
  --from-literal=email-password='your-app-password' \
  --dry-run=client -o yaml | kubectl apply -f -
```

> Prefer a file? Copy `argocd-notifications-secret.example.yaml` to
> `argocd-notifications-secret.yaml`, fill it in, and apply it — it's already in
> `.gitignore` so it won't be committed.

Restart the controller to pick up changes immediately (optional):

```bash
kubectl -n argocd rollout restart deploy/argocd-notifications-controller
```

---

## 4. Push this demo and create the Application

```bash
git clone https://github.com/Ashutoshdocs/lectureArgoCD.git
cd lectureArgoCD
# copy the Chapter05_argoCD_Notifications_Email folder in, then:
git add Chapter05_argoCD_Notifications_Email
git commit -m "Chapter05: ArgoCD email notifications demo"
git push origin main

kubectl apply -f Chapter05_argoCD_Notifications_Email/application.yaml
```

Edit the recipient in `application.yaml` (`team@example.com`) to your address.
The annotations subscribe the app's sync-succeeded, sync-failed and
health-degraded events to email.

---

## 5. Test the emails ⭐

**A. Natural trigger — first sync.**
When the app first syncs to Healthy you get a ✅ *sync-succeeded* email.

**B. Force a test with the notifications CLI** (no state change needed):

```bash
kubectl -n argocd exec deploy/argocd-notifications-controller -- \
  /app/argocd-notifications template notify app-sync-succeeded web \
  --recipient gmail:team@example.com
```

**C. Trigger a FAILURE on purpose** (bad path → sync fails):

```bash
kubectl -n argocd patch application web --type merge \
  -p '{"spec":{"source":{"path":"Chapter05_argoCD_Notifications_Email/does-not-exist"}}}'
```
→ expect a ❌ *sync-failed* email. Revert:
```bash
kubectl -n argocd patch application web --type merge \
  -p '{"spec":{"source":{"path":"Chapter05_argoCD_Notifications_Email/manifests"}}}'
```

**D. Trigger DEGRADED health** (bad image → pods never healthy):

```bash
kubectl -n notify-demo set image deploy/web nginx=nginx:doesnotexist
```
→ expect a ⚠️ *health-degraded* email. Fix:
```bash
kubectl -n notify-demo set image deploy/web nginx=nginx:1.27-alpine
```

---

## Configuration reference

**Service** (in `argocd-notifications-cm`)
| Key | Meaning |
|-----|---------|
| `service.email.gmail` | Email service **named** `gmail`; the name after the last dot is what subscriptions reference |
| `username/password` | `$email-username` / `$email-password` read from the secret |
| `host/port/from` | SMTP server + the From address |

**Trigger** — `when:` is an expr condition; `send:` names templates; `oncePer:` dedupes.

**Template** — `email.subject` + `message` body. Fields come from the live
Application object (`.app.status.…`).

**Subscription annotation** format:
```
notifications.argoproj.io/subscribe.<trigger>.<service>: <recipient>
```
e.g. `notifications.argoproj.io/subscribe.on-sync-failed.gmail: team@example.com`.

---

## 🧰 Troubleshooting

- **No email arrives** — check the controller logs:
  `kubectl -n argocd logs deploy/argocd-notifications-controller -f`.
- **SMTP auth error** — using the login password instead of an **App Password**
  (Gmail), or the account blocks SMTP. Re-check host/port.
- **Nothing fires at all** — confirm `argocd-notifications-cm` and
  `argocd-notifications-secret` exist in the **argocd** namespace and the
  controller pod is Running; restart it after edits.
- **`$email-username` shows literally** — the key name in the secret must match
  the variable after `$` in the ConfigMap.
- **Duplicate emails** — add/adjust `oncePer:` in the trigger.
- **Service name mismatch** — the service is named `gmail`
  (`service.email.gmail`), so subscriptions must say `.gmail:`. Rename both sides
  together if you change it.

## 🧹 Cleanup

```bash
kubectl delete -f Chapter05_argoCD_Notifications_Email/application.yaml
kubectl delete namespace notify-demo
kubectl -n argocd delete cm argocd-notifications-cm
kubectl -n argocd delete secret argocd-notifications-secret
```

---

### One-line recap for students
> Configure the **email service** (SMTP + secret), define **triggers + templates**
> (when + what), then **subscribe** an app with `.gmail:` annotations. The
> controller sends the mail.
