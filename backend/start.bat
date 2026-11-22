@echo off
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo Creating Python virtual environment in backend\.venv...
    python -m venv .venv || exit /b 1
    ".venv\Scripts\python.exe" -m pip install -r requirements-dev.txt || exit /b 1
)

if not exist ".env" (
    copy ".env.example" ".env" >nul
    echo Created backend\.env from .env.example.
    echo Set DB_PORT=3306 (for local MariaDB^) and DB_PASSWORD, then run start.bat again.
    exit /b 1
)

".venv\Scripts\python.exe" init_db.py || exit /b 1

netstat -ano | findstr ":8000 " | findstr "LISTENING" >nul 2>&1
if %errorlevel%==0 (
    echo RideSync API is already running at http://127.0.0.1:8000 (docs: http://127.0.0.1:8000/docs^)
    exit /b 0
)

echo Starting RideSync API at http://127.0.0.1:8000 (docs: http://127.0.0.1:8000/docs^)
".venv\Scripts\python.exe" -m uvicorn app.main:app --reload --port 8000
