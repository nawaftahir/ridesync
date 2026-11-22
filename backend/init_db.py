"""Create RideSync MariaDB tables defined in sql/schema.sql."""

import pymysql

from app.db import _db_settings, init_db, is_db_configured


def main() -> None:
    if not is_db_configured():
        raise SystemExit(
            "Configure backend/.env (DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD) first."
        )
    try:
        target = init_db()
    except pymysql.MySQLError as exc:
        code = exc.args[0] if exc.args else None
        if code == 2059:
            cfg = _db_settings()
            user = cfg["user"]
            db_name = cfg["database"]
            raise SystemExit(
                "MariaDB asked for Windows GSSAPI login (not supported by PyMySQL).\n"
                "Run this in MariaDB as root to use a normal password instead:\n"
                f"  CREATE OR REPLACE USER '{user}'@'127.0.0.1' "
                "IDENTIFIED VIA mysql_native_password USING PASSWORD('your_env_password');\n"
                f"  GRANT ALL PRIVILEGES ON {db_name}.* TO '{user}'@'127.0.0.1'; FLUSH PRIVILEGES;"
            ) from exc
        raise SystemExit(f"Could not connect to MariaDB: {exc}") from exc

    print(f"Schema initialized in {target}.")


if __name__ == "__main__":
    main()
