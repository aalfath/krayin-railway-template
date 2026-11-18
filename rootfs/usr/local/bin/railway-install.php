<?php
/**
 * Boot-time helper for Krayin CRM on Railway.
 *
 *   wait     block until the database answers (up to ~3 minutes)
 *   locked CMD...  run CMD while holding a MySQL advisory lock
 *   state    print "installed" or "empty"
 *   install  seed Krayin's base data and create the first admin from
 *            ADMIN_EMAIL / ADMIN_PASSWORD, in one transaction, so the
 *            upstream admin@example.com / admin123 account never exists.
 *            Unlike `krayin-crm:install` it never runs migrate:fresh and
 *            never re-seeds an installed database.
 */
declare(strict_types=1);

$mode = $argv[1] ?? '';

if ($mode === 'wait') {
    $dsn = sprintf('mysql:host=%s;port=%s', getenv('DB_HOST'), getenv('DB_PORT') ?: '3306');
    for ($i = 1; $i <= 90; $i++) {
        try {
            new PDO($dsn, getenv('DB_USERNAME') ?: 'root', getenv('DB_PASSWORD') ?: '', [PDO::ATTR_TIMEOUT => 5]);
            fwrite(STDERR, "[railway] database reachable\n");
            exit(0);
        } catch (Throwable $e) {
            fwrite(STDERR, "[railway] waiting for database ($i): ".$e->getMessage()."\n");
            sleep(2);
        }
    }
    exit(1);
}

if ($mode === 'locked') {
    // Hold a MySQL advisory lock while running the given command, so two
    // deployments that start together (first deploy, overlapping redeploys)
    // never migrate or install the same database at the same time.
    $dsn = sprintf('mysql:host=%s;port=%s', getenv('DB_HOST'), getenv('DB_PORT') ?: '3306');
    $pdo = new PDO($dsn, getenv('DB_USERNAME') ?: 'root', getenv('DB_PASSWORD') ?: '', [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    $name = 'krayin-railway-boot-'.(getenv('DB_DATABASE') ?: 'railway');
    fwrite(STDERR, "[railway] waiting for the boot lock\n");
    if ((int) $pdo->query('SELECT GET_LOCK('.$pdo->quote($name).', 900)')->fetchColumn() !== 1) {
        fwrite(STDERR, "[railway] ERROR: could not get the boot lock within 15 minutes\n");
        exit(1);
    }
    $cmd = implode(' ', array_map('escapeshellarg', array_slice($argv, 2)));
    passthru($cmd, $code);
    $pdo->query('SELECT RELEASE_LOCK('.$pdo->quote($name).')');
    exit($code);
}

require '/var/www/html/vendor/autoload.php';
$app = require '/var/www/html/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Webkul\Installer\Database\Seeders\DatabaseSeeder as KrayinSeeder;
use Webkul\Installer\Helpers\DatabaseManager;

function isInstalled(): bool
{
    if (Schema::hasTable('core_config')
        && DB::table('core_config')->where('code', DatabaseManager::INSTALLATION_COMPLETED_FLAG)->exists()) {
        return true;
    }

    return Schema::hasTable('users') && DB::table('users')->count() > 0;
}

if ($mode === 'state') {
    echo isInstalled() ? "installed\n" : "empty\n";
    exit(0);
}

if ($mode === 'install') {
    if (isInstalled()) {
        fwrite(STDERR, "[railway] already installed, nothing to do\n");
        exit(0);
    }

    $email = trim((string) getenv('ADMIN_EMAIL'));
    $password = (string) getenv('ADMIN_PASSWORD');
    $name = trim((string) (getenv('ADMIN_NAME') ?: 'Admin'));

    if (! filter_var($email, FILTER_VALIDATE_EMAIL)) {
        fwrite(STDERR, "[railway] ERROR: ADMIN_EMAIL is not a valid email address\n");
        exit(1);
    }
    if (strlen($password) < 8) {
        fwrite(STDERR, "[railway] ERROR: ADMIN_PASSWORD must be at least 8 characters\n");
        exit(1);
    }

    DB::transaction(function () use ($email, $password, $name) {
        app(KrayinSeeder::class)->run(['locale' => config('app.locale', 'en')]);

        DB::table('users')->where('id', 1)->update([
            'name'       => $name,
            'email'      => $email,
            'password'   => password_hash($password, PASSWORD_BCRYPT, ['cost' => 10]),
            'updated_at' => now(),
        ]);

        DB::table('core_config')->updateOrInsert(
            ['code' => DatabaseManager::INSTALLATION_COMPLETED_FLAG],
            ['value' => '1', 'created_at' => now(), 'updated_at' => now()]
        );
    });

    if (DB::table('users')->where('email', 'admin@example.com')->exists()) {
        fwrite(STDERR, "[railway] ERROR: the default admin account still exists\n");
        exit(1);
    }

    fwrite(STDERR, "[railway] installed: admin account {$email} created\n");
    exit(0);
}

fwrite(STDERR, "usage: railway-install.php wait|locked CMD...|state|install\n");
exit(2);
