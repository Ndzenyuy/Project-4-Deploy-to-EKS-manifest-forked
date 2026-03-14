#!/bin/bash

echo "=== Pre-flight Checks ==="
echo ""

# Variables
DOMAIN="www.lumiatechs.com"
BASE_DOMAIN="lumiatechs.com"
NAMESPACE="lumiatech"
MANIFESTS_DIR="kubedefs"

# Check 1: Namespace exists and context is set
echo "[Check 1] Ensuring namespace '$NAMESPACE' exists and context is set..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
kubectl config set-context --current --namespace=$NAMESPACE > /dev/null 2>&1
CURRENT_NS=$(kubectl config view --minify --output 'jsonpath={..namespace}')
if [ "$CURRENT_NS" == "$NAMESPACE" ]; then
    echo "   ✅ Namespace: $CURRENT_NS"
else
    echo "   ❌ Failed to set namespace to $NAMESPACE (current: $CURRENT_NS)"
    exit 1
fi

# Check 2: Apply all manifests
echo ""
echo "[Check 2] Applying manifests from $MANIFESTS_DIR/..."
if [ ! -d "$MANIFESTS_DIR" ]; then
    echo "   ❌ Directory '$MANIFESTS_DIR' not found. Run this script from the project root."
    exit 1
fi
kubectl apply -f $MANIFESTS_DIR/ -n $NAMESPACE > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "   ✅ Manifests applied"
else
    echo "   ⚠️  Some manifests may have failed. Continuing..."
fi

# Check 3: Wait for all pods to be Running
echo ""
echo "[Check 3] Waiting for all pods to be Running in namespace '$NAMESPACE'..."
MAX_WAIT=180
ELAPSED=0
INTERVAL=10
while true; do
    NOT_READY=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep -v 'Running\|Completed' | wc -l)
    TOTAL=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
    if [ "$TOTAL" -eq 0 ]; then
        echo "   ⚠️  No pods found in namespace $NAMESPACE. Check manifests were applied correctly."
        kubectl get pods -n $NAMESPACE
        exit 1
    fi
    if [ "$NOT_READY" -eq 0 ]; then
        echo "   ✅ All $TOTAL pod(s) are Running"
        break
    fi
    if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
        echo "   ❌ Timed out waiting for pods after ${MAX_WAIT}s. Current pod status:"
        kubectl get pods -n $NAMESPACE
        echo ""
        echo "   Check logs with: kubectl logs -l app=lumia-app -n $NAMESPACE"
        exit 1
    fi
    printf "\r   Waiting for pods... %d/%d ready (%ds elapsed)" $((TOTAL - NOT_READY)) $TOTAL $ELAPSED
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo ""
echo "=== Pre-flight Checks Passed. Starting Route53 CNAME Configuration ==="
echo ""

# Get Load Balancer DNS
echo "1. Getting Load Balancer DNS..."
LB_DNS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$LB_DNS" ]; then
    echo "❌ Could not find Load Balancer DNS"
    exit 1
fi

echo "   ✅ Load Balancer: $LB_DNS"

# Get Route53 hosted zone ID
echo ""
echo "2. Getting Route53 hosted zone ID..."
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${BASE_DOMAIN}.'].Id" --output text 2>/dev/null | cut -d'/' -f3)

if [ -z "$HOSTED_ZONE_ID" ]; then
    echo "❌ Could not find hosted zone for $BASE_DOMAIN"
    echo ""
    echo "Manual steps:"
    echo "1. Go to AWS Console → Route53 → Hosted Zones"
    echo "2. Select your domain: $BASE_DOMAIN"
    echo "3. Create Record:"
    echo "   - Record name: www"
    echo "   - Record type: CNAME"
    echo "   - Value: $LB_DNS"
    echo "   - TTL: 300"
    exit 1
fi

echo "   ✅ Route53 Hosted Zone ID: $HOSTED_ZONE_ID"

# Check if record already exists and delete it
echo ""
echo "3. Checking for existing records..."
EXISTING_RECORD=$(aws route53 list-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --query "ResourceRecordSets[?Name=='${DOMAIN}.']" \
  --output json)

if [ "$EXISTING_RECORD" != "[]" ]; then
    echo "   Found existing record, will update it"
fi

