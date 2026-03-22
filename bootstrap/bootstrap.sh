#!/usr/bin/env bash
set -euo pipefail

# requires: kind, kubectl, helm
# requires env: GITHUB_USER, GITHUB_TOKEN

if kind get clusters 2>/dev/null | grep -q "gitops-cluster"; then
  echo "Cluster already exists, skipping..."
else
  echo "Setting up Kind cluster"
  kind create cluster --config bootstrap/kind-config.yaml
fi

kubectl config use-context kind-gitops-cluster

if helm status argocd -n argocd &>/dev/null; then
  echo "Argo CD already installed, skipping..."
else
  echo "Installing Argo CD via Helm"
  helm repo add argo https://argoproj.github.io/argo-helm --force-update
  helm repo update
  helm install argocd argo/argo-cd \
    --namespace argocd \
    --create-namespace \
    --version 7.3.4 \
    --values bootstrap/argocd-values.yaml \
    --wait
fi

echo "Applying RBAC"
kubectl apply -f argocd/rbac-config.yaml

echo "Creating app namespace / pull secret..."
kubectl apply -f k8s/namespace.yaml
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username="${GITHUB_USER}" \
  --docker-password="${GITHUB_TOKEN}" \
  --namespace app \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Patching repo URL into application.yaml"
REPO_URL=$(git remote get-url origin)
if grep -q "REPO_URL_PLACEHOLDER" argocd/application.yaml; then
  sed -i.bak "s|REPO_URL_PLACEHOLDER|${REPO_URL}|g" argocd/application.yaml
  rm -f argocd/application.yaml.bak
fi

echo "Applying Argo CD Application"
kubectl apply -f argocd/application.yaml

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "Done."
echo " Argo CD: make argocd-ui  (admin / ${ARGOCD_PASSWORD})"
echo " App:     make app-forward -> curl http://localhost:8888/health"