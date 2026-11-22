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
        self.rides: dict[int, dict] = {}
        self.members: set[tuple[int, int]] = set()
        self.positions: dict[tuple[int, int], dict] = {}


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
        elif q.startswith("INSERT INTO users"):
            uid = self.state.next_user_id
            self.state.next_user_id += 1
            self.state.users[uid] = {"id": uid, "name": params[0]}
            self.lastrowid = uid
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
            ride_id, user_id, lat, lng, speed, battery = params
            self.state.positions[(ride_id, user_id)] = {
                "ride_id": ride_id,
                "user_id": user_id,
                "latitude": lat,
                "longitude": lng,
                "speed": speed,
                "battery": battery,
                "updated_at": self.state.now,
            }
        elif q.startswith("SELECT updated_at FROM positions"):
            pos = self.state.positions[(params[0], params[1])]
            self._rows = [{"updated_at": pos["updated_at"]}]
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


def test_schema_sql_defines_four_core_tables() -> None:
    statements = read_table_sql()
    assert len(statements) == 4
    joined = "\n".join(statements)
    for table in ("users", "rides", "ride_members", "positions"):
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
                "battery_percent": 80,
            },
        )

        positions = client.get(f"/rides/{code}/positions")
        assert positions.status_code == 200
        riders = positions.json()["riders"]
        assert len(riders) == 2
        by_id = {item["rider"]["id"]: item for item in riders}
        assert by_id[host_id]["age_seconds"] == 75
        assert by_id[host_id]["is_stale"] is True
        assert by_id[rider_id]["age_seconds"] == 0
        assert by_id[rider_id]["is_stale"] is False

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
