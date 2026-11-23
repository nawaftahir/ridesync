"""Simple MariaDB connection helpers for RideSync."""

import os
from pathlib import Path
import re
from dotenv import load_dotenv
import pymysql
from pymysql.cursors import DictCursor

BACKEND_DIR = Path(__file__).resolve().parent.parent
SCHEMA_PATH = BACKEND_DIR / "sql" / "schema.sql"

# Load settings from backend/.env when running locally.
load_dotenv(BACKEND_DIR / ".env")


def _db_settings():
    port_text = os.getenv("DB_PORT", "3306").strip()
    return {
        "host": os.getenv("DB_HOST", "127.0.0.1").strip(),
        "port": int(port_text) if port_text else 3306,
        "database": os.getenv("DB_NAME", "ridesync").strip(),
        "user": os.getenv("DB_USER", "ridesync_app").strip(),
        "password": os.getenv("DB_PASSWORD", ""),
    }


def is_db_configured() -> bool:
    """Return True when .env has a real database password set."""
    cfg = _db_settings()
    password = str(cfg["password"])
    return bool(
        cfg["host"]
        and cfg["database"]
        and cfg["user"]
        and password
        and password != "change_me_local_or_tunnel_password"
    )


def open_connection(use_database: bool = True):
    """Open a new MariaDB connection that returns rows as Python dicts."""
    cfg = _db_settings()
    options = {
        "host": cfg["host"],
        "port": cfg["port"],
        "user": cfg["user"],
        "password": cfg["password"],
        "charset": "utf8mb4",
        "cursorclass": DictCursor,
        "autocommit": False,
        "connect_timeout": 5,
        "read_timeout": 10,
        "write_timeout": 10,
    }
    if use_database:
        options["database"] = cfg["database"]
    return pymysql.connect(**options)


def get_db():
    """Provide one DB connection per FastAPI request, then commit and close."""
    conn = open_connection()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def get_db_status() -> str:
    """Check whether MariaDB is configured and reachable right now."""
    if not is_db_configured():
        return "not_configured"
    conn = None
    try:
        conn = open_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        return "connected"
    except pymysql.MySQLError:
        return "unreachable"
    finally:
        if conn is not None:
            conn.close()


def read_table_sql(schema_path: Path = SCHEMA_PATH) -> list[str]:
    """Read the CREATE TABLE statements from sql/schema.sql."""
    raw = schema_path.read_text(encoding="utf-8")
    lines = [line for line in raw.splitlines() if not line.strip().startswith("--")]
    statements = []
    for part in "\n".join(lines).split(";"):
        sql = part.strip()
        if not sql:
            continue
        upper = sql.upper()
        if upper.startswith("CREATE DATABASE") or upper.startswith("USE "):
            continue
        statements.append(sql)
    return statements


def init_db() -> str:
    """Create the RideSync tables in MariaDB if they do not exist yet."""
    cfg = _db_settings()
    db_name = str(cfg["database"])
    if not re.fullmatch(r"[A-Za-z0-9_]+", db_name):
        raise ValueError("Invalid DB_NAME: use letters, numbers, and underscores only")

    # Try creating the database first if the user has permission; skip if already created.
    conn = None
    try:
        conn = open_connection(use_database=False)
        with conn.cursor() as cur:
            cur.execute(
                f"CREATE DATABASE IF NOT EXISTS `{db_name}` "
                "CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
            )
        conn.commit()
    except pymysql.MySQLError:
        pass
    finally:
        if conn is not None:
            conn.close()

    conn = open_connection(use_database=True)
    try:
        with conn.cursor() as cur:
            for sql in read_table_sql():
                cur.execute(sql)
            # Safe migration for databases created before destination coordinates existed.
            cur.execute(
                "ALTER TABLE rides "
                "ADD COLUMN IF NOT EXISTS dest_lat DOUBLE NULL AFTER destination, "
                "ADD COLUMN IF NOT EXISTS dest_lng DOUBLE NULL AFTER dest_lat"
            )
            # Safe migration for databases created before rider heading existed.
            cur.execute(
                "ALTER TABLE positions "
                "ADD COLUMN IF NOT EXISTS heading DOUBLE NOT NULL DEFAULT 0 AFTER speed"
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    return f"{db_name} on {cfg['host']}:{cfg['port']}"
