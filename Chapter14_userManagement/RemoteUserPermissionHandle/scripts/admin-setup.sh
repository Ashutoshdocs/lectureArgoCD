#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Admin one-shot setup for the Chapter 14 demo.
# Run on the kubeadm control-plane VM from inside Chapter14_userManagement/RemoteUserPermissionHandle/:
#
#   chmod +x scripts/admin-setup.sh
#   ./scripts/admin-setup.sh
#
# It performs README steps 4-10. Each step is safe to re-run.
# -----------------------------------------------------------------------------
set -euo pipefail

ALICE_PASSWORD="${ALICE_PASSWORD:-Alice@12345}"
BOB_PASSWORD="${BOB_PASSWORD:-Bob@12345}"
NODE_IP="${NODE_IP:-$(hostname -I | awk '{print $1}')}"

echo ">>> [1/8] Installing Argo CD (stable) into namespace 'argocd'"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo ">>> [2/8] Waiting for Argo CD pods to be ready"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

echo ">>> [3/8] Exposing argocd-server on NodePort 30443 (https) / 30080 (http)"
kubectl -n argocd patch svc argocd-server --patch-file argocd-config/argocd-server-svc-patch.yaml

echo ">>> [4/8] Creating namespaces alice-ns and bob-ns"
kubectl apply -f argocd-config/namespaces.yaml

echo ">>> [5/8] Creating local users alice and bob (argocd-cm)"
kubectl -n argocd patch configmap argocd-cm --patch-file argocd-config/argocd-cm-patch.yaml

echo ">>> [6/8] Creating AppProjects"
kubectl apply -f projects/alice-project.yaml
kubectl apply -f projects/bob-project.yaml

echo ">>> [7/8] Applying RBAC (argocd-rbac-cm)"
kubectl -n argocd patch configmap argocd-rbac-cm --patch-file argocd-config/argocd-rbac-cm-patch.yaml

echo ">>> [8/8] Setting passwords for alice and bob"
if ! command -v argocd >/dev/null 2>&1; then
  echo "    argocd CLI not found - installing to /usr/local/bin"
  curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  sudo install -m 555 /tmp/argocd /usr/local/bin/argocd && rm -f /tmp/argocd
fi

ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)

# give argocd-server a moment to pick up the new accounts
sleep 5
argocd login "${NODE_IP}:30443" --username admin --password "${ADMIN_PASSWORD}" \
  --insecure --grpc-web --name admin

argocd account update-password --account alice \
  --current-password "${ADMIN_PASSWORD}" --new-password "${ALICE_PASSWORD}"
argocd account update-password --account bob \
  --current-password "${ADMIN_PASSWORD}" --new-password "${BOB_PASSWORD}"

echo
echo "================================================================"
echo " Setup complete"
echo "   Argo CD URL     : https://${NODE_IP}:30443"
echo "   admin password  : ${ADMIN_PASSWORD}"
echo "   alice / ${ALICE_PASSWORD}"
echo "   bob   / ${BOB_PASSWORD}"
echo "================================================================"
argocd account list
