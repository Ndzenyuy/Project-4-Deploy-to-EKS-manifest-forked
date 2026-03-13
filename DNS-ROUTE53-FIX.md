# Route53 DNS Configuration Fix

## Current Status
✅ App works via Load Balancer URL directly
❌ App doesn't work via www.lumiatechs.com

This means the issue is with DNS configuration, not the application.

## Common Issues & Solutions

### Issue 1: DNS Propagation Delay
DNS changes can take 5-60 minutes to propagate globally.

**Check DNS Resolution:**
```bash
# Check if DNS is resolving
nslookup www.lumiatechs.com

# Check with dig
dig www.lumiatechs.com

# Check what DNS returns
host www.lumiatechs.com
```

**Expected Output:**
```
www.lumiatechs.com canonical name = ac56fec2ff10b4be98aced852139a178-cb84f74367232483.elb.us-east-1.amazonaws.com
```

---

### Issue 2: Ingress Host Restriction Was Removed

Since you removed the host restriction from ingress, you need to add it back for domain-based routing.

**Fix: Restore Host Configuration**

```bash
# Restore the host in ingress
kubectl patch ingress lumia-ingress --type=json -p='[
  {
    "op": "add",
    "path": "/spec/rules/0/host",
    "value": "www.lumiatechs.com"
  }
]'
```

**Or apply the original ingress file:**
```bash
kubectl apply -f kubedefs/appingress.yaml
```

---

### Issue 3: Wrong CNAME Configuration

**Correct Route53 CNAME Setup:**

