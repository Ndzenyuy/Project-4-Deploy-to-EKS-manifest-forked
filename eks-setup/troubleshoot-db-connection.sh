#!/bin/bash

echo "=== Database Connection Troubleshooting ==="
echo ""

# Get pod names
DB_POD=$(kubectl get pods -l app=lumiadb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
APP_POD=$(kubectl get pods -l app=lumia-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

echo "1. Pod Status"
echo "============================================"
kubectl get pods -l app=lumiadb
kubectl get pods -l app=lumia-app
echo ""

if [ -z "$DB_POD" ]; then
    echo "❌ Database pod not found!"
    echo ""
    echo "Check deployment:"
    kubectl get deployment lumiadb
    exit 1
fi

if [ -z "$APP_POD" ]; then
    echo "❌ Application pod not found!"
    echo ""
    echo "Check deployment:"
    kubectl get deployment lumia-app
    exit 1
fi

echo "✅ Database Pod: $DB_POD"
echo "✅ Application Pod: $APP_POD"
echo ""

# Database logs
echo "2. Database Pod Logs (Last 50 lines)"
echo "============================================"
kubectl logs $DB_POD --tail=50
echo ""

# Database pod details
echo "3. Database Pod Details"
echo "============================================"
kubectl describe pod $DB_POD | grep -A 10 "Events:"
echo ""

# Application logs
echo "4. Application Pod Logs (Last 50 lines)"
echo "============================================"
kubectl logs $APP_POD --tail=50
echo ""

# Application pod details
echo "5. Application Pod Details"
echo "============================================"
kubectl describe pod $APP_POD | grep -A 10 "Events:"
echo ""

# Check services
echo "6. Service Status"
echo "============================================"
kubectl get svc lumiadb
kubectl get endpoints lumiadb
echo ""

# Check database service connectivity
echo "7. Database Service Connectivity Test"
echo "============================================"
echo "Testing DNS resolution from app pod..."
kubectl exec $APP_POD -- nslookup lumiadb 2>/dev/null || echo "⚠️ nslookup not available"
echo ""

echo "Testing database port connectivity..."
kubectl exec $APP_POD -- nc -zv lumiadb 3306 2>&1 || echo "⚠️ nc not available, trying telnet..."
kubectl exec $APP_POD -- timeout 5 telnet lumiadb 3306 2>&1 || echo "⚠️ Connection test failed"
echo ""

# Check environment variables
echo "8. Application Environment Variables"
echo "============================================"
kubectl exec $APP_POD -- env | grep -E "DB_|MYSQL" || echo "No DB environment variables found"
echo ""

# Check database is running
echo "9. Database Process Check"
echo "============================================"
kubectl exec $DB_POD -- ps aux | grep mysql || echo "⚠️ MySQL process check failed"
echo ""

# Check database is listening
echo "10. Database Port Check"
echo "============================================"
kubectl exec $DB_POD -- netstat -tlnp 2>/dev/null | grep 3306 || echo "⚠️ netstat not available"
echo ""

# Check PVC
echo "11. Persistent Volume Status"
echo "============================================"
kubectl get pvc db-pv-claim
echo ""

# Check secrets
echo "12. Secret Configuration"
echo "============================================"
kubectl get secret app-secret -o jsonpath='{.data.db-pass}' | base64 -d
echo " (decoded password)"
echo ""

# Summary
echo ""
echo "============================================"
echo "=== Troubleshooting Summary ==="
echo "============================================"
echo ""
echo "📋 Quick Commands:"
echo ""
echo "View live database logs:"
echo "  kubectl logs -f $DB_POD"
echo ""
echo "View live application logs:"
echo "  kubectl logs -f $APP_POD"
echo ""
echo "Access database pod shell:"
echo "  kubectl exec -it $DB_POD -- bash"
echo ""
echo "Access application pod shell:"
echo "  kubectl exec -it $APP_POD -- bash"
echo ""
echo "Test database connection from app pod:"
echo "  kubectl exec -it $APP_POD -- curl -v telnet://lumiadb:3306"
echo ""
echo "Check database is ready:"
echo "  kubectl exec $DB_POD -- mysqladmin ping -h localhost -uroot -padmin123"
echo ""
echo "Connect to MySQL:"
echo "  kubectl exec -it $DB_POD -- mysql -uroot -padmin123"
echo ""
