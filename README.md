# lumiatech Java Application — Kubernetes Deployment on AWS EKS

## Overview

This is the **manifest repository** for the lumiatech Java Spring MVC application. It follows a GitOps pattern with two repositories:

- **Application repository** (`Project-4-Deploy-to-EKS-app`): Java source code, Dockerfile, Jenkinsfile CI/CD pipeline
- **Manifest repository** (this repo): Kubernetes manifests (`kubedefs/`) and Helm chart (`helm/lumiatech/`)

ArgoCD watches this repository and syncs changes to the cluster automatically.

## Architecture

![Kubernetes Architecture Diagram](./images/project-4-deploy-to-eks.png)

**Application stack** (all deployed in the `lumiatech` namespace):

| Component | Image | Port | Purpose |
|---|---|---|---|
| lumia-app | `ndzenyuy/lumia-app` | 8080 | Java Spring MVC (WAR on Tomcat) |
| lumiadb | `ndzenyuy/lumia-db` | 3306 | MySQL 8.0.33 with pre-loaded schema |
| rmq01 | `rabbitmq:3.13-management` | 5672 / 15672 | RabbitMQ message queue |
| mc01 | `memcached:1.6-alpine` | 11211 | Memcached cache |

**Traffic flow:** Internet → AWS NLB → NGINX Ingress Controller → lumia-app-service:8080 → lumia-app pods

**Storage:** MySQL data persists in a PersistentVolumeClaim backed by AWS EBS gp2 (3Gi). The AWS EBS CSI driver is required for this to work.

---

## Prerequisites

### Required Tools

Install these on your workstation before starting:

```bash
# 1. AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install
aws --version

# 2. eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version

# 3. kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client

# 4. Helm 3
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

### AWS Requirements

- AWS CLI configured: `aws configure`
- IAM permissions to create EKS clusters, EC2 instances, EBS volumes, IAM roles, and Route53 records
- An EC2 key pair created in us-east-1 named `lumiatechs-eks-keys` (or update `eks-setup/eks-setup.sh` with your key name)

---

## Phase 1 — Create the EKS Cluster

```bash
# Verify your AWS credentials first
aws sts get-caller-identity

# Create the cluster (takes 15–20 minutes)
bash eks-setup/eks-setup.sh

# Configure kubectl to use the new cluster
aws eks update-kubeconfig --name lumiatechs-eks-cluster --region us-east-1

# Verify nodes are Ready
kubectl get nodes
```

**Expected output:**
```
NAME                          STATUS   ROLES    AGE   VERSION
ip-192-168-xx-xx.ec2...      Ready    <none>   2m    v1.35.x
ip-192-168-xx-xx.ec2...      Ready    <none>   2m    v1.35.x
```

---

## Phase 2 — Install Cluster Infrastructure

Both of these must be in place before deploying the application.

### 2a. NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml

# Wait until the controller pod is running
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Confirm a Load Balancer hostname has been assigned
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

The `EXTERNAL-IP` column will show an AWS NLB hostname — note this for later.

### 2b. AWS EBS CSI Driver

Required for the MySQL PersistentVolumeClaim to bind. Without it the database pod will stay in `Pending` forever.

```bash
bash eks-setup/install-ebs-csi.sh

# Verify the driver pods are running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

# Verify the gp2 storage class is available
kubectl get storageclass
```

---

## Phase 3 — Deploy the Application

### 3a. Create the namespace

```bash
kubectl create namespace lumiatech
kubectl config set-context --current --namespace=lumiatech
```

### 3b. Review / update values

Open `helm/lumiatech/values.yaml` and confirm the image tags and configuration:

```yaml
app:
  image: ndzenyuy/lumia-app:<tag>   # set by CI; use a specific SHA tag, not "latest"
  replicas: 2
  port: 8080

db:
  image: ndzenyuy/lumia-db:<tag>
  port: 3306
  name: accounts
  user: admin
  password: admin123                # stored in a Kubernetes Secret as base64
  storage: 3Gi
  storageClass: gp2

ingress:
  host: www.lumiatechs.com
  className: nginx
