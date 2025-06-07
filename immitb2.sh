#!/bin/bash

# Immich + Backblaze + Azure Setup Script
# Ensure you run this script with sudo/root privileges

### 1. Set variables - Update these as per your configuration ###
RESOURCE_GROUP="testvikas"
NSG_NAME="ImmichV2-nsg"
BUCKET_NAME="Memories78"
MOUNT_DIR="/mnt/Memories78"
IMMICH_UPLOAD_DIR="$MOUNT_DIR"

### 2. Install Docker and Docker Compose ###
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable docker && systemctl start docker

### 3. Enable Docker for your user ###
usermod -aG docker $USER

### 4. Install rclone ###
sudo apt install -y rclone fuse

### 5. Configure rclone (interactive step if not done yet) ###
# rclone config (Manual Step) -- skip if already configured

### 6. Mount Backblaze B2 bucket ###
sudo mkdir -p $MOUNT_DIR
sudo rclone mount ${BUCKET_NAME}:${BUCKET_NAME} $MOUNT_DIR \
  --vfs-cache-mode full \
  --vfs-cache-max-size 1G \
  --vfs-read-chunk-size 64M \
  --vfs-read-ahead 128M \
  --buffer-size 32M \
  --allow-other \
  --umask 002 \
  --daemon

### 7. Open port 2283 on Azure NSG for Immich UI ###
az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  --name "Allow-Port-2283" \
  --priority 1001 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --destination-port-ranges 2283 \
  --source-address-prefixes '*' \
  --destination-address-prefixes '*' \
  --description "Allow TCP traffic on port 2283 for Immich UI"

### 8. Clone Immich repository and set it up ###
mkdir ./immich-app
cd ./immich-app
wget -O docker-compose.yml https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
wget -O .env https://github.com/immich-app/immich/releases/latest/download/example.env

# Edit the .env file
sed -i "s|UPLOAD_LOCATION=.*|UPLOAD_LOCATION=$IMMICH_UPLOAD_DIR|" .env

# Optional: configure DB password, username, etc. in .env

### 9. Start Immich using Docker Compose ###

IMMICH_VERSION=release 
docker compose up -d

### 10. (Optional) Create a Systemd service to mount B2 on boot ###
# Create: /etc/systemd/system/mount-b2.service
cat <<EOF > /etc/systemd/system/mount-b2.service
[Unit]
Description=Mount Backblaze B2 Bucket via rclone
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount ${BUCKET_NAME}:${BUCKET_NAME} $MOUNT_DIR \
  --vfs-cache-mode full \
  --vfs-cache-max-size 1G \
  --vfs-read-chunk-size 64M \
  --vfs-read-ahead 128M \
  --buffer-size 32M \
  --allow-other \
  --umask 002
Restart=on-abort

[Install]
WantedBy=default.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable mount-b2
systemctl start mount-b2

echo "✅ Immich setup complete with Backblaze integration. Access it on http://<your_vm_ip>:2283"
