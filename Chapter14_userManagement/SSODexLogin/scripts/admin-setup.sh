#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Admin one-shot setup for the SSO (Dex + LDAP) demo.
# Run on the kubeadm control-plane VM from inside
#   Chapter14_userManagement/SSODexLogin/
#
#   chmod +x scripts/admin-setup.sh
#   NODE_IP=192.168.1.50 ./scripts/admin-setup.sh
#
# Performs README steps 5-12. Safe to re-run.
# -----------------------------------------------------------------------------
set -euo pipefail

NODE_IP="${NODE_IP:-$(hostname -I | awk '{print $1}')}"
echo ">>> Using NODE_IP=${NODE_IP}  (Argo CD URL https://${NODE_IP}:30443)"

echo ">>> [1/9] Ensuring Argo CD is installed"
if ! kubectl get ns argocd >/dev/null 2>&1; then
  kubectl create namespace argocd
  kubectl apply -n argocd --server-side --force-conflicts \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
fi
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-dex-server --timeout=300s

echo ">>> [2/9] Exposing argocd-server on NodePort 30443"
kubectl -n argocd patch svc argocd-server --patch-file argocd-config/argocd-server-svc-patch.yaml

echo ">>> [3/9] Deploying demo OpenLDAP (namespace ldap)"
kubectl apply -k ldap/
kubectl -n ldap rollout status deploy/openldap --timeout=300s
sleep 10   # give slapd time to load the bootstrap LDIF

echo ">>> [4/9] Verifying LDAP users and groups"
kubectl -n ldap exec deploy/openldap -- ldapsearch -x -H ldap://localhost \
  -D "cn=readonly,dc=example,dc=org" -w 'Readonly@123' \
  -b "dc=example,dc=org" "(|(objectClass=inetOrgPerson)(objectClass=groupOfNames))" dn member \
  | grep -E '^(dn|member):'

echo ">>> [5/9] Storing LDAP bind password in argocd-secret"
kubectl -n argocd patch secret argocd-secret --patch-file argocd-config/argocd-secret-patch.yaml

echo ">>> [6/9] Configuring Dex LDAP connector + Argo CD URL (argocd-cm)"
sed "s/NODE_IP/${NODE_IP}/g" argocd-config/argocd-cm-sso-patch.yaml > /tmp/argocd-cm-sso-patch.yaml
kubectl -n argocd patch configmap argocd-cm --patch-file /tmp/argocd-cm-sso-patch.yaml
rm -f /tmp/argocd-cm-sso-patch.yaml

echo ">>> [7/9] Applying group-based RBAC (argocd-rbac-cm)"
kubectl -n argocd patch configmap argocd-rbac-cm --patch-file argocd-config/argocd-rbac-cm-sso-patch.yaml

echo ">>> [8/9] Creating dev-ns and dev-project"
kubectl apply -f argocd-config/namespaces.yaml
kubectl apply -f projects/dev-project.yaml

echo ">>> [9/9] Restarting Dex and Argo CD server to load the new config"
kubectl -n argocd rollout restart deploy/argocd-dex-server deploy/argocd-server
kubectl -n argocd rollout status deploy/argocd-dex-server --timeout=180s
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s

echo
echo "================================================================"
echo " SSO setup complete"
echo "   UI  : https://${NODE_IP}:30443   -> click 'LOG IN VIA COMPANY LDAP'"
echo "   CLI : argocd login ${NODE_IP}:30443 --sso --insecure --grpc-web --name charlie"
echo
echo "   LDAP users           group       Argo CD role"
echo "   charlie / Charlie@123  dev-team    role:dev (manage dev-app, no delete)"
echo "   diana   / Diana@123    ops-team    role:readonly"
echo "   eve     / Eve@123      (none)      no access"
echo "================================================================"
