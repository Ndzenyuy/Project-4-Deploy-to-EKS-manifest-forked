# lumiatech Java Application - Kubernetes Deployment

## Overview

This project deploys a Java web application (lumiatech) to a Kubernetes cluster using a GitOps approach with two separate repositories:

- **Application Repository**: Contains source code, Dockerfile, and CI/CD pipeline
- **Manifest Repository**: Contains Kubernetes manifests and Helm charts for deployment

## Architecture

![Kubernetes Architecture Diagram](./images/project-4-deploy-to-eks.png)

- **Application**: Java Spring MVC application (WAR file)
- **Database**: MySQL
- **Orchestration**: Kubernetes
- **Deployment Tool**: Helm
- **Ingress**: NGINX Ingress Controller

## Prerequisites

- Kubernetes cluster (v1.35)
- kubectl configured
- Helm 3.x installed
- Docker registry access
- NGINX Ingress Controller installed in cluster

## Repository Structure

### Application Repository

```
lumiatech-app/
├── src/                    # Java source code
├── pom.xml                 # Maven build configuration
├── Dockerfile              # Container image definition
├── Jenkinsfile             # CI/CD pipeline
└── README.md
```

### Manifest Repository

```
lumiatech-manifests/
├── helm/
│   └── lumiatech/
│       ├── Chart.yaml          # Chart metadata
│       ├── values.yaml         # Default values
│       └── templates/          # Kubernetes manifest templates
│           ├── appdeploy.yaml
│           ├── appservice.yaml
│           ├── appingress.yaml
│           ├── dbdeploy.yaml
│           ├── dbservice.yaml
│           ├── dbpvc.yaml
│           └── secret.yaml
├── kubedefs/
│   ├── appdeploy.yaml      # Application deployment
│   ├── appservice.yaml     # Application service
│   ├── appingress.yaml     # NGINX ingress
│   ├── dbdeploy.yaml       # Database deployment
│   ├── dbservice.yaml      # Database service
│   ├── dbpvc.yaml          # Persistent volume claim
│   └── secret.yaml         # Application secrets
└── README.md
```

## Deployment Components

### Application Deployment

- **Image**: `ndzenyuy/lumia-app:latest`
- **Port**: 8080
- **Init Containers**: Wait for database service
- **Service Type**: ClusterIP
- **Environment Variables**: Database connection details

### Database Deployment

- **Image**: `ndzenyuy/lumia-db:latest`
- **Port**: 3306
- **Storage**: PersistentVolumeClaim (3Gi, gp2 storage class)
- **Credentials**: Stored in Kubernetes Secret

### Ingress

- **Host**: `www.lumiatechs.com`
- **Path**: `/`
- **Backend**: lumia-app-service:8080

## Docker Images Build and Push

### Prerequisites for Building Images

- Docker installed and running
- Docker Hub account
- Maven 3.6+ installed
- Java 17+ installed

### Build and Push Process

The application source code is located in the `src/` folder and uses Maven for building.

#### Option 1: Automated Script (Recommended)

```bash
# Make script executable
chmod +x build-and-push.sh

# Run the build and push script
./build-and-push.sh
```

#### Option 2: Manual Steps

```bash
# 1. Login to Docker Hub
docker login

# 2. Build Java application (source code in src/ folder)
mvn clean install -DskipTests

# 3. Build application Docker image
docker build -t ndzenyuy/lumia-app:latest -f Docker-files/app/Dockerfile .

# 4. Build database Docker image
docker build -t ndzenyuy/lumia-db:latest -f Docker-files/db/Dockerfile Docker-files/db/

# 5. Push images to Docker Hub
docker push ndzenyuy/lumia-app:latest
docker push ndzenyuy/lumia-db:latest

# 6. Verify images
docker images | grep -E "(lumia-app|lumia-db)"
```

### Image Details

- **Application Image**: Built from Java source code in `src/` folder using Maven
- **Database Image**: MySQL 8.0.33 with pre-loaded database schema
- **Build Context**: Application builds from project root to access `target/` directory

### Docker Hub Images

- **Application**: `ndzenyuy/lumia-app:latest`
- **Database**: `ndzenyuy/lumia-db:latest`

## AWS EKS Cluster Setup

### Prerequisites

