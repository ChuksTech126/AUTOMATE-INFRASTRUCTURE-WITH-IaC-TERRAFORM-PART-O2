#!/bin/bash
set -Eeuo pipefail

LOG_FILE="/var/log/nginx-user-data.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== NGINX USER DATA STARTED ====="
date

export DEBIAN_FRONTEND=noninteractive

echo "Updating Ubuntu packages..."
apt-get update -y

echo "Installing NGINX..."
apt-get install -y nginx

echo "Creating NGINX configuration..."

cat > /etc/nginx/sites-available/default <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    location = /healthstatus {
        access_log off;
        default_type text/plain;
        return 200 "healthy\n";
    }

    location / {
        return 404;
    }
}

server {
    listen 80;
    listen [::]:80;

    server_name tooling.chuksapp.online;

    location / {
        proxy_pass http://${internal_lb_dns};

        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_set_header X-Original-Forwarded-Proto $http_x_forwarded_proto;
    }
}

server {
    listen 80;
    listen [::]:80;

    server_name wordpress.chuksapp.online;

    location / {
        proxy_pass http://${internal_lb_dns};

        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_set_header X-Original-Forwarded-Proto $http_x_forwarded_proto;
    }
}
NGINX

echo "Testing NGINX configuration..."
nginx -t

echo "Enabling and starting NGINX..."
systemctl enable nginx
systemctl restart nginx

echo "Testing health endpoint..."
curl --fail http://127.0.0.1/healthstatus

echo "===== NGINX USER DATA COMPLETED ====="
