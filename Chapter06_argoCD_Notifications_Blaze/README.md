# Chapter 6: ArgoCD Notifications (Email) — Blaze App 🔥

ArgoCD Notifications automatically send alerts about application events (sync,
health, errors) to external channels like **Email, Slack, Microsoft Teams,
Webhooks, etc.** This makes GitOps workflows observable and actionable.

This chapter wires **email** notifications to the **blaze-app** and demonstrates
two events: **app successfully deployed** and **app health degraded**.

- **Repo:** `https://github.com/Ashutoshdocs/lectureArgoCD.git`
- **App manifests path:** `Chapter06_argoCD_Notifications_Blaze/applicationsets/blaze-app`

---

## 1. Introduction & Overview

* ArgoCD Notifications is a **built-in component** of ArgoCD since v1.7+.
* It consists of:
  * **Notification Controller** — watches ArgoCD Applications and triggers notifications.
  * **Triggers** — define *when* to send (e.g., on health degraded).
  * **Templates** — define *what* to send (message content).
  * **Subscriptions** — define *where* to send (Email, Slack, etc.).
* Common use cases:
  * Send an **email when an Application health is degraded**.
  * Send an **email when an Application is deployed** (synced + healthy).

**The 3 building blocks in this chapter**

| Piece | File | Role |
|-------|------|------|
| Secret | `secret-smtp.yaml` | SMTP username/password (sensitive) |
| ConfigMap | `argocd-notifications-cm.yaml` | Service, templates, triggers (logic) |
| Application annotations | `blaze-app.yaml` | Subscriptions (who gets which event) |

---

## 2. Prerequisites

