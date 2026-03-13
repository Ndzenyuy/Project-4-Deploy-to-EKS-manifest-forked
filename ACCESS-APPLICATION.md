# How to Access the Application from Browser

## Option 1: Using Ingress with Domain Name (Recommended for Production)

### Step 1: Get the Load Balancer URL

```bash
# Get the NGINX Ingress Controller Load Balancer URL
kubectl get svc ingress-nginx-controller -n ingress-nginx

# Or get just the hostname
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

**Expected Output:**
```
a1234567890abcdef-1234567890.us-east-1.elb.amazonaws.com
```

### Step 2: Update Your Hosts File (For Testing)

**On Windows:**
```cmd
# Open Notepad as Administrator
notepad C:\Windows\System32\drivers\etc\hosts

# Add this line (replace with your actual LB URL):
<LOAD_BALANCER_URL> www.lumiatechs.com
```

**On Linux/Mac:**
```bash
# Edit hosts file
sudo nano /etc/hosts

# Add this line (replace with your actual LB URL):
<LOAD_BALANCER_URL> www.lumiatechs.com
```

### Step 3: Access the Application

Open your browser and go to:
```
http://www.lumiatechs.com
```

---

## Option 2: Direct Access via Load Balancer (Quick Testing)

If you want to skip the domain name setup:

### Step 1: Get Load Balancer URL
```bash
export LB_URL=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Access your app at: http://$LB_URL"
```

### Step 2: Modify Ingress to Accept Any Host

```bash
# Temporarily remove host restriction
kubectl patch ingress lumia-ingress -p '{"spec":{"rules":[{"http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"lumia-app-service","port":{"number":8080}}}}]}}]}}'
```

### Step 3: Access Directly
```
http://<LOAD_BALANCER_URL>
```

---

## Option 3: Using LoadBalancer Service (Simplest for Testing)

### Step 1: Change App Service to LoadBalancer Type

```bash
# Patch the service
kubectl patch svc lumia-app-service -p '{"spec":{"type":"LoadBalancer"}}'

# Wait for external IP
kubectl get svc lumia-app-service -w
```

### Step 2: Get the Service URL
```bash
kubectl get svc lumia-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Step 3: Access the Application
```
http://<SERVICE_LOAD_BALANCER_URL>:8080
```

---

## Option 4: Using Port Forward (Local Testing Only)

For quick local testing without Load Balancer:

```bash
# Forward port 8080 from the pod to your local machine
kubectl port-forward svc/lumia-app-service 8080:8080

# Access from browser
http://localhost:8080
```

**Note:** Keep the terminal open while testing.

---

## Option 5: Production Setup with Route53 (Real Domain)

If you own a domain:

### Step 1: Get Load Balancer URL
```bash
LB_URL=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $LB_URL
```

### Step 2: Create Route53 Record

**Using AWS Console:**
1. Go to Route53 → Hosted Zones
2. Select your domain
3. Create Record:
   - Record name: `www`
   - Record type: `CNAME` or `A (Alias)`
   - Value: `<LOAD_BALANCER_URL>`
   - TTL: 300

**Using AWS CLI:**
```bash
# For CNAME record
aws route53 change-resource-record-sets \
  --hosted-zone-id <YOUR_ZONE_ID> \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "www.lumiatechs.com",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'$LB_URL'"}]
      }
    }]
  }'
```

### Step 3: Wait for DNS Propagation (5-10 minutes)
```bash
# Check DNS resolution
nslookup www.lumiatechs.com
```

### Step 4: Access Your Application
```
http://www.lumiatechs.com
```

---

## Verification Commands

### Check if everything is running:
```bash
# Check pods
kubectl get pods

# Check services
kubectl get svc

# Check ingress
kubectl get ingress

# Check ingress details
kubectl describe ingress lumia-ingress

# Check app logs
kubectl logs -l app=lumia-app --tail=50

# Check database connectivity
kubectl exec -it deployment/lumia-app -- curl -v http://lumiadb:3306
```

### Test from within the cluster:
```bash
# Test service connectivity
kubectl run test-pod --image=busybox --rm -it --restart=Never -- wget -O- http://lumia-app-service:8080

# Test database connectivity
kubectl run test-db --image=mysql:8.0.33 --rm -it --restart=Never -- mysql -h lumiadb -uadmin -padmin123 -e "SHOW DATABASES;"
```

---

## Troubleshooting

### Issue: Can't access the application

**Check 1: Is the Load Balancer ready?**
```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
# STATUS should show EXTERNAL-IP (not <pending>)
```

**Check 2: Are pods running?**
```bash
kubectl get pods
# All pods should be Running
```

**Check 3: Check ingress status**
```bash
kubectl describe ingress lumia-ingress
# Should show ADDRESS field with Load Balancer URL
```

**Check 4: Check app logs**
```bash
kubectl logs -l app=lumia-app --tail=100
# Look for errors
```

**Check 5: Test service directly**
```bash
kubectl port-forward svc/lumia-app-service 8080:8080
# Then access http://localhost:8080
```

### Issue: 502 Bad Gateway

- App pod is not ready
- Database connection failed
- Check logs: `kubectl logs -l app=lumia-app`

### Issue: 404 Not Found

- Ingress path configuration issue
- Service name mismatch
- Check: `kubectl describe ingress lumia-ingress`

---

## Quick Access Script

Save this as `access-app.sh`:

```bash
#!/bin/bash

echo "=== Lumiatech Application Access Info ==="
echo ""

# Check if ingress controller is ready
echo "1. Checking NGINX Ingress Controller..."
LB_URL=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ -z "$LB_URL" ]; then
    echo "   ❌ Ingress Controller not found or not ready"
    echo "   Install with: kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml"
else
    echo "   ✅ Load Balancer URL: $LB_URL"
fi

echo ""
echo "2. Checking Application Status..."
APP_STATUS=$(kubectl get pods -l app=lumia-app -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
echo "   App Status: $APP_STATUS"

DB_STATUS=$(kubectl get pods -l app=lumiadb -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
echo "   DB Status: $DB_STATUS"

echo ""
echo "3. Access Options:"
echo ""
echo "   Option A - Using Domain (requires hosts file update):"
echo "   Add to /etc/hosts (Linux/Mac) or C:\\Windows\\System32\\drivers\\etc\\hosts (Windows):"
echo "   $LB_URL www.lumiatechs.com"
echo "   Then access: http://www.lumiatechs.com"
echo ""
echo "   Option B - Direct Load Balancer Access:"
echo "   http://$LB_URL"
echo ""
echo "   Option C - Port Forward (local testing):"
echo "   kubectl port-forward svc/lumia-app-service 8080:8080"
echo "   Then access: http://localhost:8080"
echo ""
```

Make it executable and run:
```bash
chmod +x access-app.sh
./access-app.sh
```

---

## Recommended Approach

**For Quick Testing:** Use Option 3 (LoadBalancer Service) or Option 4 (Port Forward)

**For Demo/Staging:** Use Option 1 (Ingress with hosts file)

**For Production:** Use Option 5 (Route53 with real domain)
