#!/usr/bin/env bash

set -e

kubectl -n nginx scale deployment nginx --replicas=4
kubectl -n nginx get deployment nginx
flux reconcile kustomization nginx
kubectl -n nginx get deployment nginx
