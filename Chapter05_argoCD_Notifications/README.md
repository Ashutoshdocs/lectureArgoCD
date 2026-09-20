# ArgoCD Notifications — Slack & Email Demo (detailed)

Set up **ArgoCD Notifications** so that Application events — *sync succeeded*,
*sync failed*, *health degraded* — are pushed to **Slack** and **email**.

- **Repo:** `https://github.com/Ashutoshdocs/lectureArgoCD.git`
- **Path in repo:** `Chapter05_argoCD_Notifications/manifests`

---

## 🔔 How it works

```
   Application state changes (Synced / Failed / Degraded)
                     │
                     ▼
        argocd-notifications-controller   (runs in the argocd namespace)
                     │  evaluates TRIGGERS (when: …)
                     │  renders TEMPLATES (the message)
                     ▼
     ┌───────────────┴───────────────┐
     ▼                               ▼
  Slack service                 Email (SMTP) service
  (token from secret)           (user/pass from secret)
     │                               │
     ▼                               ▼
  #argocd-demo channel          team@example.com
```

Three pieces of configuration:
1. **Services** — *how* to reach Slack / SMTP (in `argocd-notifications-cm`, secrets in `argocd-notifications-secret`).
2. **Triggers + Templates** — *when* to notify and *what* the message says (in the ConfigMap).
3. **Subscriptions** — *which* app notifies *which* channel (annotations on the Application).

---

## 📁 Files

```
Chapter05_argoCD_Notifications/
├── README.md
├── application.yaml                              # sample app + subscription annotations
├── notifications/
│   ├── argocd-notifications-cm.yaml              # services, triggers, templates
│   └── argocd-notifications-secret.example.yaml  # token template (DON'T commit real one)
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
- A **Slack workspace** where you can create an app (for the Slack channel).
- An **SMTP account** (e.g. Gmail with an *App Password*) for email.

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

## 2. Create a Slack app & get a bot token

1. Go to **https://api.slack.com/apps → Create New App → From scratch**.
2. **OAuth & Permissions → Scopes → Bot Token Scopes**: add **`chat:write`**
   (add `chat:write.public` if you want to post without inviting the bot).
3. Click **Install to Workspace**, then copy the **Bot User OAuth Token**
   (starts with `xoxb-…`).
4. In Slack, create/choose a channel (e.g. **`#argocd-demo`**) and **invite the bot**:
   `/invite @your-app-name`.

## 3. Get SMTP credentials (Gmail example)

1. Enable 2-Step Verification on the Google account.
2. Create an **App Password**: Google Account → Security → App passwords.
3. Use that 16-char password (not your login password) for `email-password`,
   with host `smtp.gmail.com`, port `587`.

> Any SMTP provider works (SendGrid, SES, Outlook…). Adjust `host`/`port` in
> `argocd-notifications-cm.yaml` accordingly.

---

## 4. Apply the notifications config + secret

Apply the ConfigMap (services, triggers, templates):

```bash
kubectl apply -f Chapter05_argoCD_Notifications/notifications/argocd-notifications-cm.yaml
```

Create the secret **imperatively** so tokens never go into Git (recommended):

```bash
kubectl -n argocd create secret generic argocd-notifications-secret \
  --from-literal=slack-token='xoxb-your-token' \
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

## 5. Push this demo and create the Application

```bash
git clone https://github.com/Ashutoshdocs/lectureArgoCD.git
cd lectureArgoCD
# copy the Chapter05_argoCD_Notifications folder in, then:
git add Chapter05_argoCD_Notifications
git commit -m "Chapter05: ArgoCD notifications demo"
git push origin main

kubectl apply -f Chapter05_argoCD_Notifications/application.yaml
```

The Application's annotations subscribe it:
- `on-sync-succeeded`, `on-sync-failed`, `on-health-degraded` → **Slack** `#argocd-demo`
- `on-sync-failed`, `on-health-degraded` → **email** `team@example.com`

Edit those annotation values to your real channel and address.

---

## 6. Test the notifications ⭐

**A. Natural trigger — first sync.**
When the app first syncs to Healthy you get a ✅ *sync-succeeded* Slack message.

**B. Force a test with the notifications CLI** (no state change needed):

```bash
kubectl -n argocd exec deploy/argocd-notifications-controller -- \
  /app/argocd-notifications template notify app-sync-succeeded web \
  --recipient slack:argocd-demo
```

**C. Trigger a FAILURE on purpose.**
Point the app at a bad path so sync fails:

```bash
kubectl -n argocd patch application web --type merge \
  -p '{"spec":{"source":{"path":"Chapter05_argoCD_Notifications/does-not-exist"}}}'
```
→ expect a ❌ *sync-failed* message in Slack **and** email. Revert:
```bash
kubectl -n argocd patch application web --type merge \
  -p '{"spec":{"source":{"path":"Chapter05_argoCD_Notifications/manifests"}}}'
```

**D. Trigger DEGRADED health.**
Break the image so pods never become healthy:

```bash
kubectl -n notify-demo set image deploy/web nginx=nginx:doesnotexist
```
→ expect a ⚠️ *health-degraded* message. Fix:
```bash
kubectl -n notify-demo set image deploy/web nginx=nginx:1.27-alpine
```

---

## Configuration reference

**Service** (in `argocd-notifications-cm`)
| Key | Meaning |
|-----|---------|
| `service.slack` | Slack service; `token: $slack-token` reads the secret |
| `service.email.gmail` | Named `email` service `gmail`; SMTP host/port/from |

**Trigger** — `when:` is an expr condition; `send:` names templates; `oncePer:` dedupes.

**Template** — has `message`, plus channel-specific blocks (`slack.attachments`, `email.subject`). Fields come from the live Application object (`.app.status.…`).

**Subscription annotation** format:
```
notifications.argoproj.io/subscribe.<trigger>.<service>: <recipient>
```
e.g. `notifications.argoproj.io/subscribe.on-sync-failed.slack: argocd-demo`.

---

## 🧰 Troubleshooting

- **No Slack message** — bot not invited to the channel, or missing `chat:write`
  scope, or wrong channel name. Check controller logs:
  `kubectl -n argocd logs deploy/argocd-notifications-controller -f`.
- **No email** — wrong SMTP host/port, using login password instead of an App
  Password, or provider blocking SMTP. Logs show the SMTP error.
- **Nothing fires at all** — confirm `argocd-notifications-cm` and
  `argocd-notifications-secret` exist in the **argocd** namespace and the
  controller pod is Running; restart it after edits.
- **`$slack-token` shows literally** — the key name in the secret must match the
  variable after `$` in the ConfigMap.
- **Duplicate messages** — add/adjust `oncePer:` in the trigger.

## 🧹 Cleanup

```bash
kubectl delete -f Chapter05_argoCD_Notifications/application.yaml
kubectl delete namespace notify-demo
kubectl -n argocd delete cm argocd-notifications-cm
kubectl -n argocd delete secret argocd-notifications-secret
```

---

### One-line recap for students
> Configure a **service** (Slack/SMTP + secret), define **triggers + templates**
> (when + what), then **subscribe** an app with annotations. The controller does
> the rest.
