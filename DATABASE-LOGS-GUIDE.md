# Database Connection Troubleshooting Guide

## Quick Commands to Get Logs

### 1. Get Database Pod Logs

```bash
# Get database pod name
kubectl get pods -l app=lumiadb

# View last 100 lines of logs
kubectl logs -l app=lumiadb --tail=100

# Follow logs in real-time
kubectl logs -f -l app=lumiadb

# Get logs from specific pod
DB_POD=$(kubectl get pods -l app=lumiadb -o jsonpath='{.items[0].metadata.name}')
kubectl logs $DB_POD --tail=100

# Get previous container logs (if pod restarted)
kubectl logs $DB_POD --previous
```

### 2. Get Application Pod Logs

```bash
# View application logs
kubectl logs -l app=lumia-app --tail=100

# Follow logs in real-time
kubectl logs -f -l app=lumia-app

# Get logs from specific pod
APP_POD=$(kubectl get pods -l app=lumia-app -o jsonpath='{.items[0].metadata.name}')
kubectl logs $APP_POD --tail=100

# Check init container logs
kubectl logs $APP_POD -c init-mydb
```

### 3. Get All Logs at Once

```bash
# Save to files
kubectl logs -l app=lumiadb --tail=200 > db-logs.txt
kubectl logs -l app=lumia-app --tail=200 > app-logs.txt

# View both
cat db-logs.txt
cat app-logs.txt
```

---

## Common Database Connection Issues

### Issue 1: Database Pod Not Ready

**Check:**
```bash
kubectl get pods -l app=lumiadb
kubectl describe pod -l app=lumiadb
```

**Look for:**
- Pod status should be `Running`
- Ready should be `1/1`
- Check Events section for errors

**Fix:**
```bash
# Check PVC is bound
kubectl get pvc db-pv-claim

# Check database logs for errors
kubectl logs -l app=lumiadb --tail=50
```

---

### Issue 2: Wrong Database Credentials

**Check:**
```bash
# Check secret
kubectl get secret app-secret -o jsonpath='{.data.db-pass}' | base64 -d
echo ""

# Should output: admin123
```

**Expected Configuration:**
- Password in secret: `admin123` (base64: `YWRtaW4xMjM=`)
- Password in Dockerfile: `admin123`

**Fix if wrong:**
```bash
# Update secret
kubectl delete secret app-secret
kubectl create secret generic app-secret --from-literal=db-pass=admin123

# Restart pods
kubectl rollout restart deployment lumiadb
kubectl rollout restart deployment lumia-app
```

---

### Issue 3: Database Service Not Working

**Check:**
```bash
# Check service
kubectl get svc lumiadb

# Check endpoints (should show pod IP)
kubectl get endpoints lumiadb

# Should show something like:
# NAME      ENDPOINTS         AGE
# lumiadb   10.0.1.123:3306   5m
```

**Fix:**
```bash
# If no endpoints, check pod labels
kubectl get pods -l app=lumiadb --show-labels

# Reapply service
kubectl apply -f kubedefs/dbservice.yaml
```

---

### Issue 4: Network Connectivity

**Test from Application Pod:**
```bash
# Get app pod name
APP_POD=$(kubectl get pods -l app=lumia-app -o jsonpath='{.items[0].metadata.name}')

# Test DNS resolution
kubectl exec $APP_POD -- nslookup lumiadb

# Test port connectivity
kubectl exec $APP_POD -- nc -zv lumiadb 3306

# Test with curl
kubectl exec $APP_POD -- curl -v telnet://lumiadb:3306
```

---

### Issue 5: Database Not Initialized

**Check Database Status:**
```bash
DB_POD=$(kubectl get pods -l app=lumiadb -o jsonpath='{.items[0].metadata.name}')

# Check if MySQL is running
kubectl exec $DB_POD -- ps aux | grep mysql

# Check if MySQL is listening on port 3306
kubectl exec $DB_POD -- netstat -tlnp | grep 3306

# Test MySQL connection
kubectl exec $DB_POD -- mysqladmin ping -h localhost -uroot -padmin123

# Connect to MySQL
kubectl exec -it $DB_POD -- mysql -uroot -padmin123 -e "SHOW DATABASES;"
```

---

## Step-by-Step Troubleshooting

### Step 1: Check Pod Status
```bash
kubectl get pods
```

**Expected:**
```
NAME                        READY   STATUS    RESTARTS   AGE
lumia-app-xxxxxxxxx-xxxxx   1/1     Running   0          5m
lumiadb-xxxxxxxxx-xxxxx     1/1     Running   0          5m
```

