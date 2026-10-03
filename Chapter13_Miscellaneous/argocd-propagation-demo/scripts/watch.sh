#!/usr/bin/env bash
# Usage: ./scripts/watch.sh <namespace>
# Shows the owner chain, and which objects are being deleted, once per second.
NS="${1:-demo-kubectl}"
while true; do
  clear
  echo "Namespace: $NS    $(date +%T)"
  echo
  kubectl get deploy,rs,pod -n "$NS" \
    -o custom-columns='KIND:.kind,NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].name,DELETING-SINCE:.metadata.deletionTimestamp,FINALIZERS:.metadata.finalizers' \
    2>/dev/null || echo "(nothing found)"
  sleep 1
done
