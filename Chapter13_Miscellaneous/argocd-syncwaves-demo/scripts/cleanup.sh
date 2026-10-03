#!/usr/bin/env bash
argocd app delete waves-demo --yes 2>/dev/null || true
argocd app delete no-waves-demo --yes 2>/dev/null || true
kubectl delete namespace waves-demo no-waves-demo --ignore-not-found --wait=false
