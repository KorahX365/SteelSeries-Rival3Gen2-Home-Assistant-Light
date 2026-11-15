@echo off
title Instalador SteelSeries Rival 3 - Home Assistant
color 0A

echo ========================================================
echo   Instalador SteelSeries Rival 3 - Home Assistant
echo ========================================================
echo.

:: Verificar permisos de Administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Este instalador debe ejecutarse como Administrador.
    echo Por favor, haz clic derecho y selecciona "Ejecutar como administrador".
    echo.
    pause
    exit /b 1
)

set SCRIPT_DIR=%~dp0
set VBS_PATH=%SCRIPT_DIR%start_hidden.vbs
set STARTUP_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
set SHORTCUT=%STARTUP_DIR%\HomeAssistant_Rival3_Bridge.lnk

echo 1. Configurando permisos de red para el puerto 5055...
netsh http add urlacl url=http://*:5055/ user="%USERNAME%" >nul 2>&1

echo 2. Creando acceso directo en Inicio para ejecucion invisible...
powershell -Command "$wsh = New-Object -ComObject WScript.Shell; $sc = $wsh.CreateShortcut('%SHORTCUT%'); $sc.TargetPath = 'wscript.exe'; $sc.Arguments = '\"%VBS_PATH%\"'; $sc.Description = 'SteelSeries Rival 3 Home Assistant Bridge'; $sc.Save()"

echo.
echo ========================================================
echo [OK] Instalacion completada con exito!
echo El puente se ejecutara automaticamente cada vez que enciendas
echo el PC y detecte tu SteelSeries Rival 3 conectado.
echo ========================================================
echo.

echo Iniciando el puente ahora mismo...
start wscript.exe "%VBS_PATH%"

pause