1. **Record Name:** `www`
2. **Record Type:** `CNAME`
3. **Value:** `ac56fec2ff10b4be98aced852139a178-cb84f74367232483.elb.us-east-1.amazonaws.com` (without http://)
4. **TTL:** `300` seconds
5. **Routing Policy:** Simple routing

**Common Mistakes:**
- ❌ Adding `http://` in the CNAME value
- ❌ Adding trailing dot in domain name when not needed
- ❌ Using A record instead of CNAME
- ❌ Wrong hosted zone

---

### Issue 4: Using Alias Record (Better for AWS)

For AWS Load Balancers, **Alias records are better than CNAME**.

**Create Alias Record via AWS CLI:**

```bash
# Get your hosted zone ID
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='lumiatechs.com.'].Id" --output text | cut -d'/' -f3)

# Get Load Balancer Hosted Zone ID (for us-east-1, it's Z35SXDOTRQ7X7K)
LB_HOSTED_ZONE_ID="Z35SXDOTRQ7X7K"

# Get Load Balancer DNS name
LB_DNS="ac56fec2ff10b4be98aced852139a178-cb84f74367232483.elb.us-east-1.amazonaws.com"

# Create Alias record
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "www.lumiatechs.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "'$LB_HOSTED_ZONE_ID'",
          "DNSName": "'$LB_DNS'",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }'
```

**ELB Hosted Zone IDs by Region:**
- us-east-1: `Z35SXDOTRQ7X7K`
- us-east-2: `Z3AADJGX6KTTL2`
- us-west-1: `Z368ELLRRE2KJ0`
- us-west-2: `Z1H1FL5HABSF5`

---

## Step-by-Step Fix Guide

### Step 1: Verify Current DNS Configuration

```bash
# Check what Route53 has
aws route53 list-resource-record-sets \
  --hosted-zone-id $(aws route53 list-hosted-zones --query "HostedZones[?Name=='lumiatechs.com.'].Id" --output text | cut -d'/' -f3) \
  --query "ResourceRecordSets[?Name=='www.lumiatechs.com.']"
```

### Step 2: Delete Incorrect CNAME (if exists)

```bash
# Get hosted zone ID
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='lumiatechs.com.'].Id" --output text | cut -d'/' -f3)

# Delete CNAME record
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "DELETE",
      "ResourceRecordSet": {
        "Name": "www.lumiatechs.com",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "ac56fec2ff10b4be98aced852139a178-cb84f74367232483.elb.us-east-1.amazonaws.com"}]
      }
    }]
  }'
```

### Step 3: Create Alias Record (Recommended)

```bash
# Get hosted zone ID
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='lumiatechs.com.'].Id" --output text | cut -d'/' -f3)

# Create Alias A record
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "www.lumiatechs.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z35SXDOTRQ7X7K",
          "DNSName": "ac56fec2ff10b4be98aced852139a178-cb84f74367232483.elb.us-east-1.amazonaws.com",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }'
```

### Step 4: Restore Ingress Host Configuration

```bash
# Apply original ingress with host restriction
kubectl apply -f kubedefs/appingress.yaml

# Verify ingress configuration
kubectl get ingress lumia-ingress -o yaml
```

### Step 5: Wait and Test

```bash
# Wait 2-5 minutes for DNS propagation
sleep 120

# Test DNS resolution
nslookup www.lumiatechs.com

# Test with curl
curl -I http://www.lumiatechs.com

# Test in browser
echo "Open: http://www.lumiatechs.com"
```

---

## Verification Checklist

### ✅ DNS Configuration
```bash
# Should return Load Balancer address
dig www.lumiatechs.com +short

# Should show CNAME or A record
nslookup www.lumiatechs.com
```

### ✅ Ingress Configuration
```bash
# Should show host: www.lumiatechs.com
kubectl get ingress lumia-ingress -o yaml | grep -A5 "rules:"
```

### ✅ Application Status
```bash
# All should be Running
kubectl get pods

# Should have endpoints
kubectl get endpoints lumia-app-service
```

### ✅ Test Access
```bash
# Test with Host header
curl -H "Host: www.lumiatechs.com" http://ac56fec2ff10b4be98aced852139a178-cb84f74367232483.elb.us-east-1.amazonaws.com

# Test direct domain
curl -I http://www.lumiatechs.com
```

---

## Quick Fix Script

Save as `fix-dns.sh`:

```bash
#!/bin/bash

echo "=== Route53 DNS Fix for www.lumiatechs.com ==="
echo ""

# Variables
DOMAIN="www.lumiatechs.com"
LB_DNS="ac56fec2ff10b4be98aced852139a178-cb84f74367232483.elb.us-east-1.amazonaws.com"
LB_HOSTED_ZONE="Z35SXDOTRQ7X7K"  # us-east-1

# Get hosted zone ID
echo "1. Getting hosted zone ID..."
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='lumiatechs.com.'].Id" --output text | cut -d'/' -f3)

if [ -z "$HOSTED_ZONE_ID" ]; then
    echo "❌ Could not find hosted zone for lumiatechs.com"
    echo "Please create hosted zone first or check domain name"
    exit 1
fi

echo "   ✅ Hosted Zone ID: $HOSTED_ZONE_ID"

# Create/Update Alias record
echo ""
echo "2. Creating Alias A record..."
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "'$DOMAIN'",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "'$LB_HOSTED_ZONE'",
          "DNSName": "'$LB_DNS'",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }' > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "   ✅ DNS record created/updated successfully"
else
    echo "   ❌ Failed to create DNS record"
    exit 1
fi

# Restore ingress host
echo ""
echo "3. Restoring ingress host configuration..."
kubectl apply -f kubedefs/appingress.yaml > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "   ✅ Ingress configuration restored"
else
    echo "   ⚠️  Could not restore ingress (may already be correct)"
fi

# Wait and test
echo ""
echo "4. Waiting for DNS propagation (30 seconds)..."
sleep 30

echo ""
echo "5. Testing DNS resolution..."
DNS_RESULT=$(dig +short $DOMAIN | tail -1)

if [ -z "$DNS_RESULT" ]; then
    echo "   ⚠️  DNS not yet propagated (may take 5-10 minutes)"
else
    echo "   ✅ DNS resolves to: $DNS_RESULT"
fi

echo ""
echo "=== Summary ==="
echo "✅ DNS record configured in Route53"
echo "✅ Ingress host restriction restored"
echo ""
echo "Access your application:"
echo "   http://www.lumiatechs.com"
echo ""
echo "If it doesn't work immediately, wait 5-10 minutes for DNS propagation"
echo ""
echo "Test DNS: nslookup www.lumiatechs.com"
echo "Test App: curl -I http://www.lumiatechs.com"
```

---

## Troubleshooting Commands

```bash
# Check Route53 records
aws route53 list-resource-record-sets \
  --hosted-zone-id <YOUR_ZONE_ID> \
  --query "ResourceRecordSets[?Name=='www.lumiatechs.com.']"

# Check DNS from different servers
dig @8.8.8.8 www.lumiatechs.com
dig @1.1.1.1 www.lumiatechs.com

# Test with Host header (should work immediately)
curl -H "Host: www.lumiatechs.com" http://<LOAD_BALANCER_URL>

# Check ingress rules
kubectl describe ingress lumia-ingress

# Check ingress logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50
```

---

## Why Alias is Better than CNAME

**Advantages of Alias Records:**
1. ✅ No additional DNS lookup (faster)
2. ✅ Can be used at zone apex (lumiatechs.com)
3. ✅ No charge for queries
4. ✅ Better integration with AWS services
5. ✅ Health checks supported

**CNAME Limitations:**
1. ❌ Cannot be used at zone apex
2. ❌ Additional DNS lookup required
3. ❌ Charged for queries
4. ❌ Not AWS-optimized
