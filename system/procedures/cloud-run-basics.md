---
name: cloud-run-basics
description: >-
  Manages Cloud Run services, jobs, and worker pools. Use when you need to deploy applications
  responding to HTTP requests (services), run event-triggered or scheduled tasks (jobs),
  or handle always-on pull-based background processing (worker pools).
---

# Cloud Run Basics

Cloud Run is a fully managed application platform for running your code,
function, or container on top of Google's highly scalable infrastructure. It
abstracts away infrastructure management, providing three primary resource
types:

1.  **Services:** Responds to HTTP requests sent to a unique and stable
    endpoint, using stateless instances that autoscale based on a variety of key
    metrics, also responds to events and functions.
2.  **Jobs:** Executes parallelizable tasks that are executed manually, or on a
    schedule, and run to completion.
3.  **Worker pools:** Handles always-on background workloads such as pull-based
    workloads, for example, Kafka consumers, Pub/Sub pull queues, or RabbitMQ
    consumers.

## Prerequisites

Enable the Cloud Run Admin API and Cloud Build APIs:

```bash
gcloud services enable run.googleapis.com cloudbuild.googleapis.com
```

### Required roles

- Cloud Run Admin (`roles/run.admin`) on the project
- Cloud Run Source Developer (`roles/run.sourceDeveloper`) on the project
- Service Account User (`roles/iam.serviceAccountUser`) on the service identity
- Logs Viewer (`roles/logging.viewer`) on the project

## Deploy a Cloud Run service

> **CRITICAL RULE:** Any deployed code MUST listen on 0.0.0.0 (not 127.0.0.1)
> and use the injected $PORT environment variable (defaults to 8080), or it will
> crash on boot.

### Deploy a container image

```bash
gcloud run deploy SERVICE_NAME \
    --image IMAGE_URL \
    --region us-central1 \
    --allow-unauthenticated
```

### Deploy from source code

```bash
# With Dockerfile (Cloud Build runs it):
gcloud run deploy SERVICE_NAME --source .

# With buildpacks + automatic base image updates:
gcloud run deploy SERVICE_NAME --source . \
  --base-image BASE_IMAGE \
  --automatic-updates
```

## Create and execute a Cloud Run job

```bash
gcloud run jobs create JOB_NAME --image IMAGE_URL OPTIONS
gcloud run jobs execute JOB_NAME --wait --region=REGION
```

## Deploy a worker pool

```bash
gcloud run worker-pools deploy WORKER_POOL_NAME --image IMAGE_URL
# or from source:
gcloud run worker-pools deploy WORKER_POOL_NAME --source .
```

## What to do if a deployment fails

1. **IAM/Permission Error:** Check roles listed above.
2. **Crash on Boot / Healthcheck failed:** `gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="SERVICE_NAME"' --limit=20`
3. **Native Dependency Error (Node/Python):** Switch from `--no-build` to `--source .` (Buildpacks).

## Project-specific notes (proyecto_anita)

- Service name: `palco-v3-api`, project: `palco-prod`, region: `us-central1`
- Deploy procedure: `bash deploy/gcp/cloud_run/deploy-multitenant.sh` (--no-traffic, smoke tests, auto-migrate)
- Logs: use `gcloud logging read` with `resource.type="cloud_run_revision"` filter — `gcloud run logs read` is invalid
- Python structlog emits `jsonPayload.event`, not `jsonPayload.message`
- Memory: 1 GiB minimum for batch workloads
- Timeout: 1800s for both Cloud Run `--timeout` and Cloud Scheduler `--attempt-deadline`
- See `.claude/rules/cloud-run-deploy.md` for full deploy gate and rollback procedure
