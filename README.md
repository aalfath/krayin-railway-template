[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/krayin-crm-1?utm_medium=integration&utm_source=button&utm_campaign=krayin-crm)

# Krayin CRM on Railway

A one-click Railway template for [Krayin CRM](https://github.com/krayin/laravel-crm), the free, MIT-licensed Laravel CRM for leads, contacts, organizations, pipelines, quotes, products and email.

## What it deploys

| Service | Source | Data |
|---|---|---|
| **Krayin CRM** | this repo's `Dockerfile`: Krayin **v2.2.8** (commit `ed6deeb`, verified at build) on the official `php:8.3.36-apache-trixie` image, pinned by digest | volume at `/var/www/html/storage` (uploads, imports, sessions, cache) |
| **MySQL** | Railway's MySQL | volume at `/var/lib/mysql` (all CRM data) |

The Krayin service gets a public `*.up.railway.app` domain and a health check on `/up`. One container runs Apache, a queue worker (data imports and exports) and Laravel's scheduler (marketing campaigns).

## Variables

| Variable | Default | Notes |
|---|---|---|
| `ADMIN_EMAIL` | *(you enter it)* | Login email of the first admin. The only prompt. |
| `ADMIN_PASSWORD` | `${{secret(20,"…letters and digits…")}}` | First admin's password, generated per deploy. Read it in the Krayin service's **Variables** tab. Used only on the first start. |
| `APP_KEY` | `base64:${{secret(43,"…letters and digits…")}}=` | Laravel's 32-byte encryption key, generated per deploy. Never change it after deploy. |
| `APP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Public URL used in links and uploads. Change it if you add a custom domain. |
| `DB_*` | references to `${{MySQL.…}}` | Private-network connection to the bundled MySQL. |
| `PORT` | `8080` | Port Apache listens on. |

The start script also sets: `APP_ENV=production`, `APP_DEBUG=false`, `APP_TIMEZONE=UTC`, `APP_LOCALE=en`, `APP_CURRENCY=USD`, `QUEUE_CONNECTION=database`, file cache and sessions on the volume, logs to the deploy log, and `MAIL_MAILER=log` (mail is written to the log until you configure SMTP). Any of them can be overridden with a service variable, for example `APP_TIMEZONE=Europe/Berlin`.

Optional settings you can add later as variables on the Krayin service: SMTP (`MAIL_MAILER=smtp`, `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_ENCRYPTION`, `MAIL_FROM_ADDRESS`), inbound mail (`MAIL_RECEIVER_DRIVER=webklex-imap` plus `IMAP_*`, or SendGrid with `MAIL_RECEIVER_INBOUND_TOKEN`), and Google contacts sync (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI`). See Krayin's [`.env.example`](https://github.com/krayin/laravel-crm/blob/v2.2.8/.env.example).

## After deploy

1. Wait for the first deploy to finish (the first start creates the database tables, about 30 seconds).
2. Open the Krayin service's **Variables** tab and copy `ADMIN_PASSWORD`.
3. Open `https://YOUR-DOMAIN/admin/login` and sign in with `ADMIN_EMAIL` and that password. Change the password under **Settings > Users**.

There is no `admin@example.com` / `admin123` account: the first start seeds Krayin's base data and puts your admin in place of upstream's default user, in one database transaction, before the web server opens. The web installer stays closed. Later starts only run new migrations and never reseed.

## How it differs from a plain `krayin-crm:install`

- `railway-install.php` runs Krayin's own seeders once, on an empty database only, and records Krayin's "installation completed" flag. It never runs `migrate:fresh` or `db:seed` on a database that already has users.
- Apache trusts `X-Real-IP` only from Railway's private ranges, so Krayin's per-address login limit counts visitors, not the proxy.
- Upstream schedules the inbound-mail poll every 5 minutes, and that poll fails under the default SendGrid receiver. Here it runs only when `MAIL_RECEIVER_DRIVER=webklex-imap`.
- Krayin's install hook that reports the domain and admin email to `updates.krayincrm.com` doesn't run, because the web installer is never used.

## Updates

Each Krayin release becomes a commit to `main` here that bumps `KRAYIN_VERSION`, `KRAYIN_COMMIT` and the pinned base image, with a [`CHANGELOG.md`](CHANGELOG.md) entry (breaking changes first). Railway then shows an "update available" notice in projects deployed from this template, and you choose when to apply it. Back up the MySQL volume first: migrations run on start and only go forward.

## Licence

Krayin CRM is MIT, by Webkul. This wrapper is MIT too: a Dockerfile, an entrypoint, an install helper and Apache/PHP settings.
