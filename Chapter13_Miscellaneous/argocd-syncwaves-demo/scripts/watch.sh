#!/usr/bin/env bash
# Usage: ./scripts/watch.sh [namespace]
# Live view of pods (watch the RESTARTS column) and jobs.
NS="${1:-waves-demo}"
while true; do
  clear
  echo "Namespace: $NS    $(date +%T)"; echo
  kubectl get deploy,job -n "$NS" 2>/dev/null; echo
  kubectl get pods -n "$NS" 2>/dev/null || echo "(nothing yet)"
  sleep 2
done
