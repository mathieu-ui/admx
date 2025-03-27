#!/bin/bash

if [[ $1 == "-h" || $1 == "--help" || $1 == "help" ]]; then
    cat <<EOF
Usage: $(basename "$0")
This script creates and configures a Proxmox container with a Apache2 web service.
It will prompt for:
  - container VMID
  - container name
  - container IP address
Options:
  -h, --help    Display this help message.
EOF
    exit 0
fi

# Ask user container info
read -p "Enter the VMID of the container: " container_vmid
read -p "Enter the name of the container: " container_name
read -p "Enter the IP of the container: " container_ip
# read -p "Enter the port that will be forwarded to the 22 of the container: " container_port

# Verify if the container exists
if ssh pve "pct list | grep -q '$container_vmid'"; then
    echo "Error: Container with VMID '$container_vmid' already exists."
    exit 1
fi

# Verify template is installed
if ! ssh pve "pveam list local | grep 'debian-12-standard'"; then
    echo "Installing Debian 12 template..."
    ssh pve "pveam download local debian-12-standard_12.7-1_amd64.tar.zst"
fi

# Create the container
echo "Creating the container..."

ssh pve "pct create $container_vmid local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst --hostname '$container_name' --password 'rftgyrftgy' --memory 1024 --net0 name=eth0,bridge=vmbr0,firewall=1,gw=10.0.0.254,ip=$container_ip/24,type=veth --storage local-vm --rootfs local-lvm:4 --ostype debian --unprivileged 1" > /dev/null

# Start the container
echo "Starting the container..."
ssh pve "pct start $container_vmid"

# Modify firehol conf
# ssh pve "sed -i '/interface4 vmbr0 vmlan src/i dnat4 to \"$container_ip\":22 inface enp0s3 proto tcp dport $container_port' /etc/firehol/firehol.conf"
# ssh pve "systemctl restart firehol"

# Configure Nginx reverse proxy
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

ssh pve "ln -s /etc/nginx/sites-available/$container_name.admx.osef /etc/nginx/sites-enabled/$container_name.admx.osef" > /dev/null
ssh pve "make-ssl-cert generate-default-snakeoil" > /dev/null
ssh pve "systemctl restart nginx" > /dev/null

# Add APACHE2 on CT

echo "Installing WebService..."

ssh pve "pct exec $container_vmid -- apt-get update" > /dev/null
ssh pve "pct exec $container_vmid -- apt-get install -y apache2" > /dev/null

# Add SSH on CT
ssh pve "pct exec $container_vmid -- sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config"
ssh pve "pct exec $container_vmid -- systemctl restart ssh"

# Configure /etc/hosts on host
echo "127.0.0.1 $container_name.admx.osef" | sudo tee -a /etc/hosts

echo "You can now acces to webservice using http://$container_name.admx.osef:8080"
#echo "You can now ssh the container using 'ssh '" -> SSH NOT WORKING IDK WHYY ??
echo "Default password of the CT is 'rftgyrftgy'"
echo "You can now acces to the container using from proxmox console or from pve host using 'ssh root@$container_ip'"