# Create CNAME record
echo ""
echo "4. Creating CNAME record..."
echo "   Domain: $DOMAIN"
echo "   Target: $LB_DNS"
echo ""

CHANGE_OUTPUT=$(aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "'$DOMAIN'",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'$LB_DNS'"}]
      }
    }]
  }' 2>&1)

if [ $? -eq 0 ]; then
    echo "   ✅ CNAME record created/updated successfully"
    CHANGE_ID=$(echo $CHANGE_OUTPUT | grep -o '"Id": "[^"]*"' | cut -d'"' -f4)
    echo "   Change ID: $CHANGE_ID"
else
    echo "   ❌ Failed to create CNAME record"
    echo "   Error: $CHANGE_OUTPUT"
    echo ""
    echo "Please create manually in AWS Console:"
    echo "   Record name: www"
    echo "   Record type: CNAME"
    echo "   Value: $LB_DNS"
    exit 1
fi

# Restore ingress host
echo ""
echo "5. Configuring ingress..."
kubectl apply -f kubedefs/appingress.yaml -n lumiatech > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "   ✅ Ingress configured"
else
    echo "   ⚠️  Ingress may already be configured"
fi

# Verify configuration
echo ""
echo "6. Verifying configuration..."
INGRESS_HOST=$(kubectl get ingress lumia-ingress -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
echo "   Ingress Host: $INGRESS_HOST"

# Wait for DNS
echo ""
echo "7. Waiting for DNS propagation (60 seconds)..."
for i in {60..1}; do
    printf "\r   Waiting... %2d seconds remaining" $i
    sleep 1
done
echo ""

# Test DNS
echo ""
echo "8. Testing DNS resolution..."
echo "   Testing with Google DNS (8.8.8.8)..."
DNS_RESULT=$(dig +short $DOMAIN @8.8.8.8 | grep -v '\.$' | tail -1)

if [ -z "$DNS_RESULT" ]; then
    echo "   ⚠️  DNS not yet propagated"
else
    echo "   ✅ DNS resolves to: $DNS_RESULT"
fi

echo ""
echo "   Testing with Cloudflare DNS (1.1.1.1)..."
DNS_RESULT2=$(dig +short $DOMAIN @1.1.1.1 | grep -v '\.$' | tail -1)

if [ -z "$DNS_RESULT2" ]; then
    echo "   ⚠️  DNS not yet propagated"
else
    echo "   ✅ DNS resolves to: $DNS_RESULT2"
fi

# Test HTTP
echo ""
echo "9. Testing HTTP access..."
# First test via Host header (bypasses DNS, confirms ingress routing)
HOST_TEST=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 -H "Host: $DOMAIN" http://$LB_DNS 2>/dev/null)
echo "   Ingress routing test (Host header): HTTP $HOST_TEST"
if [ "$HOST_TEST" == "404" ] || [ "$HOST_TEST" == "502" ]; then
    echo "   ⚠️  App may have startup errors. Check: kubectl logs -l app=lumia-app -n lumiatech"
fi

# Then test via domain
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://$DOMAIN 2>/dev/null)
if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "302" ]; then
    echo "   ✅ Application is accessible! (HTTP $HTTP_CODE)"
elif [ "$HTTP_CODE" == "000" ]; then
    echo "   ⚠️  Cannot connect yet (DNS still propagating - wait 5 more minutes)"
else
    echo "   ⚠️  Received HTTP $HTTP_CODE"
fi

echo ""
echo "=========================================="
echo "=== Configuration Complete ==="
echo "=========================================="
echo ""
echo "✅ CNAME record created: $DOMAIN → $LB_DNS"
echo "✅ Ingress configured for: $DOMAIN"
echo ""
echo "🌐 Access your application:"
echo "   http://www.lumiatechs.com"
echo ""
echo "⏱️  If not working yet:"
echo "   • Wait 5-10 minutes for global DNS propagation"
echo "   • Clear browser cache (Ctrl+F5)"
echo "   • Try incognito/private mode"
echo ""
echo "🔍 Verification commands:"
echo "   nslookup www.lumiatechs.com"
echo "   dig www.lumiatechs.com"
echo "   curl -I http://www.lumiatechs.com"
echo ""
echo "✅ Direct Load Balancer (works immediately):"
echo "   http://$LB_DNS"
echo ""