- AWS CLI configured with appropriate credentials
- IAM permissions to create EKS clusters and related resources

### Install Required Tools

```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installations
kubectl version --client
eksctl version
helm version
```

### Create EKS Cluster

```bash
# Create EKS cluster
eksctl create cluster \
  --name lumiatech-cluster \
  --region us-east-1 \
  --nodegroup-name lumiatech-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed

# Configure kubectl context
aws eks update-kubeconfig --region us-east-1 --name lumiatech-cluster
```

### Install NGINX Ingress Controller

```bash
# Deploy NGINX Ingress Controller for AWS
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml

# Wait for ingress controller to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

### Verify Cluster

```bash
# Check cluster status
kubectl cluster-info

# Check nodes
kubectl get nodes

# Check system pods
kubectl get pods -n kube-system

# Check ingress controller
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

# Get ingress load balancer URL
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## Deployment Steps

### 1. Clone Repositories

```bash
# Application repository
git clone https://github.com/DevOps-Cloud-Mentorship/Project-4-Deploy-to-EKS-app.git

# Manifest repository
git clone https://github.com/DevOps-Cloud-Mentorship/Project-4-Deploy-to-EKS-manifest.git
```

### 2. Create Namespace

```bash
kubectl create namespace lumiatech
kubectl config set-context --current --namespace=lumiatech
```

### 3. Create Helm Chart

#### Create the chart structure

```bash
mkdir -p helm/lumiatech/templates
```

#### Create `helm/lumiatech/Chart.yaml`

```yaml
apiVersion: v2
name: lumiatech
description: Lumiatech Java application with MySQL
type: application
version: 1.0.0
appVersion: "latest"
```

#### Create `helm/lumiatech/values.yaml`

```yaml
app:
  image: ndzenyuy/lumia-app:latest
  replicas: 1
  port: 8080

db:
  image: ndzenyuy/lumia-db:latest
  port: 3306
  name: accounts
  user: admin
  password: admin123
  storage: 3Gi
  storageClass: gp2

ingress:
  host: www.lumiatechs.com
  className: nginx
```

#### Copy manifests into templates

```bash
cp kubedefs/*.yaml helm/lumiatech/templates/
```

#### Templatize `helm/lumiatech/templates/secret.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
data:
  db-pass: {{ .Values.db.password | b64enc }}
```

#### Templatize `helm/lumiatech/templates/appdeploy.yaml`

Replace hardcoded values with template variables:

```yaml
spec:
  replicas: {{ .Values.app.replicas }}
  ...
  containers:
  - name: lumia-app
    image: {{ .Values.app.image }}
    env:
    - name: DB_PORT
      value: "{{ .Values.db.port }}"
    - name: DB_NAME
      value: "{{ .Values.db.name }}"
    - name: DB_USER
      value: "{{ .Values.db.user }}"
    - name: DB_PASS
      valueFrom:
        secretKeyRef:
          name: app-secret
          key: db-pass
```

#### Templatize `helm/lumiatech/templates/dbpvc.yaml`

```yaml
spec:
  storageClassName: {{ .Values.db.storageClass }}
  resources:
    requests:
      storage: {{ .Values.db.storage }}
```

#### Templatize `helm/lumiatech/templates/appingress.yaml`

```yaml
spec:
  ingressClassName: {{ .Values.ingress.className }}
  rules:
  - host: {{ .Values.ingress.host }}
```

#### Validate the chart before deploying

```bash
# Lint the chart for errors
helm lint helm/lumiatech

# Preview rendered templates without deploying
helm template lumiatech helm/lumiatech -n lumiatech
```

### 4. Deploy Using Helm

```bash
# Install the chart
helm install lumiatech helm/lumiatech -n lumiatech --create-namespace

# Verify the release
helm list -n lumiatech
```

#### Upgrade after changes

```bash
helm upgrade lumiatech helm/lumiatech -n lumiatech
```

#### Override a value without editing values.yaml

```bash
helm upgrade lumiatech helm/lumiatech -n lumiatech \
  --set app.image=ndzenyuy/lumia-app:v2.0
