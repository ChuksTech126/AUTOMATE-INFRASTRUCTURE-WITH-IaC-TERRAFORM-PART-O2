#!/bin/bash

set -Eeuo pipefail

exec > >(tee -a /var/log/user-data.log) 2>&1

export DEBIAN_FRONTEND=noninteractive

# --------------------------------------------------
# 1. Install Apache, PHP and dependencies
# --------------------------------------------------

apt-get update -y

apt-get install -y \
  apache2 \
  php \
  libapache2-mod-php \
  php-mysql \
  php-curl \
  php-gd \
  php-mbstring \
  php-xml \
  php-zip \
  php-intl \
  curl \
  wget \
  git \
  rsync \
  unzip \
  tar \
  default-mysql-client \
  binutils \
  openssl \
  util-linux

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

a2enmod "php$PHP_VERSION"
a2enmod rewrite

# --------------------------------------------------
# Install Amazon EFS utilities
# --------------------------------------------------

if ! command -v mount.efs >/dev/null 2>&1; then
  apt-get install -y \
    binutils \
    nfs-common \
    stunnel4 \
    util-linux

  git clone --depth 1 --branch v1.36.0 \
    https://github.com/aws/efs-utils.git \
    /opt/efs-utils

  cd /opt/efs-utils
  ./build-deb.sh
  apt-get install -y ./build/amazon-efs-utils*.deb
  cd /

  command -v mount.efs
fi


# --------------------------------------------------
# 3. Mount WordPress EFS access point
# --------------------------------------------------

EFS_FILE_SYSTEM_ID="${efs_file_system_id}"
EFS_ACCESS_POINT_ID="${efs_access_point_id}"

mkdir -p /var/www/html

if ! mountpoint -q /var/www/html; then
  mount -t efs \
    -o "tls,accesspoint=$EFS_ACCESS_POINT_ID" \
    "$EFS_FILE_SYSTEM_ID:/" \
    /var/www/html
fi

mountpoint -q /var/www/html

if ! grep -q "$EFS_FILE_SYSTEM_ID" /etc/fstab; then
  echo "$EFS_FILE_SYSTEM_ID:/ /var/www/html efs _netdev,tls,accesspoint=$EFS_ACCESS_POINT_ID 0 0" \
    >> /etc/fstab
fi

# --------------------------------------------------
# 4. Prepare WordPress document root
# --------------------------------------------------

WEB_ROOT="/var/www/html/html"

mkdir -p "$WEB_ROOT"

# Serialize initialization because ASG instances
# share the same EFS access point.

exec 9>/var/www/html/.wordpress-install.lock
flock 9

# --------------------------------------------------
# 5. Download official WordPress package
# --------------------------------------------------

if [ ! -f "$WEB_ROOT/wp-load.php" ]; then

  echo "Downloading WordPress..."

  curl -fsSL \
    https://wordpress.org/latest.tar.gz \
    -o /tmp/wordpress.tar.gz

  mkdir -p /tmp/wordpress-install

  tar -xzf /tmp/wordpress.tar.gz \
    -C /tmp/wordpress-install

  rsync -a \
    --no-owner \
    --no-group \
    /tmp/wordpress-install/wordpress/ \
    "$WEB_ROOT/"

  rm -rf /tmp/wordpress-install
  rm -f /tmp/wordpress.tar.gz

fi

# --------------------------------------------------
# 6. Decode RDS connection values
# --------------------------------------------------

DB_HOST_B64="${db_host_b64}"
DB_PORT_B64="${db_port_b64}"
DB_NAME_B64="${db_name_b64}"
DB_USERNAME_B64="${db_username_b64}"
DB_PASSWORD_B64="${db_password_b64}"

DB_HOST=$(printf '%s' "$DB_HOST_B64" | base64 -d)
DB_PORT=$(printf '%s' "$DB_PORT_B64" | base64 -d)
DB_NAME=$(printf '%s' "$DB_NAME_B64" | base64 -d)
DB_USERNAME=$(printf '%s' "$DB_USERNAME_B64" | base64 -d)
DB_PASSWORD=$(printf '%s' "$DB_PASSWORD_B64" | base64 -d)

# --------------------------------------------------
# 7. Wait for RDS to become reachable
# --------------------------------------------------

DB_READY=false

for attempt in $(seq 1 30); do

  if MYSQL_PWD="$DB_PASSWORD" mysql \
    --connect-timeout=10 \
    -h "$DB_HOST" \
    -P "$DB_PORT" \
    -u "$DB_USERNAME" \
    "$DB_NAME" \
    -e "SELECT 1;" >/dev/null 2>&1; then

    DB_READY=true
    echo "RDS connection successful."
    break
  fi

  echo "Waiting for RDS: attempt $attempt/30"
  sleep 10

