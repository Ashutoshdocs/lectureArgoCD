#!/usr/bin/env bash
# Removes everything the demo created (except Argo CD itself).
for APP in demo-foreground demo-background demo-orphan; do
  argocd app delete "$APP" --yes 2>/dev/null || true
done
for NS in demo-kubectl demo-foreground demo-background demo-orphan; do
  kubectl delete namespace "$NS" --ignore-not-found --wait=false
done
