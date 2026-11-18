# Changelog

Breaking changes are listed first in each entry. Read the entry before you apply an update in Railway, and back up the MySQL volume first: migrations run on start and only go forward.

## v2.2.8 (2026-11-18)

- First release of this template: Krayin CRM [v2.2.8](https://github.com/krayin/laravel-crm/releases/tag/v2.2.8) (commit `ed6deebfcb8c616eaf352c893a10a6d8e666fc6e`) on `php:8.3.36-apache-trixie@sha256:a800bbd2c0aa322702259ed475556b2cbc311076a8d3c4bba9bfe96838745472`, Composer `2.11.2@sha256:0c8e663f14c94d07b3c45b175c51f5a14718508f21fe4dd7e54f09488dd0ed71`.
- Railway MySQL, `storage/` on a volume, health check on `/up`, generated `APP_KEY` and first-admin password, one prompt (`ADMIN_EMAIL`), a queue worker and the scheduler in the same container.
