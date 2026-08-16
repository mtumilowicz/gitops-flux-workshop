#!/usr/bin/env bash

set -e

kubectl -n nginx-dev scale deployment nginx --replicas=4
kubectl -n nginx-dev get deployment nginx
flux reconcile kustomization nginx-dev
kubectl -n nginx-dev get deployment nginx
