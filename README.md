# admx

This repository contains a Bash script that creates and configures a Proxmox container with an Apache2 web service.

## Overview

The [`script.sh`](script.sh) script performs the following tasks:
- Prompts for the container VMID, container name, and container IP address.
- Verifies if the container already exists.
- Downloads and installs the Debian 12 template if it is not already available.
- Creates and starts the container.
- Configures an Nginx reverse proxy.
- Installs Apache2 inside the container.
- Adjusts SSH settings to enable root login.
- Updates the host's `/etc/hosts` file to map the container hostname.

## Usage

To run the script, execute:

```bash
bash script.sh
```

To get some help :

```bash
bash script.sh -h
```