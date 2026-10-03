#!/usr/bin/env bash
# Usage: ./scripts/logs.sh [namespace]
# Prints the logs of every hook Job, in the order they started.
NS="${1:-hooks-demo}"
for JOB in $(kubectl get jobs -n "$NS" --sort-by=.status.startTime -o jsonpath='{.items[*].metadata.name}'); do
  echo "=============== $JOB ==============="
  kubectl logs -n "$NS" "job/$JOB" 2>/dev/null || echo "(no logs)"
  echo
done
