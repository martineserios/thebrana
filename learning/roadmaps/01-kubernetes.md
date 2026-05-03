# Kubernetes Roadmap

> Intermediate path. Assumes Docker fluency. Goal: run SenseLedger's backend on a local `kind` cluster, then port it to a managed cluster with GitOps, autoscaling, and observability.

## Mental model first

Before writing any YAML, hold these ideas in your head until they're boring:

1. **k8s is a reconciliation loop, not a deployer.** You declare a desired state; controllers move the world toward it. Every bug you'll hit is either "the state I declared is wrong" or "a controller can't reconcile it."
2. **Everything is an API object.** Deployments, Services, Pods, Nodes, CRDs — all just records in etcd that controllers watch.
3. **Pods are cattle with identity when you say so.** Deployment = anonymous replicas. StatefulSet = stable identity per pod. Job = run-to-completion.
4. **Networking is flat inside the cluster, gated at the edge.** Every pod can reach every other pod unless a NetworkPolicy says otherwise.

If any of the above feels fuzzy, that's your first stop.

## Core surface area (what "intermediate" means here)

You should be able to read, write, and debug these without looking it up:

| Area | Objects you should know cold |
|------|------------------------------|
| Workloads | `Deployment`, `StatefulSet`, `DaemonSet`, `Job`, `CronJob` |
| Pods | `initContainers`, `sidecars`, probes (`liveness`, `readiness`, `startup`), resource requests/limits, `securityContext` |
| Networking | `Service` (ClusterIP/NodePort/LoadBalancer), `Ingress`, `NetworkPolicy`, headless services |
| Config | `ConfigMap`, `Secret`, `env`, `envFrom`, projected volumes |
| Storage | `PersistentVolume`, `PersistentVolumeClaim`, `StorageClass`, volume modes |
| Security | `ServiceAccount`, `Role`, `RoleBinding`, `ClusterRole`, Pod Security Admission |
| Scaling | `HorizontalPodAutoscaler`, `PodDisruptionBudget`, `ResourceQuota`, `LimitRange` |

## Day-2 toolkit

The stuff that separates "I deployed a pod once" from "I run this":

- **Packaging**: Helm (charts, values, templating) *and* Kustomize (overlays, no templating). Know when to use which.
- **GitOps**: ArgoCD or Flux. Desired state lives in a git repo; cluster reconciles from it.
- **Observability**: `metrics-server`, Prometheus, Grafana, Loki/Promtail, OpenTelemetry Collector.
- **Policy**: Kyverno or Gatekeeper for admission policies.
- **Backup**: Velero for cluster backups; `pg_dump` via `CronJob` for Postgres.
- **Secrets**: External Secrets Operator (pulling from Vault / cloud secret manager). Never commit real secrets to git.
- **Progressive delivery**: Argo Rollouts or Flagger for canary / blue-green.

## Scenarios to work through

Do these in order. Each one is a milestone.

### Scenario 1 — Stand up the local cluster

- Install `kind` or `k3d`. Bring up a 3-node cluster (1 control-plane, 2 workers).
- Install `metrics-server`, `kubectl`, `k9s` or `Lens`, `stern` for log tailing.
- Deploy the SenseLedger ingest API stub (just a "hello" FastAPI/Go service) as a `Deployment` + `Service` + `Ingress`.
- Expose it locally via `kind`'s port mapping or an `ingress-nginx` installed via Helm.
- **Exit criteria**: `curl http://localhost/ingest/health` returns 200, from your laptop, hitting the pod.

### Scenario 2 — Stateful Postgres with backup

- Deploy TimescaleDB (Postgres + extension) as a `StatefulSet` with a `PersistentVolumeClaim`.
- Create a `CronJob` that runs `pg_dump` nightly and pushes to an S3-compatible store (MinIO, also deployed in the cluster).
- Simulate a disaster: `kubectl delete sts timescaledb -n senseledger`, restore from the latest dump.
- **Exit criteria**: You can kill the database and get the data back within 10 minutes.

### Scenario 3 — Config, secrets, and zero-downtime rollouts

- Externalize the ingest API's config into a `ConfigMap` and its DB password into a `Secret`.
- Change a config value and roll the Deployment without dropping a single request (readiness probes + `maxSurge`/`maxUnavailable`).
- Install Argo Rollouts. Convert the Deployment to a `Rollout` with a 25% canary and an analysis step that checks the error rate.
- **Exit criteria**: Push a broken image → canary fails analysis → automatic rollback, no alert to users.

