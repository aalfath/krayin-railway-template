#!/bin/sh
# Runs under the boot lock (see railway-install.php locked): install an empty
# database once, otherwise only apply new migrations. Never reseeds.
set -eu
cd /var/www/html
STATE="$(php /usr/local/bin/railway-install.php state)"
echo "[railway] database state: ${STATE}"
if [ "${STATE}" = "installed" ]; then
    php artisan migrate --force --no-interaction
else
    : "${ADMIN_EMAIL:?ADMIN_EMAIL is required for the first start (it becomes the admin login)}"
    : "${ADMIN_PASSWORD:?ADMIN_PASSWORD is required for the first start}"
    php artisan migrate --force --no-interaction
    php /usr/local/bin/railway-install.php install
fi