### Step 2: Check Database Logs
```bash
kubectl logs -l app=lumiadb --tail=50
```

**Look for:**
- ✅ `mysqld: ready for connections` - Database is ready
- ❌ `Access denied` - Password issue
- ❌ `Can't start server` - Configuration issue
- ❌ `lost+found` error - Init container issue

### Step 3: Check Application Logs
```bash
kubectl logs -l app=lumia-app --tail=50
```

**Look for:**
- ❌ `Connection refused` - Database not ready or service issue
- ❌ `Unknown host` - DNS/Service issue
- ❌ `Access denied` - Wrong credentials
- ❌ `Communications link failure` - Network issue

### Step 4: Check Environment Variables
```bash
APP_POD=$(kubectl get pods -l app=lumia-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec $APP_POD -- env | grep DB_
```

**Expected:**
```
DB_HOST=lumiadb
DB_PORT=3306
DB_NAME=accounts
DB_USER=admin
DB_PASS=admin123
```

### Step 5: Test Database Connection
```bash
DB_POD=$(kubectl get pods -l app=lumiadb -o jsonpath='{.items[0].metadata.name}')

# Test MySQL is accessible
kubectl exec $DB_POD -- mysql -uadmin -padmin123 -e "SELECT 1;"

# Check if accounts database exists
kubectl exec $DB_POD -- mysql -uadmin -padmin123 -e "SHOW DATABASES;"

# Check tables in accounts database
kubectl exec $DB_POD -- mysql -uadmin -padmin123 accounts -e "SHOW TABLES;"
```

---

## Automated Troubleshooting Script

Run the comprehensive troubleshooting script:

```bash
chmod +x eks-setup/troubleshoot-db-connection.sh
./eks-setup/troubleshoot-db-connection.sh
```

This will check:
1. Pod status
2. Database logs
3. Application logs
4. Service connectivity
5. DNS resolution
6. Port connectivity
7. Environment variables
8. PVC status
9. Secret configuration

---

## Common Fixes

### Fix 1: Restart Pods
```bash
kubectl rollout restart deployment lumiadb
kubectl rollout restart deployment lumia-app
```

### Fix 2: Check Init Container
```bash
# The app has an init container that waits for database
APP_POD=$(kubectl get pods -l app=lumia-app -o jsonpath='{.items[0].metadata.name}')
kubectl logs $APP_POD -c init-mydb
```

### Fix 3: Verify Database User
```bash
DB_POD=$(kubectl get pods -l app=lumiadb -o jsonpath='{.items[0].metadata.name}')

# Create user if doesn't exist
kubectl exec $DB_POD -- mysql -uroot -padmin123 -e "
CREATE USER IF NOT EXISTS 'admin'@'%' IDENTIFIED BY 'admin123';
GRANT ALL PRIVILEGES ON accounts.* TO 'admin'@'%';
FLUSH PRIVILEGES;
"
```

### Fix 4: Check Database Initialization
```bash
DB_POD=$(kubectl get pods -l app=lumiadb -o jsonpath='{.items[0].metadata.name}')

# Check if database was initialized
kubectl exec $DB_POD -- ls -la /var/lib/mysql/

# Check init script was executed
kubectl exec $DB_POD -- ls -la /docker-entrypoint-initdb.d/
```

---

## Real-Time Monitoring

### Watch Logs Live
```bash
# Terminal 1: Watch database logs
kubectl logs -f -l app=lumiadb

# Terminal 2: Watch application logs
kubectl logs -f -l app=lumia-app

# Terminal 3: Watch pod status
watch kubectl get pods
```

### Stream All Logs
```bash
# Install stern (optional)
# brew install stern  # Mac
# or download from: https://github.com/stern/stern

# Stream all logs
stern "lumia.*"
```

---

## Get Detailed Pod Information

```bash
# Database pod details
kubectl describe pod -l app=lumiadb

# Application pod details
kubectl describe pod -l app=lumia-app

# Check events
kubectl get events --sort-by='.lastTimestamp' | grep -E "lumia|db"
```

---

## Export Logs for Analysis

```bash
# Create logs directory
mkdir -p logs

# Export all logs
kubectl logs -l app=lumiadb --tail=500 > logs/database-logs.txt
kubectl logs -l app=lumia-app --tail=500 > logs/application-logs.txt
kubectl describe pod -l app=lumiadb > logs/database-pod-details.txt
kubectl describe pod -l app=lumia-app > logs/application-pod-details.txt
kubectl get events --sort-by='.lastTimestamp' > logs/cluster-events.txt

echo "Logs exported to logs/ directory"
ls -lh logs/
```
