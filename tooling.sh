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
  php-mbstring \
  php-xml \
  php-zip \
  curl \
  wget \
  git \
  rsync \
  unzip \
  default-mysql-client \
  binutils \
  python3 \
  util-linux

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

a2enmod "php$PHP_VERSION"
a2enmod rewrite

# --------------------------------------------------
# 2. Install Amazon EFS utilities
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
# 3. Mount Tooling EFS access point
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
# 4. Serialize shared EFS initialization
# --------------------------------------------------

exec 9>/var/www/html/.tooling-install.lock
flock 9

# --------------------------------------------------
# 5. Clone Tooling repository
# --------------------------------------------------

if [ ! -d /opt/tooling/.git ]; then
  rm -rf /opt/tooling
  git clone https://github.com/ChuksTech126/tooling.git /opt/tooling
fi

WEB_ROOT="/var/www/html/html"

mkdir -p "$WEB_ROOT"

if [ ! -d /opt/tooling/html ]; then
  echo "ERROR: Repository does not contain the expected html directory."
  exit 1
fi

# Deploy the PHP application to EFS.
rsync -a \
  --no-owner \
  --no-group \
  --exclude='.git' \
  /opt/tooling/html/ \
  "$WEB_ROOT/"

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
# 7. Wait for RDS connection
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
  echo "ERROR: Cannot connect to RDS."
  exit 1
fi

# --------------------------------------------------
# 8. Update Tooling PHP database connection
# --------------------------------------------------

if [ ! -f "$WEB_ROOT/functions.php" ]; then
  echo "ERROR: functions.php was not found in the deployed application."
  exit 1
fi

# The repository currently contains a hard-coded
# localhost MySQL connection in functions.php.
# Replace that exact connection with the RDS values.

DB_HOST_B64="$DB_HOST_B64" \
DB_PORT_B64="$DB_PORT_B64" \
DB_NAME_B64="$DB_NAME_B64" \
DB_USERNAME_B64="$DB_USERNAME_B64" \
DB_PASSWORD_B64="$DB_PASSWORD_B64" \
python3 - <<'PY'
import os
import re
from pathlib import Path

php_file = Path("/var/www/html/html/functions.php")
content = php_file.read_text()

replacement = (
    "$db = mysqli_connect("
    f"base64_decode('{os.environ['DB_HOST_B64']}'), "
    f"base64_decode('{os.environ['DB_USERNAME_B64']}'), "
    f"base64_decode('{os.environ['DB_PASSWORD_B64']}'), "
    f"base64_decode('{os.environ['DB_NAME_B64']}'), "
    f"(int) base64_decode('{os.environ['DB_PORT_B64']}')"
    ");"
)

pattern = r"^\s*\$db\s*=\s*mysqli_connect\([^;]*\);\s*$"

updated, count = re.subn(
    pattern,
    replacement,
    content,
    count=1,
    flags=re.MULTILINE
)

if count != 1:
    raise SystemExit(
        "ERROR: Expected the original mysqli_connect line "
        "in functions.php but could not find it."
    )

php_file.write_text(updated)
print("Tooling PHP database connection updated to RDS.")
PY

# --------------------------------------------------
# 9. Import Tooling database schema if necessary
# --------------------------------------------------

if [ ! -f /opt/tooling/tooling-db.sql ]; then
  echo "ERROR: tooling-db.sql was not found in the repository."
  exit 1
fi

USERS_TABLE_EXISTS=$(
  MYSQL_PWD="$DB_PASSWORD" mysql \
    -N \
    -h "$DB_HOST" \
    -P "$DB_PORT" \
    -u "$DB_USERNAME" \
    "$DB_NAME" \
    -e "SHOW TABLES LIKE 'users';"
)

if [ "$USERS_TABLE_EXISTS" != "users" ]; then

  echo "Importing Tooling database schema..."

  MYSQL_PWD="$DB_PASSWORD" mysql \
    -h "$DB_HOST" \
    -P "$DB_PORT" \
    -u "$DB_USERNAME" \
    "$DB_NAME" \
    < /opt/tooling/tooling-db.sql

else

  echo "Tooling users table already exists. Skipping import."

fi

# --------------------------------------------------
# 10. Configure Apache
# --------------------------------------------------

cat > /etc/apache2/sites-available/000-default.conf <<'APACHE'
<VirtualHost *:80>

    ServerAdmin infra@chuksapp.online

    DocumentRoot /var/www/html/html

    <Directory /var/www/html/html>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog $${APACHE_LOG_DIR}/tooling-error.log
    CustomLog $${APACHE_LOG_DIR}/tooling-access.log combined

</VirtualHost>
APACHE

a2dissite 000-default.conf >/dev/null 2>&1 || true
a2ensite 000-default.conf

# Remove default Apache landing page
rm -f "$WEB_ROOT/index.html"

# --------------------------------------------------
# 11. Create ALB health-check endpoint
# --------------------------------------------------

printf 'healthy\n' > "$WEB_ROOT/healthstatus"

# --------------------------------------------------
# 12. Set application permissions
# --------------------------------------------------

# EFS access point maps the instance's file operations
# to UID/GID 33 (www-data).

chmod -R u+rwX,g+rwX "$WEB_ROOT"

# --------------------------------------------------
# 13. Validate PHP and Apache
# --------------------------------------------------

php -l "$WEB_ROOT/functions.php"

apache2ctl configtest

systemctl enable apache2
systemctl restart apache2

# --------------------------------------------------
# 14. Local health check
# --------------------------------------------------

curl --fail http://127.0.0.1/healthstatus

echo "Tooling bootstrap completed successfully."
