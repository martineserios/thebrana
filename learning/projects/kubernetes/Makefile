# Convenience targets for SenseLedger k8s scenarios.
#
# These wrap the most common kind/kubectl/helm invocations so you can focus
# on the scenario content instead of re-typing flags. None of this is required
# — read each target before running it.

CLUSTER_NAME ?= senseledger
NAMESPACE    ?= senseledger

.PHONY: help
help:
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: cluster-up
cluster-up: ## Create the kind cluster
	kind create cluster --name $(CLUSTER_NAME) --config kind-cluster.yaml

.PHONY: cluster-down
cluster-down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER_NAME)

.PHONY: cluster-ctx
cluster-ctx: ## Switch kubectl context to this cluster
	kubectl config use-context kind-$(CLUSTER_NAME)

.PHONY: ingress-install
ingress-install: ## Install ingress-nginx via Helm
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true
	helm repo update
	helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
		--namespace ingress-nginx --create-namespace \
		--set controller.service.type=NodePort \
		--set controller.service.nodePorts.http=30080 \
		--set controller.service.nodePorts.https=30443 \
		--set controller.hostPort.enabled=true \
		--set controller.nodeSelector."ingress-ready"=true

.PHONY: deploy-dev
deploy-dev: ## Apply base manifests via Kustomize (dev overlay)
	kubectl apply -k overlays/dev

.PHONY: deploy-staging
deploy-staging: ## Apply staging overlay (managed cluster context required)
	kubectl apply -k overlays/staging

.PHONY: logs
logs: ## Tail logs for the ingest API
	kubectl -n $(NAMESPACE) logs -l app.kubernetes.io/name=ingest-api -f --tail=100

.PHONY: port-forward
port-forward: ## Port-forward ingest API directly (bypasses ingress)
	kubectl -n $(NAMESPACE) port-forward svc/ingest-api 8080:80

.PHONY: clean
clean: ## Remove the SenseLedger namespace (keeps cluster)
	kubectl delete namespace $(NAMESPACE) --ignore-not-found
