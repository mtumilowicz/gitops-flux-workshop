#!/usr/bin/env bash

set -e

kubectl -n flux-system patch kustomization namespaces-dev \
  --type=merge \
  --patch='{"spec":{"path":"./does-not-exist"}}'

flux reconcile kustomization namespaces-dev || true
flux events --for Kustomization/namespaces-dev
flux reconcile kustomization nginx-dev || true

kubectl apply -f flux-setup/dev/namespaces-sync.yaml
flux reconcile kustomization namespaces-dev
flux reconcile kustomization nginx-dev