### Scenario 4 — Observability stack

- Install `kube-prometheus-stack` via Helm.
- Instrument the ingest API with OpenTelemetry (traces + metrics).
- Wire logs through the OTel Collector to Loki.
- Build a Grafana dashboard: request rate, p95 latency, error rate, pod CPU/memory.
- Set an alert: "error rate > 5% for 2 minutes" → fires to a local webhook.
- **Exit criteria**: You can answer "what's wrong?" in under 30 seconds from the dashboard when you break something on purpose.

### Scenario 5 — Autoscaling under load

- Install `metrics-server` (if not already) and KEDA.
- HPA the ingest API on CPU; KEDA-scale the stream worker (from scenario in data-engineering roadmap) on Kafka lag.
- Hammer the ingest API with `hey` or `k6`. Watch it scale up and back down.
- Add a `PodDisruptionBudget` so rolling node upgrades don't take the whole thing down.
- **Exit criteria**: Under 500 RPS, p95 stays under target; pod count tracks load; no 5xx during scale events.

### Scenario 6 — GitOps and multi-env

- Split manifests into a Kustomize overlay: `base/`, `overlays/dev/`, `overlays/prod/`.
- Install ArgoCD in the cluster, point it at your manifest repo.
- Make a change via PR → merge → ArgoCD syncs. Never `kubectl apply` again.
- **Exit criteria**: Any change to the running system has a corresponding commit in git. No drift.

### Scenario 7 — Security hardening

- Enable Pod Security Admission in `restricted` mode on the `senseledger` namespace.
- Fix every pod that fails it (`runAsNonRoot`, `readOnlyRootFilesystem`, drop all capabilities, seccomp profile).
- Add a `NetworkPolicy` that blocks all egress except to the database, the wallet bridge, and DNS.
- Install Kyverno; add a policy requiring all images to come from your registry and to have a `sha256` digest, not a tag.
- **Exit criteria**: `kubectl auth can-i` and policy reports show zero `restricted` violations.

### Scenario 8 — Port to a managed cluster

- Provision a managed cluster (GKE Autopilot, EKS with Karpenter, or a DigitalOcean cluster if you want cheap).
- Install your GitOps controller, point it at the same repo with a new overlay (`overlays/cloud/`).
- Migrate the stateful data (pg_dump from kind → restore in cloud).
- Run for a week. Watch the bill. Understand where the money goes.
- **Exit criteria**: SenseLedger runs entirely on a managed cluster, deployed via GitOps, monitored, and you can tell me why your bill is what it is.

## Where this feeds SenseLedger

| k8s deliverable | SenseLedger piece |
|-----------------|-------------------|
| Scenario 1 | Ingest API namespace + Ingress |
| Scenario 2 | TimescaleDB for readings |
| Scenario 4 | Observability for everything |
| Scenario 5 | Stream worker autoscaling (data eng roadmap feeds this) |
| Scenario 6 | Single source of truth for config across dev / prod |
| Scenario 7 | Hardened baseline for the wallet bridge (handles private keys) |

## Resources (starting points, not a reading list)

- `kubernetes.io/docs/concepts` — the official concepts section. Read it once front to back.
- `kind.sigs.k8s.io` — local cluster.
- `helm.sh/docs` + `kustomize.io`.
- `argo-cd.readthedocs.io`, `argoproj.github.io/rollouts`.
- `prometheus-operator.dev` for `kube-prometheus-stack`.
- `kyverno.io/policies` for policy examples.
- `killercoda.com` and `kubernetes.io/training` for interactive scenarios if you want drills.

## Anti-patterns to avoid

- `latest` image tags. Always use digests or immutable tags.
- No resource requests. Leads to noisy neighbors and bad scheduling.
- Exec-into pods to debug in prod. Use logs, metrics, traces — fix the pod, don't patch the running one.
- Helm charts pulled from random GitHub users. Prefer official charts or your own forks.
- Reaching for an operator before trying a plain Deployment. Operators are great once you need them, and painful when you don't.

## Done when

- SenseLedger runs on a managed cluster, reconciled by GitOps, observed by Prometheus+Loki, autoscaled, hardened, and backed up.
- You can explain, out loud, what happens from `kubectl apply` to a pod being `Running`, and who each actor is (API server, scheduler, kubelet, CRI, CNI).
- You've broken it on purpose at least three times and recovered without swearing.