```

> **Note on the Secret:** The Helm template automatically base64-encodes `db.password` via `{{ .Values.db.password | b64enc }}`. The raw `kubedefs/secret.yaml` contains the hardcoded base64 value `YWRtaW4xMjM=` (= `admin123`). If you change the password, run `echo -n 'newpassword' | base64` and update accordingly.

### 3c. Validate the chart

```bash
helm lint helm/lumiatech
helm template lumiatech helm/lumiatech -n lumiatech   # preview rendered YAML
```

### 3d. Install

**Step 1 — Adopt any resources already in the namespace into the Helm release.**
This is required if any manifests were previously applied with `kubectl apply`. It is safe to run even if the namespace is empty.

```bash
for resource in deployment service configmap pvc secret ingress; do
  kubectl get $resource -n lumiatech -o name 2>/dev/null | while read name; do
    kubectl label $name -n lumiatech "app.kubernetes.io/managed-by=Helm" --overwrite
    kubectl annotate $name -n lumiatech \
      "meta.helm.sh/release-name=lumiatech" \
      "meta.helm.sh/release-namespace=lumiatech" --overwrite
  done
done
```

**Step 2 — Install the Helm release.**

```bash
helm install lumiatech helm/lumiatech -n lumiatech
```

**Step 3 — Watch the pods come up.**
The database starts first; the app init container waits for the DB DNS to resolve before the app pod starts.

```bash
kubectl get pods -n lumiatech -w
```

**Expected steady state (all pods `1/1 Running`):**
```
NAME                         READY   STATUS    RESTARTS   AGE
lumia-app-xxxxxxxxx-xxxxx    1/1     Running   0          3m
lumiadb-xxxxxxxxx-xxxxx      1/1     Running   0          3m
rmq01-xxxxxxxxx-xxxxx        1/1     Running   0          3m
mc01-xxxxxxxxx-xxxxx         1/1     Running   0          3m
```

> **Why the init container?** `lumia-app` has a busybox init container that loops on `nslookup lumiadb` until the database service DNS resolves. This prevents the app from crashing before MySQL is ready.

### 3e. Verify

```bash
kubectl get pods,svc,ingress -n lumiatech
kubectl describe ingress lumia-ingress -n lumiatech   # confirm ADDRESS is populated
```

---

## Phase 4 — Access the Application

### Option A: Quick local test (port-forward)

```bash
kubectl port-forward svc/lumia-app-service 8080:8080 -n lumiatech
# Open: http://localhost:8080
```

### Option B: Domain via /etc/hosts (demo / staging)

```bash
# Get the NLB hostname
LB=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Add to /etc/hosts: $LB www.lumiatechs.com"
```

**On Linux/Mac:** `sudo nano /etc/hosts`, add the line above.  
**On Windows:** Open `C:\Windows\System32\drivers\etc\hosts` as Administrator and add the line.

Then open `http://www.lumiatechs.com`.

### Option C: Route53 DNS (production)

For a real domain, use an **Alias A record** (not CNAME — Alias is free, faster, and can be used at the zone apex):

```bash
# Get your hosted zone ID
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='lumiatechs.com.'].Id" \
  --output text | cut -d'/' -f3)

# Get the NLB hostname
LB=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# ELB hosted zone IDs by region:
# us-east-1: Z35SXDOTRQ7X7K  |  us-east-2: Z3AADJGX6KTTL2
# us-west-1: Z368ELLRRE2KJ0  |  us-west-2: Z1H1FL5HABSF5
LB_ZONE="Z35SXDOTRQ7X7K"

aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"www.lumiatechs.com\",
        \"Type\": \"A\",
        \"AliasTarget\": {
          \"HostedZoneId\": \"$LB_ZONE\",
          \"DNSName\": \"$LB\",
          \"EvaluateTargetHealth\": false
        }
      }
    }]
  }"

# DNS propagation takes 2–10 minutes
nslookup www.lumiatechs.com
```

---

## Phase 5 — GitOps with ArgoCD (optional)

ArgoCD watches this repository and automatically syncs any commit to the cluster, enabling GitOps. The CI pipeline in the application repo updates `helm/lumiatech/values.yaml` with the new image SHA tag and commits here; ArgoCD then deploys the new version without any manual `helm upgrade`.

### Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expose the UI
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Get the server URL
export ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ArgoCD URL: https://$ARGOCD_SERVER"

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### Register the application

