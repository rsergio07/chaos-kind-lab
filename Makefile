.PHONY: preflight up verdict chaos stop-chaos fix unfix status down

export KUBECONFIG := $(CURDIR)/.kubeconfig
WINDOW ?= 60

preflight: ## Check tools, resources and tc netem support
	@./scripts/preflight.sh

up: ## Create the cluster and install everything
	@./scripts/up.sh

verdict: ## SLO verdict over the last WINDOW seconds
	@./scripts/verdict.sh $(WINDOW)

chaos: ## Add 800ms of latency to pricing for 180 seconds
	@kubectl delete -f experiments/pricing-latency.yaml --ignore-not-found --wait=true
	@kubectl apply -f experiments/pricing-latency.yaml

stop-chaos: ## End the experiment early
	@kubectl delete -f experiments/pricing-latency.yaml --ignore-not-found

fix: ## Give storefront a timeout and a fallback
	@kubectl -n shop set env deployment/storefront PRICING_TIMEOUT=150ms FALLBACK=true
	@kubectl -n shop rollout status deployment/storefront --timeout=2m

unfix: ## Put the bug back
	@kubectl -n shop set env deployment/storefront PRICING_TIMEOUT=0s FALLBACK=false
	@kubectl -n shop rollout status deployment/storefront --timeout=2m

status: ## Show pods and the experiment
	@kubectl -n shop get pods
	@kubectl -n shop get networkchaos

down: ## Delete the cluster
	@kind delete cluster --name chaos-lab --kubeconfig $(KUBECONFIG)
