#!/usr/bin/env bash

set -e

echo "This demo creates and pushes a change commit and a revert commit."
read -r -p "Type yes to continue: " confirmation
[[ "${confirmation}" == "yes" ]] || exit 0

perl -pi -e \
  's/index\.html: "environment: dev"/index.html: "environment: dev-updated"/' \
  apps/nginx/overlays/dev/configmap.yaml
git add apps/nginx/overlays/dev/configmap.yaml
git commit -m 'Update dev page'
git push

flux reconcile kustomization nginx-dev --with-source

echo "Verify the change:"
echo "  kubectl -n nginx-dev port-forward service/nginx 8080:80"
echo "  open http://localhost:8080, then stop the command with Ctrl-C"
read -r -p "Type OK after verification: " verification
[[ "${verification}" == "OK" ]] || exit 0

git revert --no-edit HEAD
git push
flux reconcile kustomization nginx-dev --with-source