**Option A — CLI:**

```bash
# Install ArgoCD CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/

argocd login $ARGOCD_SERVER --username admin --password <password> --insecure

argocd app create lumiatech \
  --repo https://github.com/DevOps-Cloud-Mentorship/Project-4-Deploy-to-EKS-manifest.git \
  --path helm/lumiatech \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace lumiatech \
  --sync-policy automated \
  --auto-prune \
  --self-heal

argocd app get lumiatech
argocd app sync lumiatech   # force immediate sync if needed
```

**Option B — UI:**

Open `https://<ARGOCD_SERVER>`, log in with `admin` / `<password>`, click **+ New App** and fill in:

| Field | Value |
|---|---|
| Application Name | `lumiatech` |
| Project | `default` |
| Sync Policy | `Automatic` |
| Repository URL | `https://github.com/DevOps-Cloud-Mentorship/Project-4-Deploy-to-EKS-manifest.git` |
| Revision | `HEAD` |
| Path | `helm/lumiatech` |
| Cluster URL | `https://kubernetes.default.svc` |
| Namespace | `lumiatech` |

Click **Create**, then **Sync → Synchronize**.

---

## Phase 6 — Monitoring with Prometheus & Grafana (optional)

### Install kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

# Wait for all pods to be running
kubectl get pods -n monitoring -w
```

### Register the app as a Prometheus target

```bash
kubectl apply -f kubedefs/servicemonitor.yaml
```

This scrapes `/actuator/prometheus` on the lumia-app pods every 30 seconds. The endpoint is only available if the application image is built with Spring Boot Actuator + Micrometer.

### Access Grafana

```bash
kubectl patch svc prometheus-grafana -n monitoring -p '{"spec": {"type": "LoadBalancer"}}'
export GRAFANA=$(kubectl get svc prometheus-grafana -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Grafana: http://$GRAFANA"
# Username: admin  |  Password: admin123
```

**Useful dashboard IDs** (import via Grafana UI → **+** → **Import**):

| Dashboard | ID |
|---|---|
| Kubernetes cluster overview | `315` |
| Kubernetes pod metrics | `6417` |
| JVM / Micrometer | `4701` |
| Node Exporter Full | `1860` |

> **If Grafana shows "No data":** Go to **Connections → Data Sources → Prometheus** and confirm the URL is the internal cluster DNS `http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090`, not the external LoadBalancer hostname.

### Access Prometheus UI

```bash
kubectl patch svc prometheus-kube-prometheus-prometheus -n monitoring \
  -p '{"spec": {"type": "LoadBalancer"}}'
export PROM=$(kubectl get svc prometheus-kube-prometheus-prometheus -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Prometheus: http://$PROM:9090"
```

---

## Helm Operations Reference

```bash
# Upgrade after changing values.yaml or templates
helm upgrade lumiatech helm/lumiatech -n lumiatech

# Override image tag without editing values.yaml (used by CI)
helm upgrade lumiatech helm/lumiatech -n lumiatech \
  --set app.image=ndzenyuy/lumia-app:<new-tag>

# Roll back to the previous release
helm rollback lumiatech -n lumiatech

# List release history
helm history lumiatech -n lumiatech

# Uninstall
helm uninstall lumiatech -n lumiatech
```

---

## Troubleshooting

### PVC stays in `Pending`

The EBS CSI driver is not installed or the IAM role is missing.

```bash
# Check PVC status and events
kubectl describe pvc db-pv-claim -n lumiatech

# Verify EBS CSI driver pods are running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

# Re-run the installation script if missing
bash eks-setup/install-ebs-csi.sh

# Verify addon status
aws eks describe-addon --cluster-name lumiatechs-eks-cluster \
  --addon-name aws-ebs-csi-driver --region us-east-1
```

### App init container loops (`waiting for mydb`)

The `lumiadb` service or pod is not ready.

```bash
# Check DB pod status and events
kubectl get pods -l app=lumiadb -n lumiatech
kubectl describe pod -l app=lumiadb -n lumiatech

# Check DB logs
kubectl logs -l app=lumiadb -n lumiatech --tail=50

# Check init container logs on the app pod
APP_POD=$(kubectl get pods -l app=lumia-app -n lumiatech -o jsonpath='{.items[0].metadata.name}')
kubectl logs $APP_POD -c init-mydb -n lumiatech

# Check service endpoints (must show a pod IP, not <none>)
kubectl get endpoints lumiadb -n lumiatech
```

### `ImagePullBackOff`

The image tag in `values.yaml` does not exist in Docker Hub.

```bash
kubectl describe pod <pod-name> -n lumiatech | grep -A5 Events
# Confirm the image tag exists: docker pull ndzenyuy/lumia-app:<tag>
```

### App crashes with RabbitMQ / Memcached errors

The application requires MySQL, RabbitMQ, and Memcached. If you see errors like `Failed to check/redeclare auto-delete queue(s)` in the app logs, the message queue or cache is not deployed.

```bash
# Check all expected pods are running
kubectl get pods -n lumiatech

# RabbitMQ connectivity test
APP_POD=$(kubectl get pods -l app=lumia-app -n lumiatech -o jsonpath='{.items[0].metadata.name}')
kubectl exec $APP_POD -n lumiatech -- nc -zv rmq01 5672
kubectl exec $APP_POD -n lumiatech -- nc -zv mc01 11211

# Check RabbitMQ logs
kubectl logs -l app=rmq01 -n lumiatech
```

### Can't access `www.lumiatechs.com`

```bash
# 1. Confirm ingress has an ADDRESS
kubectl get ingress lumia-ingress -n lumiatech

# 2. Confirm NGINX controller has an external IP
kubectl get svc ingress-nginx-controller -n ingress-nginx

# 3. Test with the Host header directly against the LB (bypasses DNS)
LB=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -H "Host: www.lumiatechs.com" http://$LB

# 4. Test DNS resolution
nslookup www.lumiatechs.com
dig www.lumiatechs.com +short
```

### Wrong database password

```bash
# Check current secret value
kubectl get secret app-secret -n lumiatech \
  -o jsonpath='{.data.db-pass}' | base64 -d && echo
# Should output: admin123

# Fix if wrong
kubectl delete secret app-secret -n lumiatech
kubectl create secret generic app-secret \
  --from-literal=db-pass=admin123 -n lumiatech
kubectl rollout restart deployment lumiadb lumia-app -n lumiatech
```

### Connect directly to MySQL

```bash
DB_POD=$(kubectl get pods -l app=lumiadb -n lumiatech -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $DB_POD -n lumiatech -- mysql -uadmin -padmin123 -e "SHOW DATABASES;"
```

### General debug commands

```bash
# Stream all logs
kubectl logs -f deployment/lumia-app -n lumiatech
kubectl logs -f deployment/lumiadb -n lumiatech
kubectl logs -f deployment/rmq01 -n lumiatech

# Describe any pod for detailed events
kubectl describe pod <pod-name> -n lumiatech

# Check all events sorted by time
kubectl get events -n lumiatech --sort-by='.lastTimestamp'

# Shell into app pod
kubectl exec -it deployment/lumia-app -n lumiatech -- /bin/bash

# Check environment variables seen by the app
kubectl exec deployment/lumia-app -n lumiatech -- env | grep -E "DB_|RABBIT|MEMCACH"
```

---

## CI/CD Pipeline

The Jenkins pipeline in the application repository:

1. Builds the Maven WAR artifact
2. Builds Docker images tagged with the Git commit SHA (`ndzenyuy/lumia-app:<sha>`)
3. Pushes images to Docker Hub
4. Updates `helm/lumiatech/values.yaml` with the new image tags
5. Commits and pushes to this manifest repository

ArgoCD detects the new commit and syncs the Helm chart, triggering a rolling update in the cluster. **Always use SHA-tagged images in `values.yaml` — not `latest`** — so every deployment is traceable to a specific commit.

---

## Cleanup

```bash
# Remove the application
helm uninstall lumiatech -n lumiatech
kubectl delete namespace lumiatech

# Remove monitoring (if installed)
helm uninstall prometheus -n monitoring
kubectl delete namespace monitoring

# Remove ArgoCD (if installed)
kubectl delete namespace argocd

# Delete the EKS cluster (irreversible — costs stop immediately)
eksctl delete cluster --name lumiatechs-eks-cluster --region us-east-1
```
