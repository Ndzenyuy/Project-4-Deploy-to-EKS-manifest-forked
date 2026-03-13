# MySQL Database Pending State - Fix Guide

## Root Causes Identified:

1. **Missing StorageClass in PVC** - PVC cannot bind without specifying storage class
2. **Password Mismatch** - Dockerfile uses "admin123" but secret had "vprodbpass"
3. **Missing EBS CSI Driver** - EKS requires AWS EBS CSI driver for volume provisioning

## Quick Fix Steps:

### Step 1: Install EBS CSI Driver (if not already installed)

```bash
# Make script executable
chmod +x eks-setup/install-ebs-csi.sh

# Run installation
./eks-setup/install-ebs-csi.sh

# Verify storage class exists
kubectl get storageclass
```

### Step 2: Delete Existing Resources (if already deployed)

```bash
# Delete in reverse order
kubectl delete -f kubedefs/appdeploy.yaml
kubectl delete -f kubedefs/dbdeploy.yaml
kubectl delete -f kubedefs/dbpvc.yaml
kubectl delete -f kubedefs/secret.yaml

# Verify deletion
kubectl get pvc
kubectl get pods
```

### Step 3: Redeploy with Fixed Manifests

```bash
# Deploy in correct order
kubectl apply -f kubedefs/secret.yaml
kubectl apply -f kubedefs/dbpvc.yaml
kubectl apply -f kubedefs/dbservice.yaml
kubectl apply -f kubedefs/dbdeploy.yaml
kubectl apply -f kubedefs/appservice.yaml
kubectl apply -f kubedefs/appdeploy.yaml
kubectl apply -f kubedefs/appingress.yaml
```

### Step 4: Verify Deployment

```bash
# Check PVC status (should be Bound)
kubectl get pvc db-pv-claim

# Check database pod (should be Running)
kubectl get pods -l app=lumiadb

# Check database logs
kubectl logs -l app=lumiadb

# Check app pod
kubectl get pods -l app=lumia-app
```

## Verification Commands:

```bash
# Check if EBS CSI driver is installed
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

# Check storage classes
kubectl get sc

# Check PVC binding
kubectl describe pvc db-pv-claim

# Check pod events
kubectl describe pod -l app=lumiadb
```

## Expected Output:

```
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
db-pv-claim    Bound    pvc-xxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx     3Gi        RWO            gp2

NAME                       READY   STATUS    RESTARTS   AGE
lumiadb-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

## Changes Made:

1. **dbpvc.yaml**: Added `storageClassName: gp2`
2. **secret.yaml**: Changed password from "vprodbpass" to "admin123" (base64: YWRtaW4xMjM=)
3. **install-ebs-csi.sh**: New script to install EBS CSI driver

## Alternative: Use gp3 Storage Class

If you prefer gp3 (newer, better performance):

```bash
# Create gp3 storage class
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF

# Then update dbpvc.yaml to use storageClassName: gp3
```

## Troubleshooting:

If PVC still pending:
```bash
# Check events
kubectl get events --sort-by='.lastTimestamp'

# Check CSI driver
kubectl logs -n kube-system -l app=ebs-csi-controller

# Verify IAM permissions
aws eks describe-addon --cluster-name lumiatech-cluster --addon-name aws-ebs-csi-driver
```
