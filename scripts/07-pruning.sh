#!/usr/bin/env bash

set -e

echo "This demo creates and pushes a pruning commit and a revert commit."
read -r -p "Type yes to continue: " confirmation
[[ "${confirmation}" == "yes" ]] || exit 0

perl -ni -e 'print unless /^  - secret\.enc\.yaml$/' \
  apps/nginx/overlays/dev/kustomization.yaml
git add apps/nginx/overlays/dev/kustomization.yaml
git commit -m 'Remove dev workshop secret'
git push

flux reconcile kustomization nginx-dev --with-source
kubectl -n nginx-dev get secret nginx-workshop-secret || true

git revert --no-edit HEAD
git push
flux reconcile kustomization nginx-dev --with-source
kubectl -n nginx-dev get secret nginx-workshop-secret
