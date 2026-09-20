#!/usr/bin/env bash
# Helper: build a version of the frontend and push it to ACR.
# Usage:  bash build-push.sh 1.0.0
set -euo pipefail

ACR_NAME="myacrdemo"          # <-- EDIT: your ACR name (without .azurecr.io)
VERSION="${1:?Usage: build-push.sh <version>   e.g. build-push.sh 1.0.1}"
LOGIN_SERVER="${ACR_NAME}.azurecr.io"
IMAGE="${LOGIN_SERVER}/frontend:${VERSION}"

az acr login --name "$ACR_NAME"

# Build straight in ACR (no local Docker needed):
az acr build \
  --registry "$ACR_NAME" \
  --image "frontend:${VERSION}" \
  --build-arg APP_VERSION="${VERSION}" \
  ./app

# --- OR build locally and push (uncomment if you prefer local Docker) ---
# docker build --build-arg APP_VERSION="${VERSION}" -t "$IMAGE" ./app
# docker push "$IMAGE"

echo "✅ Pushed ${IMAGE}"
