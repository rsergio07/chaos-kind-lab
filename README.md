# chaos-kind-lab

A hands-on chaos engineering lab. You run a small shop on a local Kubernetes
cluster, make one dependency slow with Chaos Mesh, measure what customers feel with
Prometheus and Grafana, fix the bug, and prove the fix with the same experiment.

**Video walkthrough:** on the [Reliability Bench](https://www.youtube.com/@reliabilitybench) YouTube channel

## What you will learn

- How to define an SLO and measure a baseline before you break anything
- How to write and run a `NetworkChaos` experiment
- Why pod status can look fine while customers leave
- How a small delay can become an outage when capacity runs out
- How timeouts and fallbacks change the way a system degrades

## Architecture

| Part | Role |
| --- | --- |
| [kind](https://kind.sigs.k8s.io/) | Local Kubernetes cluster |
| `customers` | Sends 20 checkouts per second and gives up after 1 second |
| `storefront` | 2 pods with 6 worker slots each. Calls `pricing` for every checkout |
| `pricing` | Returns a price in about 20ms |
| [Chaos Mesh](https://chaos-mesh.org/) | Injects network latency into `pricing` |
| Prometheus and Grafana | SLO measurement and dashboard |

**SLO:** 99% of checkouts finish in under 500ms.

## Requirements

Docker with 4 CPUs and 8 GiB of memory, plus `git`, `make`, `kind`, `kubectl`, `helm`,
`jq` and `curl`. This lab uses only open source software and runs locally.

Tested on one setup: macOS arm64, Colima 0.10.3 (4 CPUs, 8 GiB, `vz`), kind 0.33.0 with
Kubernetes 1.37, Helm 4.3.1, Chaos Mesh 2.8.7 and kube-prometheus-stack 92.18.0. Other
platforms are untested. On Colima, raise the inotify limits first:

```bash
colima ssh -- sudo sysctl -w fs.inotify.max_user_instances=1024 fs.inotify.max_user_watches=1048576
```

## The lab

Run every command from the repository root. The first run downloads several images,
so it can take a while.

### Step 1: Get the code and check your machine

```bash
git clone https://github.com/rsergio07/chaos-kind-lab.git chaos-kind-lab
cd chaos-kind-lab
make preflight
```

Every line should say `ok`. The last check confirms that your kernel supports `tc netem`.

### Step 2: Create the cluster

```bash
kind create cluster --config cluster/kind.yaml --kubeconfig .kubeconfig
export KUBECONFIG=$PWD/.kubeconfig
kubectl get nodes
```

The private `.kubeconfig` keeps this lab away from your other clusters. If you open a
new terminal, run the `export` line again.

### Step 3: Build the app and load it into the cluster

```bash
docker build -t shop:lab app
kind load docker-image shop:lab --name chaos-lab
```

### Step 4: Install monitoring and Chaos Mesh

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 92.18.0 -n monitoring --create-namespace -f deploy/monitoring-values.yaml --wait --timeout 8m
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh --version 2.8.7 -n chaos-mesh --create-namespace -f deploy/chaos-mesh-values.yaml --wait --timeout 5m
kubectl -n chaos-mesh get pods
```

### Step 5: Deploy the shop

```bash
kubectl apply -f deploy/dashboard.yaml
kubectl apply -f deploy/shop.yaml
kubectl -n shop rollout status deployment/storefront --timeout=2m
kubectl -n shop get pods
```

Open Grafana at <http://localhost:30300/d/chaos-lab>. There is no login.

### Step 6: Measure the baseline

Wait 90 seconds for traffic to build up, then run:

```bash
./scripts/verdict.sh 60
```

You should see `SLO (99% < 500ms) PASS`.

### Step 7: Run the experiment

Read `experiments/pricing-latency.yaml`, and write down your prediction before you run it.

```bash
kubectl apply -f experiments/pricing-latency.yaml
kubectl -n shop get networkchaos
```

After 60 seconds, check what Kubernetes sees:

```bash
kubectl -n shop get pods
kubectl -n shop get events --field-selector reason=Unhealthy
```

After 2 minutes in total, check what customers see:

```bash
./scripts/verdict.sh 120
```

### Step 8: Understand the result

Capacity is slots divided by latency. With 12 slots and about 0.83 seconds per checkout,
the storefront can finish about 14 checkouts per second, but 20 arrive. Watch
`abandoned_in_flight` in the bottom right panel: the storefront keeps working on requests
that customers have already left.

The experiment removes its own fault after 180 seconds. Wait for it to end, then confirm
the shop has recovered:

```bash
./scripts/verdict.sh 30
```

### Step 9: Apply the fix

```bash
kubectl -n shop set env deployment/storefront PRICING_TIMEOUT=150ms FALLBACK=true
kubectl -n shop rollout status deployment/storefront --timeout=2m
```

### Step 10: Run the same experiment again

```bash
kubectl delete -f experiments/pricing-latency.yaml
kubectl apply -f experiments/pricing-latency.yaml
```

After 2 minutes:

```bash
./scripts/verdict.sh 120
```

The SLO should pass. `pricing` is still slow, and customers now receive a last known
price. That is degraded service, so a real system should alert on the fallback rate.

### Step 11: Clean up

```bash
kind delete cluster --name chaos-lab --kubeconfig .kubeconfig
```

## Challenges

Predict the result before each run.

1. Set `PRICING_TIMEOUT=900ms`. Does the shop survive?
2. Keep the original bug and raise `MAX_INFLIGHT`. How many slots do you need?
3. Change `RPS` on the `customers` deployment to find the new limit.
4. Add a Grafana panel for the fallback rate.

## Shortcuts

`make up` runs steps 2 to 5. `make verdict`, `make chaos`, `make fix`, `make unfix`,
`make status` and `make down` cover the rest.

## Notes on the numbers

The p99 comes from histogram buckets, so it is an estimate. `inside SLO` can include fast
errors, so read it next to `completed`. Fallback responses count as completed.

## Safety

The lab never changes your default Kubernetes context. Grafana allows anonymous viewing,
and its ports are for local use only. Do not expose them.

## License

MIT
