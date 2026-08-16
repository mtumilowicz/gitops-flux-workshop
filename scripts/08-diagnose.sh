#!/usr/bin/env bash

flux check
flux get all
flux events --for GitRepository/gitops-flux-workshop
flux events --for Kustomization/nginx-dev
flux logs --kind=Kustomization --name=nginx-dev
flux tree kustomization nginx-dev
kubectl -n nginx-dev get pods
kubectl -n nginx-dev describe deployment nginx
