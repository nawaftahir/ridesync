import secrets
from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.responses import JSONResponse
import pymysql

from app.db import get_db, get_db_status
from app.schemas import (
    CreateRideRequest,
    CreateRideResponse,
    EndRideRequest,
    EndRideResponse,
    HealthResponse,
    JoinRideRequest,
    JoinRideResponse,
    PositionUpdatedResponse,
    RidePositionsResponse,
    RiderPositionOut,
    RiderSummary,
    UpdatePositionRequest,
)

# Excludes confusing characters (0/O, 1/I) so join codes are easy to read aloud.
CODE_LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
STALE_AFTER_SECONDS = 60

app = FastAPI(
    title="RideSync API",
    version="0.1.0",
    description="Group motorcycle convoy coordination API.",
)


@app.exception_handler(pymysql.MySQLError)
def handle_database_error(_: Request, __: pymysql.MySQLError) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        content={"detail": "Database is unreachable or not configured."},
    )


def _generate_code(length: int = 6) -> str:
    return "".join(secrets.choice(CODE_LETTERS) for _ in range(length))


def _get_or_create_user(cur, user_id: int | None, name: str) -> tuple[int, str]:
    """Use an existing user ID or create a simple guest user row."""
    if user_id is not None:
        cur.execute("SELECT id, name FROM users WHERE id = %s", (user_id,))
        row = cur.fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail=f"User {user_id} was not found")
        return int(row["id"]), str(row["name"])

    cur.execute(
        "INSERT INTO users (email, password_hash, name) VALUES (NULL, '', %s)",
        (name,),
    )
    return int(cur.lastrowid), name


def _find_ride(cur, code: str) -> dict:
    """Look up a ride by join code (case-insensitive) or raise 404."""
    clean_code = code.strip().upper()
    cur.execute(
        "SELECT id, code, destination, host_id, started_at, ended_at "
        "FROM rides WHERE code = %s",
        (clean_code,),
    )
    ride = cur.fetchone()
    if ride is None:
        raise HTTPException(status_code=404, detail=f"Ride '{clean_code}' was not found")
    return ride


@app.get("/")
def read_root() -> dict[str, str]:
    return {"service": "RideSync API", "docs": "/docs"}


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status="ok", database=get_db_status())


