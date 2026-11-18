#!/bin/sh
# Krayin CRM entrypoint for Railway.
# Runs before Apache opens the port: storage seeding, first-boot install (once),
# migrations on every later boot, caches, then queue worker + scheduler + Apache.
set -eu
cd /var/www/html
log() { echo "[railway] $*"; }

# ---- settings: only references and secrets come from the template ----------
: "${APP_KEY:?APP_KEY is required (the template generates it)}"
: "${DB_HOST:?DB_HOST is required (reference the MySQL service)}"
: "${DB_PASSWORD:?DB_PASSWORD is required (reference the MySQL service)}"

case "${APP_URL:-}" in ''|'https://'|'http://') APP_URL='' ;; esac
if [ -z "${APP_URL}" ] && [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then APP_URL="https://${RAILWAY_PUBLIC_DOMAIN}"; fi
export APP_URL="${APP_URL:-http://localhost:${PORT:-8080}}"
export APP_NAME="${APP_NAME:-Krayin CRM}"
export APP_ENV="${APP_ENV:-production}"
export APP_DEBUG="${APP_DEBUG:-false}"
export APP_TIMEZONE="${APP_TIMEZONE:-UTC}"
export APP_LOCALE="${APP_LOCALE:-en}"
export APP_CURRENCY="${APP_CURRENCY:-USD}"
export DB_CONNECTION="${DB_CONNECTION:-mysql}"
export DB_PORT="${DB_PORT:-3306}"
export DB_DATABASE="${DB_DATABASE:-railway}"
export DB_USERNAME="${DB_USERNAME:-root}"
export LOG_CHANNEL="${LOG_CHANNEL:-stderr}"
export LOG_LEVEL="${LOG_LEVEL:-warning}"
export CACHE_DRIVER="${CACHE_DRIVER:-file}"
export SESSION_DRIVER="${SESSION_DRIVER:-file}"
export QUEUE_CONNECTION="${QUEUE_CONNECTION:-database}"
export MAIL_MAILER="${MAIL_MAILER:-log}"
export MAIL_FROM_ADDRESS="${MAIL_FROM_ADDRESS:-crm@${RAILWAY_PUBLIC_DOMAIN:-localhost}}"
export MAIL_FROM_NAME="${MAIL_FROM_NAME:-$APP_NAME}"
export PORT="${PORT:-8080}"

# ---- Apache: enforce one MPM and only our site ------------------------------
# Files deleted in image layers (a2dismod/a2dissite symlinks) reappeared in
# Railway's runtime filesystem, and Apache then refused to start with
# "More than one MPM loaded". Re-assert the intended links at every start.
for m in mpm_event mpm_worker; do rm -f /etc/apache2/mods-enabled/$m.load /etc/apache2/mods-enabled/$m.conf; done
ln -sf ../mods-available/mpm_prefork.load /etc/apache2/mods-enabled/mpm_prefork.load
ln -sf ../mods-available/mpm_prefork.conf /etc/apache2/mods-enabled/mpm_prefork.conf
find /etc/apache2/sites-enabled -mindepth 1 ! -name krayin.conf -exec rm -f {} +
ln -sf ../sites-available/krayin.conf /etc/apache2/sites-enabled/krayin.conf
apache2ctl -t >/dev/null 2>&1 || { log "apache config test failed:"; apache2ctl -t; exit 1; }

# ---- storage/ lives on the volume: seed an empty volume, never overwrite ----
mkdir -p storage
cp -an /opt/krayin-storage/. storage/ 2>/dev/null || true
mkdir -p storage/app/public storage/framework/cache/data storage/framework/sessions \
         storage/framework/views storage/logs bootstrap/cache
rm -rf storage/lost+found 2>/dev/null || true

# ---- database: wait, then (under a lock) install once or migrate ----------
php /usr/local/bin/railway-install.php wait
php /usr/local/bin/railway-install.php locked /usr/local/bin/railway-db.sh
touch storage/installed

# ---- caches (rebuilt each boot from the current variables) -----------------
php artisan optimize:clear >/dev/null 2>&1 || true
php artisan config:cache >/dev/null
php artisan view:cache >/dev/null 2>&1 || log "view cache skipped"
php artisan event:cache >/dev/null 2>&1 || log "event cache skipped"
php artisan route:cache >/dev/null 2>&1 || { log "route cache skipped"; php artisan route:clear >/dev/null 2>&1 || true; }

chown -R www-data:www-data storage bootstrap/cache

# The first admin's password is only needed by the install step.
unset ADMIN_PASSWORD

# ---- background: queue worker (imports, exports) and the scheduler ---------
supervise() {
    while true; do
        runuser -u www-data -- "$@" || true
        log "'$*' exited, restarting in 5 s"
        sleep 5
    done
}
supervise php artisan queue:work --sleep=3 --tries=3 --max-time=3600 &
supervise php artisan schedule:work &

log "Krayin ${KRAYIN_VERSION} ready on port ${PORT}, ${APP_URL}"
exec "$@"
