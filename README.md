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
git clone <app-repo-url>

# Manifest repository
git clone <manifest-repo-url>
```

### 2. Create Namespace

```bash
kubectl create namespace lumiatech
kubectl config set-context --current --namespace=lumiatech
```

### 3. Deploy Using Kubectl

```bash
cd kubedefs

# Deploy in order
kubectl apply -f secret.yaml
kubectl apply -f dbpvc.yaml
kubectl apply -f dbdeploy.yaml
kubectl apply -f dbservice.yaml
kubectl apply -f appdeploy.yaml
kubectl apply -f appservice.yaml
kubectl apply -f appingress.yaml

# Or deploy all at once
kubectl apply -f .
```

### 4. Verify Deployment

```bash
kubectl get pods -n lumiatech
kubectl get svc -n lumiatech
kubectl get ingress -n lumiatech
```

### 5. Access Application

```bash
# Get ingress load balancer URL
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Update /etc/hosts or DNS
echo "<INGRESS_LB_URL> www.lumiatechs.com" >> /etc/hosts

# Access via browser
http://www.lumiatechs.com
```

# Delete cluster
```bash
eksctl delete cluster --name lumiatech-cluster --region us-east-2
```
## Install argoCD on the cluster
```bash
 kubectl create namespace argocd
 kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
 ```
## Verify installation
```bash
kubectl get all -n argocd
```
## Expose argocd
```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```
## Export argocd dns
```bash
export ARGOCD_SERVER=`kubectl get svc argocd-server -n argocd -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname'`
```
Get the argocd dns
echo $ARGOCD_SERVER
export argocd password
export ARGO_PWD=`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
get the argocd PASSWORD
echo $ARGO_PWD


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
- Implement monitoring with Prometheus/Grafana
- Add centralized logging with ELK/EFK stack
- Implement GitOps with ArgoCD/FluxCD
- Add health checks and readiness probes
- Implement blue-green or canary deployments
