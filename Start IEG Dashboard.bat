@echo off
rem International Enviroguard Inventory Dashboard (company 2) on http://127.0.0.1:8051
cd /d "%~dp0"
python inventory_app.py --config config_ieg.ini
pause