* A Kubernetes cluster (Kind/minikube/AKS…) running.
* **ArgoCD** installed & reachable in the browser.
* **ArgoCD CLI** installed and logged in.
* Access to an **SMTP server** for sending email.
  * This chapter uses **Gmail** → create an **App Password**:
    1. Turn **2-Step Verification ON** for the Google account.
    2. Go to **Google Account → Security → App passwords**
       (https://myaccount.google.com/apppasswords).
    3. Name it **ArgoCD SMTP** → **Create** → copy the **16-char password**
       (`xxxx xxxx xxxx xxxx`). Copy it now; you won't see it again.

> **Don't want a real mailbox / worried about cost?** See
> *"Using a different SMTP server"* and *"Zero-cost local SMTP (MailHog)"* below.

---

## 3. Setup: Integrating with Email

### Step 0 (optional): Install the notifications catalog

Our ConfigMap defines its own triggers/templates, so this is optional. It's handy
if you later want the community catalog of ready-made triggers:

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/notifications_catalog/install.yaml
```

### Step 1: Configure the SMTP Secret

Edit `secret-smtp.yaml`:
> Replace `your-email@example.com` with your sender Gmail (the one that owns the App Password).
> Replace `your-smtp-password` with the App Password **exactly** (keep the spaces).

Apply it:

```bash
kubectl apply -f Chapter06_argoCD_Notifications_Blaze/secret-smtp.yaml
```

### Step 2: Configure the Notification ConfigMap

Edit `argocd-notifications-cm.yaml`:
> Replace `<your-argocd-server>` with your ArgoCD server URL / public IP (used to
> build the "Details" link inside the email).

Apply it:

```bash
kubectl apply -f Chapter06_argoCD_Notifications_Blaze/argocd-notifications-cm.yaml
# pick up changes immediately (optional)
kubectl -n argocd rollout restart deploy/argocd-notifications-controller
```

### Secret ↔ ConfigMap integration (why `$variables`)

* **Secret** stores sensitive values (`email-username`, `email-password`).
* **ConfigMap** references them as `$email-username` / `$email-password`.
* The controller substitutes them at runtime.

**Flow:** Secret → holds creds → ConfigMap references `$vars` → controller resolves
them when sending. Without the `$variable` references you'd hardcode credentials in
Git (not recommended).

### Step 3: Deploy the blaze-app with subscriptions

Edit `blaze-app.yaml`:
> Replace `<receiver@example.com>` with the recipient address.
> (`repoURL`/`path` are already set to this repo & chapter.)

Push this chapter to your repo, then apply the Application:

```bash
git add Chapter06_argoCD_Notifications_Blaze && git commit -m "Chapter06: blaze-app notifications" && git push origin main
kubectl apply -f Chapter06_argoCD_Notifications_Blaze/blaze-app.yaml
```

Watch it sync, then open the app:

```bash
kubectl -n argocd get applications
kubectl get all -n default -l app=blaze-app

kubectl port-forward svc/blaze-app-service -n default 3000:3000 --address=0.0.0.0 &
# open http://<instance_public_ip>:3000  (or http://localhost:3000)
```

You should see the 🔥 **Blaze App** page.

---

## 4. Demo: Email on Deployed & Degraded

**1. Deployed (success).**
When blaze-app finishes sync and becomes **Healthy**, the `on-deployed` trigger
fires → you get an email:
```
[ArgoCD] blaze-app successfully deployed 🎉
```

**2. Introduce a failure.**
Edit the Deployment image in Git to a non-existent tag (e.g. `nginx:v1`):

```bash
# in Chapter06_argoCD_Notifications_Blaze/applicationsets/blaze-app/deployment.yaml
#   image: nginx:1.27-alpine   ->   image: nginx:v1
git commit -am "break blaze-app image (demo)" && git push origin main
```

ArgoCD syncs the bad image → pods hit `ImagePullBackOff` → after a bit the app
goes **Degraded**. Watch the controller decide to send:

```bash
kubectl -n argocd logs deploy/argocd-notifications-controller --follow
```

**3. Observe the email.**
When health becomes **Degraded**, the `on-health-degraded` trigger fires →
recipient gets:
```
[ArgoCD] blaze-app health is Degraded
```
The body includes namespace, sync status, revision, health message and a details link.

**Revert** to fix:
```bash
git commit -am "restore blaze-app image" && git push origin main
```

---

## Using a different SMTP server (not Gmail)

**Gmail *is* an SMTP server** — "SMTP instead of Gmail" just means pointing at a
different host. Only `host`/`port`/creds change in `argocd-notifications-cm.yaml`:

| Provider | host | port | Free tier? |
|----------|------|------|-----------|
| Gmail | smtp.gmail.com | 465 (SSL) / 587 (TLS) | Free, ~500/day |
| Outlook / Office365 | smtp.office365.com | 587 | Free with account |
| Amazon SES | email-smtp.<region>.amazonaws.com | 587 | ~$0.10 / 1,000 emails |
| SendGrid | smtp.sendgrid.net | 587 | Free ~100/day (user is `apikey`) |
| Brevo / Mailgun | (provider host) | 587 | Free tier, then paid |

**Will it cost me?** For this demo — **no.** Gmail App Password and the free tiers
above cover it. You only pay at production volume (e.g. SES).

## Zero-cost local SMTP (MailHog) — best for teaching

Run a fake SMTP server **inside the cluster**: no account, no internet, nothing
leaves the cluster, and you read the "sent" mail in a web UI.

```bash
kubectl -n default create deployment mailhog --image=mailhog/mailhog
kubectl -n default expose deployment mailhog --port=1025 --name=mailhog-smtp
kubectl -n default expose deployment mailhog --port=8025 --name=mailhog-web
kubectl -n default port-forward svc/mailhog-web 8025:8025   # open http://localhost:8025
```

Then point the ConfigMap service at it (no username/password needed):

```yaml
service.email: |
  host: mailhog-smtp.default.svc.cluster.local
  port: 1025
  from: argocd@example.com
```

Every notification lands in the MailHog inbox at http://localhost:8025.

---

## 5. Key Takeaways

* ArgoCD Notifications integrates with Email via 3 pieces: **Secret** (creds),
  **ConfigMap** (service + triggers + templates), **Application annotations** (subscriptions).
* This demo emails on **deployed** and **degraded** for blaze-app.

## Common ArgoCD Notification Triggers

| Trigger | Condition | When to use |
|---------|-----------|-------------|
| `on-sync-status-unknown` | sync status `Unknown` | debugging odd states |
| `on-sync-running` | sync started | notify on large deploys |
| `on-sync-succeeded` | sync `Synced` | audit trails |
| `on-sync-failed` | sync failed | **most common** — alert on failed deploy |
| `on-health-degraded` | health `Degraded` | CrashLoop / ImagePull issues |
| `on-deployed` | synced **and** healthy | "deployment done, all healthy" |
| `on-created` / `on-deleted` | app created / deleted | onboarding / removal audit |

## 🧹 Cleanup

```bash
kubectl delete -f Chapter06_argoCD_Notifications_Blaze/blaze-app.yaml
kubectl -n argocd delete cm argocd-notifications-cm
kubectl -n argocd delete secret argocd-notifications-secret
# if you used MailHog:
kubectl -n default delete deploy/mailhog svc/mailhog-smtp svc/mailhog-web
```

---

Docs: https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/

Happy Learning!
