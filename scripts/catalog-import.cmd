@echo off
rem Double-click, or drag a folder of saved plans onto this file, to turn the plans into catalog entries.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0catalog-import.ps1" %*
echo.
pause
