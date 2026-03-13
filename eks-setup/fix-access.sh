#!/bin/bash

echo "=== Fixing Application Access ==="
echo ""

# Get Load Balancer URL
LB_URL=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$LB_URL" ]; then
    echo "❌ Error: Could not find Load Balancer URL"
    exit 1
fi

echo "✅ Load Balancer URL: $LB_URL"
echo ""

# Resolve Load Balancer to IP
echo "Resolving Load Balancer IP address..."
LB_IP=$(nslookup $LB_URL | grep -A1 "Name:" | grep "Address:" | tail -1 | awk '{print $2}')

if [ -z "$LB_IP" ]; then
    # Try alternative method
    LB_IP=$(dig +short $LB_URL | head -1)
fi

if [ -z "$LB_IP" ]; then
    echo "⚠️  Could not resolve IP automatically"
    echo ""
    echo "SOLUTION 1: Access directly via Load Balancer (No hosts file needed)"
    echo "-------------------------------------------------------------------"
    echo "Run this command to remove host restriction:"
    echo ""
    echo "kubectl patch ingress lumia-ingress -p '{\"spec\":{\"rules\":[{\"http\":{\"paths\":[{\"path\":\"/\",\"pathType\":\"Prefix\",\"backend\":{\"service\":{\"name\":\"lumia-app-service\",\"port\":{\"number\":8080}}}}]}}]}}'"
    echo ""
    echo "Then access: http://$LB_URL"
    echo ""
    echo "SOLUTION 2: Use Port Forward (Easiest)"
    echo "---------------------------------------"
    echo "kubectl port-forward svc/lumia-app-service 8080:8080"
    echo "Then access: http://localhost:8080"
    echo ""
else
    echo "✅ Load Balancer IP: $LB_IP"
    echo ""
    echo "Add this line to your /etc/hosts file:"
    echo "---------------------------------------"
    echo "$LB_IP www.lumiatechs.com"
    echo ""
    echo "Commands to update hosts file:"
    echo "sudo bash -c 'echo \"$LB_IP www.lumiatechs.com\" >> /etc/hosts'"
    echo ""
    echo "Then access: http://www.lumiatechs.com"
fi

echo ""
echo "=== Current Application Status ==="
kubectl get pods -l app=lumia-app
kubectl get pods -l app=lumiadb
kubectl get svc lumia-app-service
kubectl get ingress lumia-ingress
