#!/usr/bin/env bash

set -e

flux reconcile kustomization nginx --with-source
flux get kustomizations -n flux-system

kubectl -n nginx get deployment nginx
kubectl -n nginx get service nginx
kubectl -n nginx get configmap nginx-index
