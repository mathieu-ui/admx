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

echo "Creating the container..."

ssh pve "pct create $container_vmid local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst --hostname '$container_name' --password 'rftgyrftgy' --memory 1024 --net0 name=eth0,bridge=vmbr0,firewall=1,gw=10.0.0.254,ip=$container_ip/24,type=veth --storage local-vm --rootfs local-lvm:4 --ostype debian --unprivileged 1" > /dev/null

# Start the container
ssh pve "pct start $container_vmid"

# Modify the firehol configuration on the PVE server
ssh pve "sed -i '/interface4 vmbr0 vmlan src/i dnat4 to \"$container_ip\":22 inface enp0s3 proto tcp dport $container_port' /etc/firehol/firehol.conf"
ssh pve "systemctl restart firehol"

# Configure the Nginx reverse proxy on the PVE server

echo "Configuring the revers proxy..."

ssh pve "echo 'server {
    listen 80;
    server_name $container_name.admx.osef $container_name;
    location / {
        proxy_pass http://$container_ip;
    }
    access_log /var/log/nginx/$container_name.admx.osef-access.log;
    error_log  /var/log/nginx/$container_name.admx.osef-error.log; 
    location ^~ /.well-known/acme-challenge/ { default_type "text/plain"; root /var/www/certbot/; }
}' > /etc/nginx/sites-available/$container_name.admx.osef"

# Create a symlink for the Nginx configuration
ssh pve "ln -s /etc/nginx/sites-available/$container_name.admx.osef /etc/nginx/sites-enabled/$container_name.admx.osef"

# Generate a self-signed SSL certificate
ssh pve "make-ssl-cert generate-default-snakeoil"

# Restart the Nginx service
ssh pve "systemctl restart nginx"

# Install Apache2 on the newly created container

echo "Installing WebService..."

ssh pve "pct exec $container_vmid -- apt-get update" > /dev/null
ssh pve "pct exec $container_vmid -- apt-get install -y apache2" > /dev/null

# Configure /etc/hosts on your computer
echo "127.0.0.1 $container_name.admx.osef" | sudo tee -a /etc/hosts

echo "You can now acces to webservice using http://$container_name.admx.osef:8080"
echo "You can now ssh the container using 'ssh '"