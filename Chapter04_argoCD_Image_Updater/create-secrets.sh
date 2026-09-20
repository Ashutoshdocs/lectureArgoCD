#!/usr/bin/env bash
# Helper: create the ACR pull secret and the Git write-back secret.
# Edit the variables below, then run:  bash create-secrets.sh
set -euo pipefail

# ----- EDIT THESE -----
ACR_NAME="myacrdemo"                       # ACR name (without .azurecr.io)
ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
GIT_USERNAME="Ashutoshdocs"                # GitHub username
GIT_TOKEN="ghp_replace_me"                 # GitHub PAT with 'repo' scope
# ----------------------

# 1) ACR pull secret in the app namespace (used by the Deployment + Image Updater).
#    Get an ACR token with: az acr credential show -n "$ACR_NAME"
ACR_USERNAME="$(az acr credential show -n "$ACR_NAME" --query username -o tsv)"
ACR_PASSWORD="$(az acr credential show -n "$ACR_NAME" --query 'passwords[0].value' -o tsv)"

kubectl create namespace frontend-demo --dry-run=client -o yaml | kubectl apply -f -

kubectl -n frontend-demo create secret docker-registry acr-secret \
  --docker-server="$ACR_LOGIN_SERVER" \
  --docker-username="$ACR_USERNAME" \
  --docker-password="$ACR_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# 2) Git credentials for Image Updater write-back (lives in argocd namespace).
kubectl -n argocd create secret generic git-creds \
  --from-literal=username="$GIT_USERNAME" \
  --from-literal=password="$GIT_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Secrets created: frontend-demo/acr-secret and argocd/git-creds"