```

#### Rollback to a previous release

```bash
helm rollback lumiatech -n lumiatech
```

#### Uninstall

```bash
helm uninstall lumiatech -n lumiatech
```

### 5. Verify Deployment

```bash
kubectl get pods -n lumiatech
kubectl get svc -n lumiatech
kubectl get ingress -n lumiatech
```

### 6. Access Application

```bash
# Get ingress load balancer URL
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Update /etc/hosts or DNS
echo "<INGRESS_LB_URL> www.lumiatechs.com" >> /etc/hosts

# Access via browser
http://www.lumiatechs.com
```

### 7. Configure ArgoCD

#### Update kubeconfig

```bash
aws eks update-kubeconfig --name lumiatech-cluster --region us-east-1
```

#### Install ArgoCD on the cluster

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

#### Verify installation

```bash
kubectl get all -n argocd
```

#### Expose ArgoCD

```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

#### Get ArgoCD server DNS

```bash
export ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname')
echo $ARGOCD_SERVER
```

#### Get ArgoCD admin password

```bash
export ARGO_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo $ARGO_PWD
```

#### Login to ArgoCD UI

Open your browser and navigate to:
```
https://<ARGOCD_SERVER>
```

- **Username**: `admin`
- **Password**: value of `$ARGO_PWD`

#### Create ArgoCD Application pointing to Helm chart

**Option 1: Via CLI**

```bash
# Install ArgoCD CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/

# Login
argocd login $ARGOCD_SERVER --username admin --password $ARGO_PWD --insecure

# Create the app using the Helm chart path
argocd app create lumiatech \
  --repo https://github.com/DevOps-Cloud-Mentorship/Project-4-Deploy-to-EKS-manifest.git \
  --path helm/lumiatech \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace lumiatech \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# Verify the app
argocd app get lumiatech

# Sync manually if needed
argocd app sync lumiatech
```

**Option 2: Via UI**

1. Click **+ New App**
2. Fill in the form:

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

3. Click **Create**
4. Click **Sync** → **Synchronize**

#### Delete cluster

```bash
eksctl delete cluster --name lumiatech-cluster --region us-east-1
```


## CI/CD Pipeline

### Build & Push

1. Maven builds WAR file
2. Docker builds container image
3. Image pushed to registry
4. Trigger manifest repository update

### Deploy

1. Update image tag in values.yaml
2. Commit to manifest repository
3. Helm upgrade deployment
4. Kubernetes rolls out new version

## Configuration

### Secrets

Update `secret.yaml` with base64 encoded values:

```bash
echo -n 'your-password' | base64
```

### Environment Variables

- `DB_HOST`: Database service name (lumiadb)
- `DB_PORT`: Database port (3306)
- `DB_NAME`: Database name (accounts)
- `DB_USER`: Database user (root)
- `DB_PASS`: Database password (from secret)
- `MYSQL_ROOT_PASSWORD`: Database root password (from secret)

### Persistent Storage

- Database uses PVC for data persistence
- Storage class: gp2 (AWS EBS)
- Storage size: 3Gi

### Docker Images

- **Application**: `ndzenyuy/lumia-app:latest`
- **Database**: `ndzenyuy/lumia-db:latest`

### Ingress Configuration

- **Domain**: www.lumiatechs.com
- **Ingress Controller**: NGINX
- **Backend Service**: lumia-app-service:8080

## Monitoring & Troubleshooting

### Install Prometheus & Grafana

#### Add Helm repository

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

#### Install kube-prometheus-stack

```bash
kubectl create namespace monitoring

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

#### Verify installation

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

#### Access Grafana

```bash
kubectl patch svc prometheus-grafana -n monitoring -p '{"spec": {"type": "LoadBalancer"}}'

# Wait for external hostname
kubectl get svc prometheus-grafana -n monitoring -w

