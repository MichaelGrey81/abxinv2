@echo off
rem Runs the query, updates the cache, Excel workbook and trend history,
rem then writes a shareable HTML report into the reports folder.
rem Point Windows Task Scheduler at this file to refresh every night.
cd /d "%~dp0"
if not exist reports mkdir reports
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set TODAY=%%d
python inventory_app.py --refresh --export "reports\inventory_health_%TODAY%.html" >> data\refresh.log 2>&1
