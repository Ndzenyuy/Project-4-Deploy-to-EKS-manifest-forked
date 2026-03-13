# Missing Services Fix - RabbitMQ & Memcached

## Problem Identified

Your application logs show errors about **RabbitMQ** connection failures:
```
ERROR org.springframework.amqp.rabbit.listener.SimpleMessageListenerContainer - Failed to check/redeclare auto-delete queue(s).
```

This is because your application requires **3 backend services**, but only **MySQL** was deployed:

1. ✅ **MySQL** (Database) - Deployed
2. ❌ **RabbitMQ** (Message Queue) - **MISSING**
3. ❌ **Memcached** (Cache) - **MISSING**

## Solution: Deploy Missing Services

### Quick Fix - Deploy Everything

```bash
# Make script executable
chmod +x eks-setup/deploy-complete-stack.sh

# Deploy all services
./eks-setup/deploy-complete-stack.sh
```

This will deploy:
- MySQL database
- RabbitMQ message queue
- Memcached cache
- Application with proper configuration

---

### Manual Deployment Steps

If you prefer to deploy manually:

#### Step 1: Deploy RabbitMQ

```bash
# Deploy RabbitMQ service and deployment
kubectl apply -f kubedefs/rmqservice.yaml
kubectl apply -f kubedefs/rmqdeploy.yaml

# Verify RabbitMQ is running
kubectl get pods -l app=rmq01
kubectl logs -l app=rmq01
```

#### Step 2: Deploy Memcached

```bash
# Deploy Memcached service and deployment
kubectl apply -f kubedefs/mcservice.yaml
kubectl apply -f kubedefs/mcdeploy.yaml

# Verify Memcached is running
kubectl get pods -l app=mc01
kubectl logs -l app=mc01
```

#### Step 3: Update Application Deployment

```bash
# Apply updated app deployment with RabbitMQ and Memcached env vars
kubectl apply -f kubedefs/appdeploy.yaml

# Restart application to pick up new configuration
kubectl rollout restart deployment lumia-app
```

#### Step 4: Verify All Services

```bash
# Check all pods
kubectl get pods

# Should see:
# lumiadb-xxx        1/1  Running
# rmq01-xxx          1/1  Running
# mc01-xxx           1/1  Running
# lumia-app-xxx      1/1  Running
```

---

## Service Details

### RabbitMQ Configuration

**Service Name:** `rmq01`
**Port:** `5672` (AMQP), `15672` (Management UI)
**Credentials:**
- Username: `test`
- Password: `test`

**Image:** `rabbitmq:3.13-management`

### Memcached Configuration

**Service Name:** `mc01`
**Port:** `11211`
**Image:** `memcached:1.6-alpine`

### MySQL Configuration

**Service Name:** `lumiadb`
**Port:** `3306`
**Credentials:**
- Username: `admin`
- Password: `admin123`
- Database: `accounts`

---

## Application Configuration

The application expects these environment variables (now configured):

```yaml
# Database
DB_HOST: lumiadb
DB_PORT: 3306
DB_NAME: accounts
DB_USER: admin
DB_PASS: admin123

# RabbitMQ
RABBITMQ_HOST: rmq01
RABBITMQ_PORT: 5672
RABBITMQ_USERNAME: test
RABBITMQ_PASSWORD: test

# Memcached
MEMCACHED_HOST: mc01
MEMCACHED_PORT: 11211
```

---

## Verification Commands

### Check All Services Are Running

```bash
# Check pods
kubectl get pods

# Check services
kubectl get svc

# Check endpoints (should show IPs for all services)
kubectl get endpoints
```

### Test Service Connectivity

```bash
# Get app pod name
APP_POD=$(kubectl get pods -l app=lumia-app -o jsonpath='{.items[0].metadata.name}')

# Test database connectivity
kubectl exec $APP_POD -- nc -zv lumiadb 3306

# Test RabbitMQ connectivity
kubectl exec $APP_POD -- nc -zv rmq01 5672

# Test Memcached connectivity
kubectl exec $APP_POD -- nc -zv mc01 11211
```

### Check Application Logs

```bash
# View application logs (should no longer show RabbitMQ errors)
kubectl logs -l app=lumia-app --tail=50

# Follow logs in real-time
kubectl logs -f -l app=lumia-app
```

### Check RabbitMQ Status

```bash
# View RabbitMQ logs
kubectl logs -l app=rmq01

# Access RabbitMQ Management UI (optional)
kubectl port-forward svc/rmq01 15672:15672
# Then open: http://localhost:15672
# Login: test / test
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│           NGINX Ingress Controller          │
│         (Load Balancer Frontend)            │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│         Lumia Application (Java)            │
│              Port: 8080                     │
└──┬────────────┬────────────┬────────────────┘
   │            │            │
   ▼            ▼            ▼
┌──────┐   ┌─────────┐   ┌──────────┐
│MySQL │   │RabbitMQ │   │Memcached │
│:3306 │   │:5672    │   │:11211    │
└──────┘   └─────────┘   └──────────┘
```

---

## Troubleshooting

### Issue: RabbitMQ Pod Not Starting

```bash
# Check pod status
kubectl describe pod -l app=rmq01

# Check logs
kubectl logs -l app=rmq01

# Common fix: Restart pod
kubectl delete pod -l app=rmq01
```

### Issue: Application Still Shows Errors

```bash
# Restart application after backend services are ready
kubectl rollout restart deployment lumia-app

# Wait for new pod to start
kubectl get pods -w
```

### Issue: Services Can't Communicate

```bash
# Check DNS resolution
APP_POD=$(kubectl get pods -l app=lumia-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec $APP_POD -- nslookup rmq01
kubectl exec $APP_POD -- nslookup mc01
kubectl exec $APP_POD -- nslookup lumiadb

# Check service endpoints
kubectl get endpoints
```

---

## Files Created

1. **kubedefs/rmqdeploy.yaml** - RabbitMQ deployment
2. **kubedefs/rmqservice.yaml** - RabbitMQ service
3. **kubedefs/mcdeploy.yaml** - Memcached deployment
4. **kubedefs/mcservice.yaml** - Memcached service
5. **kubedefs/appdeploy.yaml** - Updated with env vars
6. **eks-setup/deploy-complete-stack.sh** - Complete deployment script

---

## Expected Result

After deploying all services, you should see:

```bash
$ kubectl get pods
NAME                         READY   STATUS    RESTARTS   AGE
lumia-app-xxxxxxxxx-xxxxx    1/1     Running   0          2m
lumiadb-xxxxxxxxx-xxxxx      1/1     Running   0          5m
mc01-xxxxxxxxx-xxxxx         1/1     Running   0          3m
rmq01-xxxxxxxxx-xxxxx        1/1     Running   0          3m
```

And application logs should show successful connections:
```
✅ Connected to MySQL database
✅ Connected to RabbitMQ
✅ Connected to Memcached
```

---

## Clean Deployment (If Needed)

If you want to start fresh:

```bash
# Delete all resources
kubectl delete -f kubedefs/

# Wait for cleanup
kubectl get pods

# Redeploy everything
./eks-setup/deploy-complete-stack.sh
```
