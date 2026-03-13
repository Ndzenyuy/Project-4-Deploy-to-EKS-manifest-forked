#!/bin/bash
# ----------------------------------------------------
# EC2 UserData: OpenJDK 17 + Maven + Tomcat 9 (8081) + Jenkins (8082)
# ----------------------------------------------------

set -e

echo "Updating system..."
apt update -y

# Provisioning tools for the cluster setup

yum --help &>> /dev/null
if [ $? -eq 0 ]
then
  yum install zip unzip -y
else
  apt update && apt install zip unzip -y
fi
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install


curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp

sudo mv /tmp/eksctl /usr/local/bin
eksctl version
curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.17.9/2020-08-04/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin
kubectl version --short --client


# ----------------------------------------------------
# Install Java 17, Maven, utilities
# ----------------------------------------------------
echo "Installing OpenJDK 17, Maven, and utilities..."
apt install -y \
  openjdk-17-jdk \
  maven \
  wget \
  curl \
  gnupg \
  tar

java -version
mvn -version


# ----------------------------------------------------
# Create Tomcat user
# ----------------------------------------------------
echo "Creating tomcat user..."
useradd -r -m -U -d /opt/apache-tomcat-9.0.96 -s /bin/false tomcat || true

# ----------------------------------------------------
# Install Tomcat 9
# ----------------------------------------------------
echo "Downloading Tomcat 9.0.96..."
cd /tmp
wget https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.96/bin/apache-tomcat-9.0.96.tar.gz

echo "Extracting Tomcat..."
tar xf apache-tomcat-9.0.96.tar.gz -C /opt/

chown -R tomcat:tomcat /opt/apache-tomcat-9.0.96
chmod +x /opt/apache-tomcat-9.0.96/bin/*.sh


# ----------------------------------------------------
# Create Tomcat systemd service
# ----------------------------------------------------
echo "Creating Tomcat systemd service..."
cat <<EOF > /etc/systemd/system/tomcat9.service
[Unit]
Description=Apache Tomcat 9
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat

Environment="JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"
Environment="CATALINA_HOME=/opt/apache-tomcat-9.0.96"
Environment="CATALINA_BASE=/opt/apache-tomcat-9.0.96"
Environment="CATALINA_PID=/opt/apache-tomcat-9.0.96/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server"
Environment="JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"
Environment="CATALINA_HOME=/opt/apache-tomcat-9.0.96"
Environment="CATALINA_BASE=/opt/apache-tomcat-9.0.96"
Environment="CATALINA_PID=/opt/apache-tomcat-9.0.96/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC \
--add-opens java.base/java.lang=ALL-UNNAMED \
--add-opens java.base/java.lang.invoke=ALL-UNNAMED \
--add-opens java.base/java.lang.reflect=ALL-UNNAMED \
--add-opens java.base/java.io=ALL-UNNAMED \
--add-opens java.base/java.security=ALL-UNNAMED \
--add-opens java.base/java.util=ALL-UNNAMED \
--add-opens java.base/java.util.concurrent=ALL-UNNAMED \
--add-opens java.rmi/sun.rmi.transport=ALL-UNNAMED"

ExecStart=/opt/apache-tomcat-9.0.96/bin/startup.sh
ExecStop=/opt/apache-tomcat-9.0.96/bin/shutdown.sh

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# ----------------------------------------------------
# Enable and start Tomcat
# ----------------------------------------------------
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable tomcat9
systemctl start tomcat9

echo "----------------------------------------------------"
echo "Setup complete:"
echo " - Java 17 installed"
echo " - Maven installed"
echo " - Tomcat running on port 8081"
echo " - Jenkins running on port 8082"
echo "----------------------------------------------------"