# Get the URL
export GRAFANA_URL=$(kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "http://$GRAFANA_URL"
```

Open `http://<GRAFANA_URL>` in your browser.

- **Username**: `admin`
- **Password**: `admin123`

#### Access Prometheus UI

```bash
kubectl patch svc prometheus-kube-prometheus-prometheus -n monitoring -p '{"spec": {"type": "LoadBalancer"}}'

# Get the URL
export PROMETHEUS_URL=$(kubectl get svc prometheus-kube-prometheus-prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "http://$PROMETHEUS_URL:9090"
```

Open `http://<PROMETHEUS_URL>:9090` in your browser.

#### Configure ServiceMonitor for lumiatech app

Create `kubedefs/servicemonitor.yaml` to scrape app metrics:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: lumiatech-monitor
  namespace: monitoring
  labels:
    release: prometheus
spec:
  namespaceSelector:
    matchNames:
      - lumiatech
  selector:
    matchLabels:
      app: lumia-app
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 30s
```

```bash
kubectl apply -f kubedefs/servicemonitor.yaml
```

#### Verify Prometheus datasource in Grafana

The `kube-prometheus-stack` chart automatically configures Prometheus as a datasource in Grafana. To verify:

1. Login to Grafana
2. Go to **Connections** → **Data Sources**
3. Confirm `Prometheus` is listed and its status shows **Data source connected and labels found**

If the datasource is missing or shows **No data**, add/fix it manually:

1. Click **Add data source** → select **Prometheus**
2. Set URL to the in-cluster DNS name:
   ```
   http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090
   ```
3. Click **Save & Test** — you should see **Data source connected and labels found**

#### Troubleshoot: No data in Grafana dashboards

If dashboards show **No data**, run through these checks:

```bash
# 1. Confirm Prometheus pods are running
kubectl get pods -n monitoring

# 2. Confirm Prometheus is scraping targets
# Open Prometheus UI → Status → Targets — all targets should be UP
echo "http://$PROMETHEUS_URL:9090/targets"

# 3. Check Prometheus has data by running a test query in the UI
# Go to http://$PROMETHEUS_URL:9090 → Graph → run:
# up
# node_cpu_seconds_total

# 4. Verify the datasource URL in Grafana is the internal cluster DNS
# Connections → Data Sources → Prometheus → URL should be:
# http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090

# 5. Check Grafana can reach Prometheus
kubectl exec -n monitoring deploy/prometheus-grafana -- \
  wget -qO- http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090/-/healthy

# 6. Check for scrape config issues
kubectl logs -n monitoring -l app=prometheus --container prometheus | tail -50
```

Common causes:
- **Datasource URL wrong**: Must use the internal cluster DNS, not the external LoadBalancer hostname
- **Time range too narrow**: Set Grafana time range to **Last 1 hour** or wider
- **Wrong dashboard variables**: On imported dashboards, check the `datasource` dropdown at the top is set to `Prometheus`
- **No metrics endpoint on app**: The JVM dashboard (ID `4701`) requires Spring Boot Actuator with Micrometer — only works if your app exposes `/actuator/prometheus`

#### Useful Grafana dashboards

Import these dashboards via Grafana UI (**+** → **Import** → enter ID):

| Dashboard | ID |
|---|---|
| Kubernetes cluster overview | `315` |
| Kubernetes pod metrics | `6417` |
| JVM (Micrometer) | `4701` |
| Node Exporter Full | `1860` |

#### Upgrade or change Grafana password

```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=<new-password>
```

#### Uninstall

```bash
helm uninstall prometheus -n monitoring
kubectl delete namespace monitoring
```

### Check Logs

```bash
kubectl logs -f deployment/lumia-app -n lumiatech
kubectl logs -f deployment/lumiadb -n lumiatech
```

### Debug Pods

```bash
kubectl describe pod <pod-name> -n lumiatech
kubectl exec -it <pod-name> -n lumiatech -- /bin/bash
```

### Common Issues

- **Init containers stuck**: Check service DNS resolution
- **ImagePullBackOff**: Verify registry credentials
- **CrashLoopBackOff**: Check application logs and database connectivity

## Cleanup

```bash
# Delete all resources
kubectl delete -f kubedefs/

# Delete namespace
kubectl delete namespace lumiatech

# Delete EKS cluster (optional)
eksctl delete cluster --name lumiatech-cluster --region us-east-1
```

## Security Considerations

- Secrets stored in Kubernetes Secret (consider using Sealed Secrets or External Secrets Operator)
- Use private container registry
- Implement RBAC policies
- Enable network policies
- Regular security scanning of images

## Future Enhancements

- Add Horizontal Pod Autoscaler (HPA)
- ~~Implement monitoring with Prometheus/Grafana~~ ✅ Done
- Add centralized logging with ELK/EFK stack
- Implement GitOps with ArgoCD/FluxCD
- Add health checks and readiness probes
- Implement blue-green or canary deployments
