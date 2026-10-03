#!/usr/bin/env bash
# Usage: ./scripts/order.sh [namespace]
# Lists resources in the order they were created, with their sync wave.
NS="${1:-waves-demo}"
kubectl get cm,deploy,svc,job -n "$NS" --sort-by=.metadata.creationTimestamp \
  -o custom-columns='CREATED:.metadata.creationTimestamp,WAVE:.metadata.annotations.argocd\.argoproj\.io/sync-wave,KIND:.kind,NAME:.metadata.name' \
  | grep -v kube-root-ca
