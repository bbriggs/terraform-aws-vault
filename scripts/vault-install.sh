#! /bin/bash
set -e

# Install package
sudo apt-get update -y
sudo apt-get install -y curl unzip jq

# Download, unpack, install vault
DOWNLOAD_URL=https://releases.hashicorp.com/vault/0.7.0/vault_0.7.0_linux_amd64.zip
curl -L "${DOWNLOAD_URL}" > /tmp/vault.zip
cd /tmp
sudo unzip vault.zip
sudo mv vault /usr/local/bin
sudo chmod 0755 /usr/local/bin/vault
sudo chown root.root /usr/local/bin/vault

sudo mv /tmp/vault-config.hcl /usr/local/etc/vault-config.hcl

# Setup Systemd Service

sudo chmod 00644 /tmp/vault.service
sudo mv /tmp/vault.service /etc/systemd/system/vault.service
sudo mkdir -p /etc/sysconfig/vault
sudo chmod 00644 /etc/sysconfig/vault
