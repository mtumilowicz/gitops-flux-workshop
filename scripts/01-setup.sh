#!/usr/bin/env bash

set -e

flux check --pre

flux install
kubectl -n flux-system wait deployment --all \
  --for=condition=Available \
  --timeout=2m

kubectl apply -k sops-setup
kubectl apply -k flux-setup
