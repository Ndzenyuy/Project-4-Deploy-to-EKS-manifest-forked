# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **manifest repository** for the lumiatech Java Spring MVC application deployed to AWS EKS. It is one half of a GitOps setup — the **application repository** (`Project-4-Deploy-to-EKS-app`) holds source code and CI/CD pipeline; this repo holds all Kubernetes manifests and the Helm chart. ArgoCD watches this repo and syncs changes to the cluster automatically.

**Namespace**: `lumiatech`  
**Domain**: `www.lumiatechs.com`  
**Cluster**: `lumiatechs-eks-cluster` (us-east-1, K8s v1.35)

## Repository Structure

- `helm/lumiatech/` — Helm chart (primary deployment method). Templates use `values.yaml` for image tags, replicas, DB config, and ingress host.
- `kubedefs/` — Raw (non-templated) Kubernetes manifests. Used as the base from which Helm templates were derived; kept for reference and direct `kubectl apply` scenarios.
- `eks-setup/` — Shell scripts for cluster provisioning and tooling.

## Key Deployment Commands

### Helm (primary)

```bash
# Lint and preview before applying
helm lint helm/lumiatech
helm template lumiatech helm/lumiatech -n lumiatech

# Install
helm install lumiatech helm/lumiatech -n lumiatech --create-namespace

# Upgrade after manifest changes
helm upgrade lumiatech helm/lumiatech -n lumiatech

# Override image tag (used by CI pipeline)
helm upgrade lumiatech helm/lumiatech -n lumiatech \
  --set app.image=ndzenyuy/lumia-app:<tag>

# Rollback
helm rollback lumiatech -n lumiatech

# Uninstall
helm uninstall lumiatech -n lumiatech
```

### kubectl (raw manifests)

```bash
kubectl apply -f kubedefs/
kubectl delete -f kubedefs/
```

### Verify deployment

```bash
kubectl get pods,svc,ingress -n lumiatech
kubectl logs -f deployment/lumia-app -n lumiatech
kubectl logs -f deployment/lumiadb -n lumiatech
kubectl describe pod <pod-name> -n lumiatech
```

## Architecture

Two deployments in the `lumiatech` namespace:

1. **lumia-app** — Java Spring MVC (WAR on Tomcat), port 8080. Has an init container that blocks startup until the `lumiadb` DNS name resolves, ensuring DB is ready before the app starts.
2. **lumiadb** — MySQL 8.0.33 with a pre-loaded schema. Has an init container that removes `lost+found` from the EBS volume before MySQL starts (required for MySQL to accept the mount).

Database password is stored in a Kubernetes Secret (`app-secret`, key `db-pass`). The Helm template auto-base64-encodes the plaintext value from `values.yaml` using `{{ .Values.db.password | b64enc }}`. The raw `kubedefs/secret.yaml` contains a hardcoded base64 value (`YWRtaW4xMjM=` = `admin123`).

Persistent storage uses a PVC (`db-pv-claim`) backed by AWS EBS gp2 (3Gi). The **EBS CSI driver must be installed** on the cluster for PVCs to bind — use `eks-setup/install-ebs-csi.sh`.

Traffic flow: Internet → AWS NLB → NGINX Ingress Controller (ingress-nginx namespace) → `lumia-app-service:8080` → lumia-app pods.

## Image Tags

The CI pipeline (Jenkins in the app repo) builds images tagged with the Git commit SHA and updates `helm/lumiatech/values.yaml` with the new tag before committing to this repo. ArgoCD detects the commit and syncs. Do not manually set `app.image` to `latest` in `values.yaml` — that defeats the GitOps traceability.

## Cluster Setup (one-time)

```bash
# 1. Create EKS cluster
bash eks-setup/eks-setup.sh

# 2. Update kubeconfig
aws eks update-kubeconfig --name lumiatechs-eks-cluster --region us-east-1

# 3. Install NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml

# 4. Install EBS CSI driver (required for PVC to bind)
bash eks-setup/install-ebs-csi.sh

# 5. Deploy application
helm install lumiatech helm/lumiatech -n lumiatech --create-namespace
```

## Monitoring

Prometheus + Grafana deployed via `kube-prometheus-stack` in the `monitoring` namespace. `kubedefs/servicemonitor.yaml` configures Prometheus to scrape the app at `/actuator/prometheus` (requires Spring Boot Actuator + Micrometer on the app side).

```bash
# Install monitoring stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

kubectl apply -f kubedefs/servicemonitor.yaml
```

Grafana dashboard IDs: cluster overview `315`, pod metrics `6417`, JVM/Micrometer `4701`, Node Exporter `1860`.

## ArgoCD

```bash
# Install
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Create app pointing to this repo
argocd app create lumiatech \
  --repo https://github.com/DevOps-Cloud-Mentorship/Project-4-Deploy-to-EKS-manifest.git \
  --path helm/lumiatech \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace lumiatech \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

## Common Troubleshooting

- **PVC stuck Pending**: EBS CSI driver not installed — run `eks-setup/install-ebs-csi.sh`.
- **App init container looping**: `lumiadb` service DNS not resolving — check DB deployment and service are up (`kubectl get pods,svc -n lumiatech`).
- **ImagePullBackOff**: Image tag in `values.yaml` doesn't exist in Docker Hub.
- **Ingress not routing**: Get the NLB hostname with `kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'` and ensure DNS/hosts file points `www.lumiatechs.com` to it.
- **Grafana shows no data**: Datasource URL must be the in-cluster DNS (`http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090`), not the external LoadBalancer hostname.
