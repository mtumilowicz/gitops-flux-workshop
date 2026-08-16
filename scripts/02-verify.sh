#!/usr/bin/env bash

set -e

flux reconcile kustomization namespaces-dev
flux reconcile kustomization nginx-dev
flux reconcile kustomization namespaces-prod
flux reconcile kustomization nginx-prod
flux get kustomizations

kubectl -n nginx-dev get deployment nginx
kubectl -n nginx-prod get deployment nginx

kubectl -n nginx-dev get secret nginx-workshop-secret \
  -o jsonpath='{.data.environment}' | base64 --decode
echo
