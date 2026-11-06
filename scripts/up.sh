#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

kind create cluster --config cluster/kind.yaml --kubeconfig .kubeconfig

# Registries return the occasional 5xx. Retry the base image instead of failing the run.
pulled=false
for attempt in 1 2 3 4 5; do
  if docker pull -q golang:1.24-alpine; then
    pulled=true
    break
  fi
  echo "pull failed (attempt $attempt of 5), retrying in $((attempt * 15))s"
  sleep $((attempt * 15))
done
"$pulled"

docker build -q -t shop:lab app
kind load docker-image shop:lab --name "$CLUSTER"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add chaos-mesh https://charts.chaos-mesh.org >/dev/null
helm repo update >/dev/null

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "$KUBE_PROMETHEUS_CHART" --namespace monitoring --create-namespace \
  --values deploy/monitoring-values.yaml --wait --timeout 8m

helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  --version "$CHAOS_MESH_CHART" --namespace chaos-mesh --create-namespace \
  --values deploy/chaos-mesh-values.yaml --wait --timeout 5m

kubectl apply -f deploy/dashboard.yaml
kubectl apply -f deploy/shop.yaml
kubectl -n shop rollout status deployment/pricing --timeout=2m
kubectl -n shop rollout status deployment/storefront --timeout=2m
kubectl -n shop rollout status deployment/customers --timeout=2m

echo
echo "Grafana:    http://localhost:30300/d/chaos-lab"
echo "Prometheus: http://localhost:30090"
