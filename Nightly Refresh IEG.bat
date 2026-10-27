@echo off
rem Refreshes the International Enviroguard dashboard (company 2) and saves a dated HTML report.
cd /d "%~dp0"
if not exist reports mkdir reports
if not exist data_ieg mkdir data_ieg
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set TODAY=%%d
python inventory_app.py --config config_ieg.ini --refresh --export "reports\ieg_inventory_%TODAY%.html" >> data_ieg\refresh.log 2>&1
