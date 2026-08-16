#!/usr/bin/env bash

set -e

flux get kustomizations

echo "Verify dev:"
echo "  kubectl -n nginx-dev port-forward service/nginx 8080:80"
echo "  open http://localhost:8080, then stop the command with Ctrl-C"
echo
echo "Verify prod:"
echo "  kubectl -n nginx-prod port-forward service/nginx 8080:80"
echo "  open http://localhost:8080, then stop the command with Ctrl-C"