@app.post(
    "/rides",
    response_model=CreateRideResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_ride(
    payload: CreateRideRequest, conn=Depends(get_db)
) -> CreateRideResponse:
    with conn.cursor() as cur:
        host_id, host_name = _get_or_create_user(
            cur, payload.host_id, payload.host_name
        )

        code = ""
        ride_id = 0
        for _ in range(10):
            candidate = _generate_code()
            try:
                cur.execute(
                    "INSERT INTO rides (code, destination, host_id) VALUES (%s, %s, %s)",
                    (candidate, payload.destination, host_id),
                )
                code = candidate
                ride_id = int(cur.lastrowid)
                break
            except pymysql.IntegrityError as exc:
                # 1062 = duplicate key in MariaDB; try another random code.
                if exc.args and exc.args[0] == 1062:
                    continue
                raise

        if not code:
            raise HTTPException(status_code=500, detail="Could not generate ride code")

        cur.execute(
            "INSERT INTO ride_members (ride_id, user_id) VALUES (%s, %s)",
            (ride_id, host_id),
        )
        cur.execute("SELECT started_at FROM rides WHERE id = %s", (ride_id,))
        row = cur.fetchone()

    return CreateRideResponse(
        code=code,
        destination=payload.destination,
        host_id=host_id,
        host_name=host_name,
        started_at=row["started_at"],
    )


@app.post("/rides/{code}/join", response_model=JoinRideResponse)
def join_ride(
    code: str, payload: JoinRideRequest, conn=Depends(get_db)
) -> JoinRideResponse:
    with conn.cursor() as cur:
        ride = _find_ride(cur, code)
        if ride["ended_at"] is not None:
            raise HTTPException(
                status_code=409, detail=f"Ride '{ride['code']}' has already ended"
            )

        user_id, name = _get_or_create_user(cur, payload.user_id, payload.name)
        cur.execute(
            "INSERT IGNORE INTO ride_members (ride_id, user_id) VALUES (%s, %s)",
            (ride["id"], user_id),
        )

    return JoinRideResponse(
        code=str(ride["code"]),
        destination=str(ride["destination"]),
        user_id=user_id,
        name=name,
        is_host=user_id == int(ride["host_id"]),
    )


@app.post("/rides/{code}/position", response_model=PositionUpdatedResponse)
def update_position(
    code: str, payload: UpdatePositionRequest, conn=Depends(get_db)
) -> PositionUpdatedResponse:
    with conn.cursor() as cur:
        ride = _find_ride(cur, code)
        if ride["ended_at"] is not None:
            raise HTTPException(
                status_code=409, detail=f"Ride '{ride['code']}' has already ended"
            )

        cur.execute(
            "SELECT 1 FROM ride_members WHERE ride_id = %s AND user_id = %s",
            (ride["id"], payload.user_id),
        )
        if cur.fetchone() is None:
            raise HTTPException(
                status_code=403,
                detail=f"User {payload.user_id} is not a member of ride '{ride['code']}'",
            )

        # Keep only one row per rider in this ride by updating on duplicate key.
        cur.execute(
            "INSERT INTO positions "
            "(ride_id, user_id, latitude, longitude, speed, battery, updated_at) "
            "VALUES (%s, %s, %s, %s, %s, %s, NOW()) "
            "ON DUPLICATE KEY UPDATE "
            "latitude = VALUES(latitude), "
            "longitude = VALUES(longitude), "
            "speed = VALUES(speed), "
            "battery = VALUES(battery), "
            "updated_at = NOW()",
            (
                ride["id"],
                payload.user_id,
                payload.latitude,
                payload.longitude,
                payload.speed_kmh,
                payload.battery_percent,
            ),
        )
        cur.execute(
            "SELECT updated_at FROM positions WHERE ride_id = %s AND user_id = %s",
            (ride["id"], payload.user_id),
        )
        row = cur.fetchone()

    return PositionUpdatedResponse(
        code=str(ride["code"]),
        user_id=payload.user_id,
        updated_at=row["updated_at"],
    )


@app.get("/rides/{code}/positions", response_model=RidePositionsResponse)
def get_positions(code: str, conn=Depends(get_db)) -> RidePositionsResponse:
    with conn.cursor() as cur:
        ride = _find_ride(cur, code)
        cur.execute(
            "SELECT u.id AS user_id, u.name, p.latitude, p.longitude, "
            "p.speed, p.battery, p.updated_at, "
            "GREATEST(0, TIMESTAMPDIFF(SECOND, p.updated_at, NOW())) AS age_seconds "
            "FROM positions p "
            "INNER JOIN users u ON u.id = p.user_id "
            "WHERE p.ride_id = %s "
            "ORDER BY u.id ASC",
            (ride["id"],),
        )
        rows = cur.fetchall()

    riders = [
        RiderPositionOut(
            rider=RiderSummary(id=int(row["user_id"]), name=str(row["name"])),
            latitude=float(row["latitude"]),
            longitude=float(row["longitude"]),
            speed_kmh=float(row["speed"]),
            battery_percent=(
                None if row["battery"] is None else int(row["battery"])
            ),
            age_seconds=int(row["age_seconds"]),
            is_stale=int(row["age_seconds"]) > STALE_AFTER_SECONDS,
            updated_at=row["updated_at"],
        )
        for row in rows
    ]
    return RidePositionsResponse(
        code=str(ride["code"]),
        destination=str(ride["destination"]),
        is_ended=ride["ended_at"] is not None,
        ended_at=ride["ended_at"],
        riders=riders,
    )


@app.post("/rides/{code}/end", response_model=EndRideResponse)
def end_ride(
    code: str, payload: EndRideRequest, conn=Depends(get_db)
) -> EndRideResponse:
    with conn.cursor() as cur:
        ride = _find_ride(cur, code)
        if int(ride["host_id"]) != payload.host_id:
            raise HTTPException(
                status_code=403, detail="Only the ride host can end this ride"
            )
        if ride["ended_at"] is not None:
            raise HTTPException(
                status_code=409, detail=f"Ride '{ride['code']}' has already ended"
            )

        cur.execute("UPDATE rides SET ended_at = NOW() WHERE id = %s", (ride["id"],))
        cur.execute("SELECT ended_at FROM rides WHERE id = %s", (ride["id"],))
        row = cur.fetchone()

    return EndRideResponse(code=str(ride["code"]), ended_at=row["ended_at"])
