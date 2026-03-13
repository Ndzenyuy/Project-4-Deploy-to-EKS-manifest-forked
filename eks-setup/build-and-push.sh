#!/bin/bash

# Docker Hub Build and Push Script for Lumiatech Application
# Replace 'ndzenyuy' with your Docker Hub username

DOCKER_USERNAME="ndzenyuy"
APP_IMAGE="$DOCKER_USERNAME/lumia-app"
DB_IMAGE="$DOCKER_USERNAME/lumia-db"
TAG="latest"

echo "=== Lumiatech Docker Build and Push Script ==="

# Step 1: Login to Docker Hub
echo "Step 1: Logging into Docker Hub..."
docker login

# Step 2: Build the Java Application WAR file
echo "Step 2: Building Java application with Maven..."
mvn clean install -DskipTests

# Check if WAR file was created
if [ ! -f "target/lumiatech-v1.war" ]; then
    echo "ERROR: WAR file not found. Maven build may have failed."
    exit 1
fi

echo "✅ WAR file created successfully: target/lumiatech-v1.war"

# Step 3: Build Application Docker Image
echo "Step 3: Building Application Docker image..."
docker build -t $APP_IMAGE:$TAG -f Docker-files/app/Dockerfile .

if [ $? -eq 0 ]; then
    echo "✅ Application image built successfully: $APP_IMAGE:$TAG"
else
    echo "❌ Failed to build application image"
    exit 1
fi

# Step 4: Build Database Docker Image
echo "Step 4: Building Database Docker image..."
docker build -t $DB_IMAGE:$TAG -f Docker-files/db/Dockerfile Docker-files/db/

if [ $? -eq 0 ]; then
    echo "✅ Database image built successfully: $DB_IMAGE:$TAG"
else
    echo "❌ Failed to build database image"
    exit 1
fi

# Step 5: Push Application Image
echo "Step 5: Pushing Application image to Docker Hub..."
docker push $APP_IMAGE:$TAG

if [ $? -eq 0 ]; then
    echo "✅ Application image pushed successfully"
else
    echo "❌ Failed to push application image"
    exit 1
fi

# Step 6: Push Database Image
echo "Step 6: Pushing Database image to Docker Hub..."
docker push $DB_IMAGE:$TAG

if [ $? -eq 0 ]; then
    echo "✅ Database image pushed successfully"
else
    echo "❌ Failed to push database image"
    exit 1
fi

# Step 7: Display built images
echo "Step 7: Listing built images..."
docker images | grep -E "(lumia-app|lumia-db)"

echo ""
echo "🎉 Build and Push Complete!"
echo "Application Image: $APP_IMAGE:$TAG"
echo "Database Image: $DB_IMAGE:$TAG"
echo ""
echo "Manifest files have been updated to use these new image names."
echo "You can now deploy to Kubernetes using: kubectl apply -f kubedefs/"