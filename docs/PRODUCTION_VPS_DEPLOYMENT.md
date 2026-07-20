# Production VPS Deployment

This guide assumes a small Ubuntu VPS with 2 CPU cores, 2 GB RAM, and 40 GB
storage. The app can run in less space, but the production textbook PDFs,
extracted page assets, PostgreSQL seed, and Qdrant seed need the larger disk.
Add swap, keep only required services running, and monitor disk space.

## What Will Run

- Nginx on the host: public HTTP/HTTPS entrypoint.
- Docker Compose: app services.
- `web`: React static site, private on `127.0.0.1:3000`.
- `api`: Rust Axum API, private on `127.0.0.1:4000`.
- `postgres`: relational source of truth.
- `qdrant`: textbook vector index.
- `redis`: small cache/queue support.

Do not expose Postgres, Redis, or Qdrant to the public internet.

## 1. Buy And Open The Server

Choose Ubuntu 24.04 LTS, Ubuntu 22.04 LTS, or Debian 13.

From your computer:

```bash
ssh root@YOUR_SERVER_IP
```

If SSH asks about fingerprint, type `yes`.

## 2. Point Your Domain

In your domain DNS panel, create:

```text
A     @       YOUR_SERVER_IP
A     www     YOUR_SERVER_IP
```

DNS can take a few minutes to a few hours. You can deploy before DNS finishes,
but HTTPS will only work after the domain points to the VPS.

## 3. Bootstrap Ubuntu

On the VPS:

```bash
apt-get update
apt-get install -y git
git clone https://github.com/Razin-developer/RightAnswer.git /opt/right-answer
cd /opt/right-answer
bash deploy/scripts/bootstrap-ubuntu.sh
```

This installs Docker, Docker Compose, Git LFS, Nginx, Certbot, firewall rules,
and a 2 GB swap file.

## 4. Create Production Environment

```bash
cd /opt/right-answer
cp .env.production.example .env.production
nano .env.production
```

Change these values:

```text
POSTGRES_PASSWORD=long-random-password
JWT_SECRET=another-long-random-secret
DOMAIN=your-domain.com
APP_URL=https://your-domain.com
CORS_ORIGINS=https://your-domain.com
VITE_API_URL=https://your-domain.com/api
OPENROUTER_API_KEY=your-key
```

Generate random secrets with:

```bash
openssl rand -base64 48
```

Save in nano with `Ctrl+O`, press Enter, then exit with `Ctrl+X`.

## 5. Configure Nginx

Copy the template:

```bash
cp deploy/nginx/rightanswer.conf /etc/nginx/sites-available/rightanswer
nano /etc/nginx/sites-available/rightanswer
```

Replace:

```text
example.com www.example.com
```

with your real domain, for example:

```text
rightanswer.example.com
```

Enable it:

```bash
ln -sf /etc/nginx/sites-available/rightanswer /etc/nginx/sites-enabled/rightanswer
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
```

## 6. Build And Start Containers

```bash
cd /opt/right-answer
bash deploy/scripts/deploy.sh
```

Check status:

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml ps
bash deploy/scripts/verify.sh
```

## 7. Enable HTTPS

Only run this after DNS points to the VPS:

```bash
certbot --nginx -d your-domain.com
```

If you also use `www`, run:

```bash
certbot --nginx -d your-domain.com -d www.your-domain.com
```

Choose the redirect-to-HTTPS option when Certbot asks.

Verify renewal:

```bash
certbot renew --dry-run
```

## 8. Migrate Textbook Vectors To Qdrant

If the repository includes production seeds, restore them first. The deploy
script runs `git lfs pull --include="storage/**"` so the VPS receives the real
textbook files and seed archives instead of Git LFS pointer files.

```bash
bash deploy/scripts/restore-seed.sh
```

After Postgres contains textbook embeddings:

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml run --rm api migrate_qdrant
```

Success looks like:

```text
Migrated N PostgreSQL embeddings into Qdrant collection right_answer_textbook_chunks.
```

If it stops with a count mismatch, do not switch traffic. The migrator is
designed to fail instead of silently losing vector data.

## 9. Check The Live Site

Open:

```text
https://your-domain.com
https://your-domain.com/api/health
```

You can also check from the VPS:

```bash
curl -fsS http://127.0.0.1:4000/health
curl -I http://127.0.0.1:3000
```

## 10. Updating Later

```bash
cd /opt/right-answer
git pull
bash deploy/scripts/deploy.sh
```

If the update changes vectors or textbook data, rerun:

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml run --rm api migrate_qdrant
```

## 11. Backups

Run manually:

```bash
cd /opt/right-answer
bash deploy/scripts/backup.sh
```

Create a daily backup cron:

```bash
crontab -e
```

Add:

```text
15 2 * * * cd /opt/right-answer && bash deploy/scripts/backup.sh >> /opt/right-answer/backups/backup.log 2>&1
```

Download backups to your computer sometimes:

```bash
scp root@YOUR_SERVER_IP:/opt/right-answer/backups/*.gz .
```

## 12. Useful Debug Commands

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml ps
docker compose --env-file .env.production -f docker-compose.prod.yml logs -f api
docker compose --env-file .env.production -f docker-compose.prod.yml logs -f qdrant
docker stats
df -h
free -h
systemctl status nginx
nginx -t
```

Restart one service:

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml restart api
```

Stop everything:

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml down
```

Do not delete Docker volumes unless you intentionally want to remove the
database and Qdrant data.

## 13. When To Upgrade The VPS

Upgrade from 2 GB RAM when:

- The Linux OOM killer stops containers.
- Qdrant queries become slow under real users.
- Disk usage goes above 75%.
- Textbook vectors grow far beyond the current collection.

Recommended next step is 2 CPU / 4 GB RAM / 40 GB storage.
