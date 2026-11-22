# RideSync Backend

FastAPI + MariaDB REST API for group motorcycle convoy sync.

There are two ways to run it. Always test on your own machine first (Part 1 or 2), then put it on a server (Part 3).

| | Where the API runs | Where the database is |
|---|---|---|
| Part 1: all local | your machine | your machine (Docker) |
| Part 2: local API, real database | your machine | your server, through an SSH tunnel |
| Part 3: deployed | your server | your server |

Anyone can run their own copy: nothing in this repo points to our server. All settings live in `backend/.env`, which is never committed.

---

## Setup (all parts)

Run inside `backend/`:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
Copy-Item .env.example .env
```

*(Linux: `python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements-dev.txt && cp .env.example .env`.)*

Open `.env` and set a password in `DB_PASSWORD`.

---

## Part 1: Everything on your machine

Needs Docker. This starts a MariaDB just for testing and creates the 4 tables:

```powershell
docker compose up -d
```

Then start the API:

```powershell
uvicorn app.main:app --reload --port 8000
```

Check it:

- Health and database status: `http://127.0.0.1:8000/health` (should say `connected`)
- Test page where you can try every endpoint: `http://127.0.0.1:8000/docs`

Stop the database with `docker compose down` (your data stays, `docker compose down -v` deletes it).

No Docker? Install MariaDB yourself, create the database and user from Part 2 using `IDENTIFIED VIA mysql_native_password USING PASSWORD('...')`, set `DB_PORT=3306` in `.env`, and run `.\start.bat` (or `python init_db.py`).

---

## Part 2: Local API, real database (SSH tunnel)

On the server, create the database and a user that only the server itself can use (change the password):

```sql
CREATE DATABASE IF NOT EXISTS ridesync
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'ridesync_app'@'localhost' IDENTIFIED BY 'your_strong_password';
CREATE USER IF NOT EXISTS 'ridesync_app'@'127.0.0.1' IDENTIFIED BY 'your_strong_password';
GRANT ALL PRIVILEGES ON ridesync.* TO 'ridesync_app'@'localhost';
GRANT ALL PRIVILEGES ON ridesync.* TO 'ridesync_app'@'127.0.0.1';
FLUSH PRIVILEGES;
```

On your machine, open a tunnel in a separate terminal. It lets you reach the server's database without opening port 3306 to the internet:

```powershell
ssh -L 3307:127.0.0.1:3306 <user>@<server-ip> -N
```

Keep `.env` as `DB_HOST=127.0.0.1`, `DB_PORT=3307` and use the real password. Create the tables once, then start the API:

```powershell
python init_db.py
uvicorn app.main:app --reload --port 8000
```

Do not run the Docker database at the same time, both use port 3307.

---

## Part 3: Put it on your server (Debian)

Do this after Part 1 or 2 works. Replace `api.example.com` with your own domain name.

**1. Get the code and install it**

```bash
sudo apt update && sudo apt install -y python3-venv nginx certbot python3-certbot-nginx git
sudo git clone <your-repo-url> /srv/ridesync
cd /srv/ridesync/backend
sudo python3 -m venv .venv
sudo .venv/bin/pip install -r requirements.txt
sudo cp .env.example .env
sudo nano .env
```

On the server the database is on the same machine, so use `DB_HOST=127.0.0.1` and `DB_PORT=3306`. Then create the tables once:

```bash
sudo .venv/bin/python init_db.py
```

**2. Keep it running (systemd)**

Create `/etc/systemd/system/ridesync.service`:

```ini
[Unit]
Description=RideSync API
After=network.target mariadb.service

[Service]
WorkingDirectory=/srv/ridesync/backend
ExecStart=/srv/ridesync/backend/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ridesync
sudo systemctl status ridesync
```

The API listens only on `127.0.0.1`, so nobody can reach it directly. nginx (next step) is the front door.

**3. nginx in front of it**

Create `/etc/nginx/sites-available/ridesync`:

```nginx
server {
    listen 80;
    server_name api.example.com;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/ridesync /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

**4. HTTPS (needs a domain name)**

Point your domain at the server's public IP first. Then:

```bash
sudo certbot --nginx -d api.example.com
```

**5. Open the ports**

Allow ports 80 and 443 in two places. Both must allow it or nothing gets through:

- Oracle Cloud: the instance's security list or network security group (ingress rules).
- The server's own firewall.

**6. Check it**

```bash
curl https://api.example.com/health
```

It should answer `{"status":"ok","database":"connected"}`.

**Updating later**

```bash
cd /srv/ridesync && sudo git pull
sudo backend/.venv/bin/pip install -r backend/requirements.txt
sudo systemctl restart ridesync
```

---

## Endpoints

| Action | Method & Path |
|---|---|
| Host creates a ride | `POST /rides` |
| Rider joins with code | `POST /rides/{code}/join` |
| Send latest GPS position | `POST /rides/{code}/position` |
| Read everyone's positions | `GET /rides/{code}/positions` |
| End ride (host only) | `POST /rides/{code}/end` |

## Tests

They use a fake in-memory store, so no database is needed:

```powershell
pytest
```
