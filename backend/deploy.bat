@echo off
REM Deploy committed backend/ files to /srv/ridesync on your SSH host (default: debian).
setlocal
set HOST=%~1
if "%HOST%"=="" set HOST=debian

cd /d "%~dp0\.."
echo Uploading backend files to %HOST%:/srv/ridesync ...
git archive HEAD backend | ssh -o BatchMode=yes %HOST% "sudo tar -xf - -C /srv/ridesync" || exit /b 1

echo Installing requirements, updating schema, and restarting ridesync.service ...
ssh -o BatchMode=yes %HOST% "cd /srv/ridesync/backend && sudo .venv/bin/pip install -q -r requirements.txt && sudo .venv/bin/python init_db.py && sudo systemctl restart ridesync && sleep 1 && curl -fsS http://127.0.0.1:8000/health && echo" || exit /b 1

echo Deploy complete!
