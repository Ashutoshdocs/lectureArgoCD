#!/usr/bin/env bash
# Usage: ./scripts/watch.sh [namespace]
# Live view of hook Jobs and app resources during a sync.
NS="${1:-hooks-demo}"
while true; do
  clear
  echo "Namespace: $NS    $(date +%T)"; echo
  kubectl get jobs,deploy,svc,cm,secret -n "$NS" 2>/dev/null | grep -v kube-root-ca || echo "(nothing yet)"
  sleep 2
done
