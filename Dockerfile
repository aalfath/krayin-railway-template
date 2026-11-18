# Krayin CRM for Railway: https://github.com/aalfath/krayin-railway-template
#
# Krayin publishes no image that fits Railway: `webkul/krayin` bundles its own
# MySQL server, runs as one fat container and its newest tag (2.2.0) is far
# behind upstream. So this builds the pinned upstream release on the official
# PHP image (pinned by version and digest), and adds only what Railway needs:
# Apache on $PORT, a first-boot install that never reseeds, a queue worker and
# the scheduler.

FROM php:8.3.36-apache-trixie@sha256:a800bbd2c0aa322702259ed475556b2cbc311076a8d3c4bba9bfe96838745472

# Upstream release and the commit its tag points at (checked at build time).
ARG KRAYIN_VERSION=v2.2.8
ARG KRAYIN_COMMIT=ed6deebfcb8c616eaf352c893a10a6d8e666fc6e

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_NO_INTERACTION=1 \
    KRAYIN_VERSION=${KRAYIN_VERSION}

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git unzip libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
        libicu-dev libzip-dev libgmp-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" bcmath calendar exif gd gmp intl opcache pcntl pdo_mysql zip; \
    rm -rf /var/lib/apt/lists/*; \
    a2enmod rewrite remoteip headers setenvif; \
    a2dissite 000-default

COPY --from=composer:2.11.2@sha256:0c8e663f14c94d07b3c45b175c51f5a14718508f21fe4dd7e54f09488dd0ed71 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

RUN set -eux; \
    rm -rf /var/www/html/*; \
    git clone --depth 1 --branch "${KRAYIN_VERSION}" https://github.com/krayin/laravel-crm.git .; \
    test "$(git -c safe.directory='*' rev-parse HEAD)" = "${KRAYIN_COMMIT}"; \
    rm -rf .git; \
    composer install --no-dev --prefer-dist --optimize-autoloader --no-scripts; \
    rm -rf /root/.composer /root/.cache; \
    touch .env; \
    php artisan package:discover --ansi; \
    # Upstream schedules the inbound-mail poll every 5 minutes, but the default
    # "sendgrid" receiver throws on it. Run it only when IMAP is configured.
    sed -i "s|Schedule::command('inbound-emails:process')->everyFiveMinutes();|Schedule::command('inbound-emails:process')->everyFiveMinutes()->when(fn () => config('mail-receiver.default') === 'webklex-imap');|" routes/console.php; \
    grep -q "webklex-imap" routes/console.php; \
    ln -sfn ../storage/app/public public/storage; \
    # Pristine storage/ tree, copied onto the empty volume on first boot.
    cp -a storage /opt/krayin-storage; \
    rm -f /opt/krayin-storage/installed; \
    chown -R www-data:www-data storage bootstrap/cache

ENV PORT=8080
COPY rootfs/ /
RUN a2ensite krayin && apache2ctl configtest && chmod 755 /usr/local/bin/railway-entrypoint.sh /usr/local/bin/railway-db.sh && sh -n /usr/local/bin/railway-db.sh && php -l /usr/local/bin/railway-install.php && sh -n /usr/local/bin/railway-entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["apache2-foreground"]
