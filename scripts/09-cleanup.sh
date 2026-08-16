#!/usr/bin/env bash

set -e

echo "This removes the workshop resources but leaves Flux installed."
read -r -p "Type yes to continue: " confirmation
[[ "${confirmation}" == "yes" ]] || exit 0

kubectl delete -k flux-setup
kubectl wait namespace/nginx-dev --for=delete --timeout=2m
kubectl wait namespace/nginx-prod --for=delete --timeout=2m
kubectl delete -k sops-setup
