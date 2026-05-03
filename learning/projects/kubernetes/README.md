# Kubernetes — SenseLedger Hands-On

Scaffold for the `k8s` roadmap scenarios. Everything here targets a local [kind](https://kind.sigs.k8s.io) cluster first, then graduates to a managed cluster via Kustomize overlays.

## What's here

```
kubernetes/
├── README.md              ← you are here
├── kind-cluster.yaml      ← 3-node kind cluster config with port mapping
├── Makefile               ← common lifecycle commands
├── manifests/             ← base Kustomize resources
│   ├── kustomization.yaml
│   ├── 00-namespace.yaml
│   ├── 10-ingest-deployment.yaml
│   ├── 20-ingest-service.yaml
│   └── 30-ingest-ingress.yaml
├── overlays/              ← per-env overlays
│   ├── dev/
│   └── staging/
└── scenarios/             ← per-scenario notes (see roadmap)
    └── README.md
```

## Prerequisites

- `docker` (or `podman` with a `docker` alias)
- `kind` — local cluster
- `kubectl` — always install the version matching your cluster
- `helm` — for installing `ingress-nginx`, `kube-prometheus-stack`, etc.
- `kustomize` — bundled with recent `kubectl`, but a standalone binary is nicer
- Optional but recommended: `k9s` or `lens`, `stern` for log tailing, `dive` for image inspection

## Quickstart (Scenario 1)

```bash
# 1. Create the cluster
make cluster-up

# 2. Install ingress-nginx (Helm)
make ingress-install

# 3. Deploy SenseLedger's ingest stub
make deploy-dev

# 4. Hit it
curl -H "Host: senseledger.local" http://localhost/ingest/health
```

Teardown:

```bash
make cluster-down
```

## Scenario map

Each subfolder in `scenarios/` contains a short notes file: what the scenario adds, how to apply it, and what "done" looks like. The scenarios build on each other — don't skip ahead.

| # | Scenario | New manifests |
|---|----------|---------------|
| 1 | Stand up the cluster + ingest stub | base + ingress-nginx |
| 2 | Stateful Postgres/Timescale + backup | StatefulSet, PVC, CronJob |
| 3 | Config, secrets, Argo Rollouts canary | Rollout, AnalysisTemplate |
| 4 | Observability (kube-prometheus-stack + Loki) | Helm values, ServiceMonitor |
| 5 | Autoscaling (HPA + KEDA) | HPA, ScaledObject |
| 6 | GitOps with ArgoCD | Application manifests |
| 7 | Security hardening (PSA, NetworkPolicy, Kyverno) | NP, Kyverno policies |
| 8 | Port to managed cluster | new overlay |

## Conventions

- **No `latest` tags.** Pin images by digest (`@sha256:...`) in overlays going to staging. In dev, tags are ok.
- **No kubectl apply in CI.** GitOps only once you reach scenario 6.
- **Every service has**: resource requests/limits, readiness + liveness probes, a ServiceMonitor (once Prom is in), a NetworkPolicy (once scenario 7).
- **One namespace per context.** `senseledger` for app, `senseledger-data` for stateful, `senseledger-system` for platform.

## Notes on `kind` vs real clusters

`kind` is the fastest feedback loop but:

- LoadBalancer services don't work out of the box — use `ingress-nginx` via NodePort or `cloud-provider-kind`.
- Persistent volumes use local path storage; they survive pod restarts but not cluster recreates.
- Autoscaling requires `metrics-server` with `--kubelet-insecure-tls` in kind.
- Resource metrics will look weird because all nodes share your laptop's kernel.

None of this blocks learning — just be aware when you port to a managed cluster.
