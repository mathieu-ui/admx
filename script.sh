#!/bin/bash

# Ask user for the VMID of the container
read -p "Enter the VMID of the container: " container_vmid

read -p "Enter the name of the container: " container_name

read -p "Enter the IP of the container: " container_ip

read -p "Enter the port that will be forwarded to the 22 of the container: " container_port

# Verify if the container already exists
if ssh pve "pct list | grep -q '$container_vmid'"; then
    echo "Error: Container with VMID '$container_vmid' already exists."
    exit 1
fi

# Verify if the Debian template is installed
if ! ssh pve "pveam list local | grep 'debian-12-standard'"; then
    echo "Installing Debian 12 template..."
    ssh pve "pveam download local debian-12-standard_12.7-1_amd64.tar.zst"
fi

# Create the container
ssh pve "pct create $container_vmid local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst --hostname '$container_name' --password 'rftgyrftgy' --memory 1024 --net0 name=eth0,bridge=vmbr0,firewall=1,gw=10.0.0.254,ip=$container_ip/24,type=veth --storage local-vm --rootfs local-lvm:4 --ostype debian --unprivileged 1"

# Modify the firehol configuration on the PVE server
ssh pve "echo 'dnat4 to \"$container_ip\":22 inface enp0s3 proto tcp dport $container_port' >> /etc/firehol/firehol.conf"
ssh pve "systemctl restart firehol"

# Configure the Nginx reverse proxy on the PVE server
ssh pve "echo 'server {
    listen 80;
    server_name $container_name.example.com;
    location / {
        proxy_pass http://$container_name;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}' > /etc/nginx/conf.d/$container_name.conf"
ssh pve "systemctl reload nginx"

# Install Apache2 on the newly created container
ssh pve "pct exec $container_vmid -- apt-get update"
ssh pve "pct exec $container_vmid -- apt-get install -y apache2"

# Configure /etc/hosts on your computer
echo "$(ssh pve "pct exec $container_vmid -- hostname -i") $container_name.example.com" | sudo tee -a /etc/hosts
