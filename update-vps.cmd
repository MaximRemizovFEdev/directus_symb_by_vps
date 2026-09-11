@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0symbolika_directus_clean_install\setup\update-vps.ps1" %*
exit /b %errorlevel%
