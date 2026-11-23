"""Request and response JSON shapes for the RideSync API."""

from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field


class _TrimmedModel(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)


class HealthResponse(_TrimmedModel):
    status: str
    database: str


class CreateRideRequest(_TrimmedModel):
    destination: str = Field(min_length=1, max_length=255)
    dest_lat: float | None = Field(default=None, ge=-90.0, le=90.0)
    dest_lng: float | None = Field(default=None, ge=-180.0, le=180.0)
    host_name: str = Field(default="Rider", min_length=1, max_length=100)
    host_id: int | None = Field(default=None, gt=0)


class CreateRideResponse(_TrimmedModel):
    code: str
    destination: str
    dest_lat: float | None = None
    dest_lng: float | None = None
    host_id: int
    host_name: str
    started_at: datetime


class JoinRideRequest(_TrimmedModel):
    name: str = Field(default="Rider", min_length=1, max_length=100)
    user_id: int | None = Field(default=None, gt=0)


class JoinRideResponse(_TrimmedModel):
    code: str
    destination: str
    dest_lat: float | None = None
    dest_lng: float | None = None
    user_id: int
    name: str
    is_host: bool


class UpdatePositionRequest(_TrimmedModel):
    user_id: int = Field(gt=0)
    latitude: float = Field(ge=-90.0, le=90.0)
    longitude: float = Field(ge=-180.0, le=180.0)
    speed_kmh: float = Field(default=0.0, ge=0.0)
    heading_degrees: float = Field(default=0.0, ge=0.0, le=360.0)
    battery_percent: int | None = Field(default=None, ge=0, le=100)


class PositionUpdatedResponse(_TrimmedModel):
    code: str
    user_id: int
    updated_at: datetime


class RiderSummary(_TrimmedModel):
    id: int
    name: str


class RiderPositionOut(_TrimmedModel):
    rider: RiderSummary
    latitude: float
    longitude: float
    speed_kmh: float
    heading_degrees: float = 0.0
    battery_percent: int | None
    age_seconds: int
    is_stale: bool
    updated_at: datetime


class SendAlertRequest(_TrimmedModel):
    user_id: int = Field(gt=0)
    alert_type: str = Field(pattern="^(fuel|wait|help)$")
    message: str = Field(default="", max_length=120)


class RideAlertOut(_TrimmedModel):
    id: int
    user_id: int
    sender_name: str
    alert_type: str
    message: str
    age_seconds: int
    created_at: datetime


class RidePositionsResponse(_TrimmedModel):
    code: str
    destination: str
    dest_lat: float | None = None
    dest_lng: float | None = None
    is_ended: bool
    ended_at: datetime | None
    riders: list[RiderPositionOut]
    latest_alert: RideAlertOut | None = None


class EndRideRequest(_TrimmedModel):
    host_id: int = Field(gt=0)


class EndRideResponse(_TrimmedModel):
    code: str
    ended_at: datetime
