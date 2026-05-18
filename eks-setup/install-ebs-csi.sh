#!/bin/bash

# Install AWS EBS CSI Driver for EKS
# This is required for PersistentVolumeClaims to work in EKS

CLUSTER_NAME="lumiatechs-eks-cluster"
REGION="us-east-1"

echo "Installing AWS EBS CSI Driver..."

# Create IAM OIDC provider for the cluster
eksctl utils associate-iam-oidc-provider \
  --region=$REGION \
  --cluster=$CLUSTER_NAME \
  --approve

# Create IAM service account for EBS CSI driver
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --role-only \
  --role-name AmazonEKS_EBS_CSI_DriverRole

# Install EBS CSI driver addon
eksctl create addon \
  --name aws-ebs-csi-driver \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --service-account-role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/AmazonEKS_EBS_CSI_DriverRole \
  --force

echo "Waiting for EBS CSI driver to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-ebs-csi-driver -n kube-system --timeout=120s

echo "EBS CSI Driver installed successfully!"
echo "Verifying storage classes..."
kubectl get storageclass
