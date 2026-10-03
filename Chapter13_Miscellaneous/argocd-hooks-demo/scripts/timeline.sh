#!/usr/bin/env bash
# Usage: ./scripts/timeline.sh [namespace]
# Lists hook Jobs in the order they started, with their phase and wave.
NS="${1:-hooks-demo}"
kubectl get jobs -n "$NS" --sort-by=.status.startTime \
  -o custom-columns='JOB:.metadata.name,PHASE:.metadata.annotations.argocd\.argoproj\.io/hook,WAVE:.metadata.annotations.argocd\.argoproj\.io/sync-wave,STARTED:.status.startTime,COMPLETED:.status.completionTime,SUCCEEDED:.status.succeeded,FAILED:.status.failed'