done

if [ "$DB_READY" = false ]; then
  echo "ERROR: Cannot connect to RDS. WordPress setup cannot continue."
  exit 1
fi

# --------------------------------------------------
# 8. Create wp-config.php only once
# --------------------------------------------------

if [ ! -f "$WEB_ROOT/wp-config.php" ]; then

  AUTH_KEY=$(openssl rand -hex 32)
  SECURE_AUTH_KEY=$(openssl rand -hex 32)
  LOGGED_IN_KEY=$(openssl rand -hex 32)
  NONCE_KEY=$(openssl rand -hex 32)
  AUTH_SALT=$(openssl rand -hex 32)
  SECURE_AUTH_SALT=$(openssl rand -hex 32)
  LOGGED_IN_SALT=$(openssl rand -hex 32)
  NONCE_SALT=$(openssl rand -hex 32)

  cat > "$WEB_ROOT/wp-config.php" <<PHP
<?php

define('DB_NAME', base64_decode('$DB_NAME_B64'));
define('DB_USER', base64_decode('$DB_USERNAME_B64'));
define('DB_PASSWORD', base64_decode('$DB_PASSWORD_B64'));
define('DB_HOST', base64_decode('$DB_HOST_B64') . ':' . base64_decode('$DB_PORT_B64'));
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');

define('AUTH_KEY', '$AUTH_KEY');
define('SECURE_AUTH_KEY', '$SECURE_AUTH_KEY');
define('LOGGED_IN_KEY', '$LOGGED_IN_KEY');
define('NONCE_KEY', '$NONCE_KEY');
define('AUTH_SALT', '$AUTH_SALT');
define('SECURE_AUTH_SALT', '$SECURE_AUTH_SALT');
define('LOGGED_IN_SALT', '$LOGGED_IN_SALT');
define('NONCE_SALT', '$NONCE_SALT');

\$table_prefix = 'wp_';

define('WP_DEBUG', false);

if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

require_once ABSPATH . 'wp-settings.php';
PHP

fi

python3 - "$WEB_ROOT/wp-config.php" <<'PY'
from pathlib import Path
import sys

wp_config = Path(sys.argv[1])
content = wp_config.read_text()
marker = "if (!defined('ABSPATH')) {"
https_forwarding = """if (
    isset($_SERVER['HTTP_X_ORIGINAL_FORWARDED_PROTO']) &&
    strtolower($_SERVER['HTTP_X_ORIGINAL_FORWARDED_PROTO']) === 'https'
) {
    $_SERVER['HTTPS'] = 'on';
}

"""

if "HTTP_X_ORIGINAL_FORWARDED_PROTO" not in content:
    if marker not in content:
        raise SystemExit("ERROR: Could not configure WordPress HTTPS proxy detection.")
    wp_config.write_text(content.replace(marker, https_forwarding + marker, 1))
PY

# --------------------------------------------------
# 9. Configure Apache
# --------------------------------------------------

cat > /etc/apache2/sites-available/000-default.conf <<'APACHE'
<VirtualHost *:80>

    ServerAdmin webmaster@localhost

    DocumentRoot /var/www/html/html

    <Directory /var/www/html/html>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog $${APACHE_LOG_DIR}/wordpress-error.log
    CustomLog $${APACHE_LOG_DIR}/wordpress-access.log combined

</VirtualHost>
APACHE

a2dissite 000-default.conf >/dev/null 2>&1 || true
a2ensite 000-default.conf

# Remove the default Apache landing page
rm -f "$WEB_ROOT/index.html"

# --------------------------------------------------
# 10. Create ALB health-check endpoint
# --------------------------------------------------

printf 'healthy\n' > "$WEB_ROOT/healthstatus"

# WordPress must be able to write uploads, plugins,
# themes and other content.

mkdir -p "$WEB_ROOT/wp-content/uploads"

chmod -R 775 "$WEB_ROOT/wp-content"

# The EFS access point enforces UID/GID 33.
chmod 640 "$WEB_ROOT/wp-config.php"

# --------------------------------------------------
# 11. Validate and start Apache
# --------------------------------------------------

apache2ctl configtest

systemctl enable apache2
systemctl restart apache2

# --------------------------------------------------
# 12. Local health check
# --------------------------------------------------

curl --fail http://127.0.0.1/healthstatus

echo "WordPress bootstrap completed successfully."
