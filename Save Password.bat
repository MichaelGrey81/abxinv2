@echo off
rem Stores the SQL login password encrypted for your Windows account, then tests the connection.
rem Run again any time the password changes.
cd /d "%~dp0"
python inventory_app.py --save-password
pause
