"""API and schema tests for the RideSync backend."""

from datetime import datetime, timedelta, timezone
from fastapi.testclient import TestClient
import pytest
import pymysql

import init_db
from app.db import get_db, is_db_configured, read_table_sql
from app.main import app


class FakeDbState:
    """In-memory tables used to test FastAPI routes without a live MariaDB server."""

    def __init__(self) -> None:
        self.now = datetime(2026, 11, 14, 17, 0, tzinfo=timezone.utc)
        self.next_user_id = 1
        self.next_ride_id = 1
        self.users: dict[int, dict] = {}
        self.tokens: dict[str, dict] = {}
        self.rides: dict[int, dict] = {}
        self.members: set[tuple[int, int]] = set()
        self.positions: dict[tuple[int, int], dict] = {}
        self.alerts: list[dict] = []
        self.next_alert_id = 1


class FakeCursor:
    """Minimal DictCursor clone handling the SQL queries used by app/main.py."""

    def __init__(self, state: FakeDbState) -> None:
        self.state = state
        self.lastrowid = 0
        self._rows: list[dict] = []

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def execute(self, sql: str, params=()):
        q = " ".join(sql.split())
        self._rows = []

        if q.startswith("SELECT id, name FROM users WHERE id ="):
            user = self.state.users.get(params[0])
            if user:
                self._rows = [{"id": user["id"], "name": user["name"]}]
        elif q.startswith("SELECT id, email, name, created_at FROM users WHERE id ="):
            user = self.state.users.get(params[0])
            if user:
                self._rows = [dict(user)]
        elif q.startswith("SELECT id, email, password_hash, name, created_at FROM users WHERE email ="):
            for user in self.state.users.values():
                if user.get("email") == params[0]:
                    self._rows = [dict(user)]
                    break
        elif q.startswith("INSERT INTO users (email, password_hash, name) VALUES (NULL, '', %s)"):
            uid = self.state.next_user_id
            self.state.next_user_id += 1
            self.state.users[uid] = {
                "id": uid,
                "email": None,
                "password_hash": "",
                "name": params[0],
                "created_at": self.state.now,
            }
            self.lastrowid = uid
        elif q.startswith("INSERT INTO users (email, password_hash, name) VALUES (%s, %s, %s)"):
            email, pw_hash, name = params
            if any(u.get("email") == email for u in self.state.users.values()):
                raise pymysql.IntegrityError(1062, "Duplicate email")
            uid = self.state.next_user_id
            self.state.next_user_id += 1
            self.state.users[uid] = {
                "id": uid,
                "email": email,
                "password_hash": pw_hash,
                "name": name,
                "created_at": self.state.now,
            }
            self.lastrowid = uid
        elif q.startswith("UPDATE users SET name = %s WHERE id = %s"):
            name, uid = params
            if uid in self.state.users:
                self.state.users[uid]["name"] = name
        elif q.startswith("INSERT INTO auth_tokens"):
            token_hash, user_id, days = params
            self.state.tokens[token_hash] = {
                "token_hash": token_hash,
                "user_id": user_id,
                "expires_at": self.state.now + timedelta(days=days),
            }
        elif q.startswith("SELECT u.id, u.email, u.name, u.created_at FROM auth_tokens"):
            token_row = self.state.tokens.get(params[0])
            if token_row and token_row["expires_at"] > self.state.now:
                user = self.state.users.get(token_row["user_id"])
                if user:
                    self._rows = [dict(user)]
        elif q.startswith("DELETE FROM auth_tokens WHERE token_hash ="):
            self.state.tokens.pop(params[0], None)
        elif q.startswith("SELECT id, code, destination, dest_lat, dest_lng, host_id, started_at, ended_at FROM rides WHERE code ="):
            for ride in self.state.rides.values():
                if ride["code"] == params[0]:
                    self._rows = [dict(ride)]
                    break
        elif q.startswith("INSERT INTO rides"):
            code, destination, dest_lat, dest_lng, host_id = params
            if any(r["code"] == code for r in self.state.rides.values()):
                raise pymysql.IntegrityError(1062, "Duplicate code")
            rid = self.state.next_ride_id
            self.state.next_ride_id += 1
            self.state.rides[rid] = {
                "id": rid,
                "code": code,
                "destination": destination,
                "dest_lat": dest_lat,
                "dest_lng": dest_lng,
                "host_id": host_id,
                "started_at": self.state.now,
                "ended_at": None,
            }
            self.lastrowid = rid
        elif q.startswith("INSERT INTO ride_members") or q.startswith("INSERT IGNORE INTO ride_members"):
            self.state.members.add((params[0], params[1]))
        elif q.startswith("SELECT started_at FROM rides WHERE id ="):
            ride = self.state.rides[params[0]]
            self._rows = [{"started_at": ride["started_at"]}]
        elif q.startswith("SELECT 1 FROM ride_members"):
            if (params[0], params[1]) in self.state.members:
                self._rows = [{"1": 1}]
        elif q.startswith("INSERT INTO positions"):
            ride_id, user_id, lat, lng, speed, heading, battery = params
            self.state.positions[(ride_id, user_id)] = {
                "ride_id": ride_id,
                "user_id": user_id,
                "latitude": lat,
                "longitude": lng,
                "speed": speed,
                "heading": heading,
                "battery": battery,
                "updated_at": self.state.now,
            }
        elif q.startswith("SELECT updated_at FROM positions"):
            pos = self.state.positions[(params[0], params[1])]
            self._rows = [{"updated_at": pos["updated_at"]}]
        elif q.startswith("SELECT u.name FROM ride_members"):
            if (params[0], params[1]) in self.state.members:
                user = self.state.users.get(params[1])
                if user:
                    self._rows = [{"name": user["name"]}]
        elif q.startswith("INSERT INTO ride_alerts"):
            aid = self.state.next_alert_id
            self.state.next_alert_id += 1
            self.state.alerts.append(
                {
                    "id": aid,
                    "ride_id": params[0],
                    "user_id": params[1],
                    "alert_type": params[2],
                    "message": params[3],
                    "created_at": self.state.now,
                }
            )
            self.lastrowid = aid
        elif q.startswith("SELECT created_at FROM ride_alerts"):
            alert = next(a for a in self.state.alerts if a["id"] == params[0])
            self._rows = [{"created_at": alert["created_at"]}]
        elif q.startswith("SELECT a.id, a.user_id"):
            ride_id = params[0]
            matching = [a for a in self.state.alerts if a["ride_id"] == ride_id]
            if matching:
                latest = matching[-1]
                age = max(0, int((self.state.now - latest["created_at"]).total_seconds()))
                if age <= 300:
                    self._rows = [
                        {
                            "id": latest["id"],
                            "user_id": latest["user_id"],
                            "sender_name": self.state.users[latest["user_id"]]["name"],
                            "alert_type": latest["alert_type"],
                            "message": latest["message"],
                            "created_at": latest["created_at"],
                            "age_seconds": age,
                        }
                    ]
        elif q.startswith("SELECT u.id AS user_id"):
            ride_id = params[0]
            rows = []
            for (r_id, u_id), pos in sorted(self.state.positions.items()):
                if r_id != ride_id:
                    continue
                age = max(0, int((self.state.now - pos["updated_at"]).total_seconds()))
                rows.append(
                    {
                        "user_id": u_id,
                        "name": self.state.users[u_id]["name"],
                        "latitude": pos["latitude"],
                        "longitude": pos["longitude"],
                        "speed": pos["speed"],
                        "heading": pos["heading"],
                        "battery": pos["battery"],
                        "updated_at": pos["updated_at"],
                        "age_seconds": age,
                    }
                )
            self._rows = rows
        elif q.startswith("UPDATE rides SET ended_at = NOW()"):
            self.state.rides[params[0]]["ended_at"] = self.state.now
        elif q.startswith("SELECT ended_at FROM rides WHERE id ="):
            ride = self.state.rides[params[0]]
            self._rows = [{"ended_at": ride["ended_at"]}]
        elif q.startswith("SELECT r.code, r.destination, r.dest_lat"):
            uid = params[0]
            rows = []
            for ride in self.state.rides.values():
                if (ride["id"], uid) not in self.state.members:
                    continue
                if ride["ended_at"] is None:
                    continue
                rider_count = sum(
                    1 for (r_id, _) in self.state.members if r_id == ride["id"]
                )
                duration_mins = max(
                    0,
                    int((ride["ended_at"] - ride["started_at"]).total_seconds() // 60),
                )
                rows.append(
                    {
                        "code": ride["code"],
                        "destination": ride["destination"],
                        "dest_lat": ride["dest_lat"],
                        "dest_lng": ride["dest_lng"],
                        "host_id": ride["host_id"],
                        "host_name": self.state.users[ride["host_id"]]["name"],
                        "started_at": ride["started_at"],
                        "ended_at": ride["ended_at"],
                        "duration_minutes": duration_mins,
                        "rider_count": rider_count,
                    }
                )
            rows.sort(key=lambda r: r["ended_at"], reverse=True)
            self._rows = rows[:50]
        else:
            raise AssertionError(f"Unhandled test SQL: {q}")

    def fetchone(self):
        return self._rows[0] if self._rows else None

    def fetchall(self):
        return list(self._rows)


class FakeConnection:
    def __init__(self, state: FakeDbState) -> None:
        self.state = state

    def cursor(self):
        return FakeCursor(self.state)


def _use_fake_db(state: FakeDbState):
    def override_get_db():
        yield FakeConnection(state)

    app.dependency_overrides[get_db] = override_get_db


def test_schema_sql_defines_core_tables() -> None:
    statements = read_table_sql()
    assert len(statements) == 6
    joined = "\n".join(statements)
    for table in ("users", "rides", "ride_members", "positions", "ride_alerts", "auth_tokens"):
        assert f"CREATE TABLE IF NOT EXISTS {table}" in joined


def test_root_and_health_endpoints(monkeypatch) -> None:
    monkeypatch.setenv("DB_PASSWORD", "")
    assert is_db_configured() is False

    client = TestClient(app)
    root = client.get("/")
    assert root.status_code == 200
    assert root.json()["docs"] == "/docs"

    health = client.get("/health")
    assert health.status_code == 200
    assert health.json() == {"status": "ok", "database": "not_configured"}

    invite = client.get("/join/k7mpqw")
    assert invite.status_code == 200
    assert "ridesync://join/K7MPQW" in invite.text
    assert "intent://join/K7MPQW" in invite.text
    assert client.get("/join/bad!code").status_code == 400

    monkeypatch.delenv("ANDROID_APP_SHA256", raising=False)
    assert client.get("/.well-known/assetlinks.json").json() == []
    monkeypatch.setenv("ANDROID_APP_SHA256", "aa:bb:cc")
    links = client.get("/.well-known/assetlinks.json")
    assert links.status_code == 200
    assert links.json()[0]["target"]["sha256_cert_fingerprints"] == ["AA:BB:CC"]


def test_ride_lifecycle_and_position_upsert() -> None:
    state = FakeDbState()
    _use_fake_db(state)
    try:
        client = TestClient(app)

        created = client.post(
            "/rides",
            json={
                "destination": "Daman-e-Koh, Islamabad",
                "dest_lat": 33.7394,
                "dest_lng": 73.0558,
                "host_name": "Nawaf",
            },
        )
        assert created.status_code == 201
        ride = created.json()
        code = ride["code"]
        host_id = ride["host_id"]
        assert len(code) == 6
        assert ride["dest_lat"] == 33.7394
        assert ride["dest_lng"] == 73.0558

        joined = client.post(f"/rides/{code.lower()}/join", json={"name": "Bilal"})
        assert joined.status_code == 200
        bilal = joined.json()
        assert bilal["code"] == code
        assert bilal["is_host"] is False
        assert bilal["dest_lat"] == 33.7394
        assert bilal["dest_lng"] == 73.0558
        rider_id = bilal["user_id"]

        client.post(
            f"/rides/{code}/position",
            json={
                "user_id": host_id,
                "latitude": 33.7200,
                "longitude": 73.0400,
                "speed_kmh": 35,
                "battery_percent": 90,
            },
        )
        state.now += timedelta(seconds=75)
        client.post(
            f"/rides/{code}/position",
            json={
                "user_id": rider_id,
                "latitude": 33.7250,
                "longitude": 73.0450,
                "speed_kmh": 42,
                "heading_degrees": 135,
                "battery_percent": 80,
            },
        )

        alert_resp = client.post(
            f"/rides/{code}/alert",
            json={"user_id": rider_id, "alert_type": "wait"},
        )
        assert alert_resp.status_code == 201
        assert alert_resp.json()["sender_name"] == "Bilal"
        assert alert_resp.json()["alert_type"] == "wait"

        positions = client.get(f"/rides/{code}/positions")
        assert positions.status_code == 200
        payload = positions.json()
        assert payload["latest_alert"]["alert_type"] == "wait"
        assert payload["latest_alert"]["sender_name"] == "Bilal"
        riders = payload["riders"]
        assert len(riders) == 2
        by_id = {item["rider"]["id"]: item for item in riders}
        assert by_id[host_id]["age_seconds"] == 75
        assert by_id[host_id]["is_stale"] is True
        assert by_id[rider_id]["age_seconds"] == 0
        assert by_id[rider_id]["is_stale"] is False
        assert by_id[rider_id]["heading_degrees"] == 135

        assert client.post(f"/rides/{code}/end", json={"host_id": rider_id}).status_code == 403
        assert client.post(f"/rides/{code}/end", json={"host_id": host_id}).status_code == 200

        assert client.post(f"/rides/{code}/join", json={"name": "Ahmed"}).status_code == 409
        assert (
            client.post(
                f"/rides/{code}/position",
                json={"user_id": rider_id, "latitude": 33.73, "longitude": 73.05},
            ).status_code
            == 409
        )
    finally:
        app.dependency_overrides.clear()


def test_unknown_ride_non_member_and_db_error() -> None:
    state = FakeDbState()
    _use_fake_db(state)
    try:
        client = TestClient(app)
        assert client.get("/rides/ZZZZZZ/positions").status_code == 404

        code = client.post(
            "/rides", json={"destination": "Murree", "host_name": "Nawaf"}
        ).json()["code"]
        resp = client.post(
            f"/rides/{code}/position",
            json={"user_id": 999, "latitude": 33.7, "longitude": 73.0},
        )
        assert resp.status_code == 403
    finally:
        app.dependency_overrides.clear()

    class BrokenDb:
        def cursor(self):
            raise pymysql.OperationalError(2003, "Can't connect")

    def override_broken_db():
        yield BrokenDb()

    app.dependency_overrides[get_db] = override_broken_db
    try:
        client = TestClient(app)
        resp = client.post("/rides", json={"destination": "Murree", "host_name": "Nawaf"})
        assert resp.status_code == 503
        assert resp.json()["detail"] == "Database is unreachable or not configured."
    finally:
        app.dependency_overrides.clear()


def test_init_db_entrypoint(monkeypatch, capsys) -> None:
    monkeypatch.setattr(init_db, "is_db_configured", lambda: False)
    with pytest.raises(SystemExit):
        init_db.main()

    monkeypatch.setattr(init_db, "is_db_configured", lambda: True)
    monkeypatch.setattr(init_db, "init_db", lambda: "ridesync on 127.0.0.1:3306")
    init_db.main()
    assert "Schema initialized in ridesync on 127.0.0.1:3306." in capsys.readouterr().out

    def raise_gssapi() -> str:
        raise pymysql.OperationalError(2059, "Authentication plugin 'auth_gssapi_client' not configured")

    monkeypatch.setattr(init_db, "init_db", raise_gssapi)
    with pytest.raises(SystemExit) as exc_info:
        init_db.main()
    assert "mysql_native_password" in str(exc_info.value)


def test_auth_register_login_me_rides_and_logout() -> None:
    state = FakeDbState()
    _use_fake_db(state)
    try:
        client = TestClient(app)

        # Invalid email is rejected.
        bad_email = client.post(
            "/auth/register",
            json={"email": "not-an-email", "password": "secret123", "name": "Nawaf"},
        )
        assert bad_email.status_code == 400

        # Register creates account + bearer token.
        reg = client.post(
            "/auth/register",
            json={"email": "Nawaf@Example.com", "password": "secret123", "name": "Nawaf"},
        )
        assert reg.status_code == 201
        reg_body = reg.json()
        token = reg_body["access_token"]
        user_id = reg_body["user"]["id"]
        assert reg_body["token_type"] == "bearer"
        assert reg_body["user"]["email"] == "nawaf@example.com"
        assert reg_body["user"]["name"] == "Nawaf"
        assert state.users[user_id]["password_hash"].startswith("scrypt$")

        # Duplicate email fails with 409.
        dup = client.post(
            "/auth/register",
            json={"email": "nawaf@example.com", "password": "otherpassword", "name": "Other"},
        )
        assert dup.status_code == 409

        # Wrong password returns 401.
        bad_login = client.post(
            "/auth/login",
            json={"email": "nawaf@example.com", "password": "wrongpassword"},
        )
        assert bad_login.status_code == 401

        # Valid login issues fresh bearer token.
        logged_in = client.post(
            "/auth/login",
            json={"email": "nawaf@example.com", "password": "secret123"},
        )
        assert logged_in.status_code == 200
        login_token = logged_in.json()["access_token"]
        assert login_token != token
        headers = {"Authorization": f"Bearer {login_token}"}

        # /auth/me requires valid bearer token and supports display-name update.
        assert client.get("/auth/me").status_code == 401
        me = client.get("/auth/me", headers=headers)
        assert me.status_code == 200
        assert me.json()["id"] == user_id

        updated = client.patch("/auth/me", headers=headers, json={"name": "Captain Nawaf"})
        assert updated.status_code == 200
        assert updated.json()["name"] == "Captain Nawaf"

        # Hosting a ride with Bearer token reuses the signed-in user row (no guest row).
        users_before_ride = len(state.users)
        ride_resp = client.post(
            "/rides",
            headers=headers,
            json={"destination": "Monal", "host_name": "IgnoredTemp"},
        )
        assert ride_resp.status_code == 201
        assert ride_resp.json()["host_id"] == user_id
        assert ride_resp.json()["host_name"] == "Captain Nawaf"
        assert len(state.users) == users_before_ride

        # Registering a second account and joining with Bearer token links that account.
        reg2 = client.post(
            "/auth/register",
            json={"email": "bilal@example.com", "password": "secret123", "name": "Bilal"},
        )
        token2 = reg2.json()["access_token"]
        uid2 = reg2.json()["user"]["id"]
        joined = client.post(
            f"/rides/{ride_resp.json()['code']}/join",
            headers={"Authorization": f"Bearer {token2}"},
            json={"name": "IgnoredTemp"},
        )
        assert joined.status_code == 200
        assert joined.json()["user_id"] == uid2
        assert joined.json()["name"] == "Bilal"

        # Logout revokes the token immediately.
        assert client.post("/auth/logout", headers=headers).status_code == 200
        assert client.get("/auth/me", headers=headers).status_code == 401
    finally:
        app.dependency_overrides.clear()


def test_ride_history_and_rider_stats() -> None:
    state = FakeDbState()
    _use_fake_db(state)
    try:
        client = TestClient(app)
        assert client.get("/rides/history").status_code == 401

        host = client.post(
            "/auth/register",
            json={"email": "host@example.com", "password": "secret123", "name": "Nawaf"},
        ).json()
        peer = client.post(
            "/auth/register",
            json={"email": "peer@example.com", "password": "secret123", "name": "Bilal"},
        ).json()
        host_headers = {"Authorization": f"Bearer {host['access_token']}"}
        peer_headers = {"Authorization": f"Bearer {peer['access_token']}"}

        # Ride 1: hosted by Nawaf, joined by Bilal, runs 35 min then ends.
        r1 = client.post(
            "/rides",
            headers=host_headers,
            json={
                "destination": "Daman-e-Koh",
                "dest_lat": 33.7394,
                "dest_lng": 73.0558,
            },
        ).json()
        client.post(f"/rides/{r1['code']}/join", headers=peer_headers, json={})
        state.now += timedelta(minutes=35)
        client.post(
            f"/rides/{r1['code']}/end",
            headers=host_headers,
            json={"host_id": host["user"]["id"]},
        )

        # Ride 2: hosted by Bilal, joined by Nawaf, runs 50 min then ends.
        r2 = client.post(
            "/rides",
            headers=peer_headers,
            json={"destination": "Murree"},
        ).json()
        client.post(f"/rides/{r2['code']}/join", headers=host_headers, json={})
        state.now += timedelta(minutes=50)
        client.post(
            f"/rides/{r2['code']}/end",
            headers=peer_headers,
            json={"host_id": peer["user"]["id"]},
        )

        # Ride 3: still active (not ended yet) -> excluded from past rides.
        client.post(
            "/rides",
            headers=host_headers,
            json={"destination": "Active Ride"},
        )

        resp = client.get("/rides/history", headers=host_headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["stats"] == {
            "total_rides": 2,
            "hosted_rides": 1,
            "joined_rides": 1,
            "total_minutes": 85,
        }
        assert len(body["rides"]) == 2
        assert body["rides"][0]["destination"] == "Murree"
        assert body["rides"][0]["is_host"] is False
        assert body["rides"][0]["duration_minutes"] == 50
        assert body["rides"][0]["rider_count"] == 2
        assert body["rides"][1]["destination"] == "Daman-e-Koh"
        assert body["rides"][1]["is_host"] is True
        assert body["rides"][1]["duration_minutes"] == 35
        assert body["rides"][1]["dest_lat"] == 33.7394
    finally:
        app.dependency_overrides.clear()
