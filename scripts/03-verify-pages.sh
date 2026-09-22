#!/usr/bin/env bash

set -e

flux get kustomizations -n flux-system

echo "Verify nginx:"
echo "  kubectl -n nginx port-forward service/nginx 8080:80"
echo "  open http://localhost:8080, then stop the command with Ctrl-C"
