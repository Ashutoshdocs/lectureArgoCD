#!/usr/bin/env bash
# Usage: ./scripts/kubectl-demo.sh foreground|background|orphan
# Deploys demo-web into namespace demo-kubectl, waits, then deletes the
# Deployment with the chosen propagation policy. Run ./scripts/watch.sh demo-kubectl
# in a second terminal to watch the order of deletion.
set -euo pipefail
POLICY="${1:?usage: $0 foreground|background|orphan}"
NS=demo-kubectl

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "$NS" -f manifests/deployment.yaml
kubectl rollout status deployment/demo-web -n "$NS"

echo
echo ">>> Deleting deployment/demo-web with --cascade=$POLICY"
kubectl delete deployment demo-web -n "$NS" --cascade="$POLICY" --wait=false
