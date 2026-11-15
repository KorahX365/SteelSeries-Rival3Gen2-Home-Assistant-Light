@echo off
title Desinstalador SteelSeries Rival 3 - Home Assistant
color 0C

echo ========================================================
echo   Desinstalador SteelSeries Rival 3 - Home Assistant
echo ========================================================
echo.

set STARTUP_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
set SHORTCUT=%STARTUP_DIR%\HomeAssistant_Rival3_Bridge.lnk

if exist "%SHORTCUT%" (
    del /f /q "%SHORTCUT%"
    echo [OK] Acceso directo eliminado de la carpeta de Inicio.
) else (
    echo El acceso directo no estaba instalado.
)

:: Detener proceso de powershell del puente si esta corriendo
powershell -Command "Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*ha_gamesense_bridge.ps1*' } | Stop-Process -Force" >nul 2>&1

echo.
echo Desinstalacion completada.
pause
