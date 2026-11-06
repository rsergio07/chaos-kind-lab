#!/usr/bin/env bash
# Pinned versions. The lab is only claimed to work with these.
export KIND_VERSION="v0.33.0"
export CHAOS_MESH_CHART="2.8.7"
export KUBE_PROMETHEUS_CHART="92.18.0"
export CLUSTER="chaos-lab"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
# A private kubeconfig, so the lab never touches your other clusters.
export KUBECONFIG="$ROOT/.kubeconfig"
