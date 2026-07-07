@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

title ProTanki Local Client

echo ============================================================
echo                 ProTanki Local Client
echo ============================================================
echo.

if not exist "ProTanki.exe" (
    echo ERROR: ProTanki.exe is missing from:
    echo %CD%
    echo.
    echo Run INSTALL_AND_START.bat from the downloaded package again.
    pause
    exit /b 1
)

if not exist "StandaloneLoader.original.swf" (
    if exist "StandaloneLoader.swf" (
        copy /y "StandaloneLoader.swf" "StandaloneLoader.original.swf" >nul
    )
)

if not exist "StandaloneLoader.local.swf" (
    echo ERROR: StandaloneLoader.local.swf is missing.
    echo Run INSTALL_AND_START.bat again.
    pause
    exit /b 1
)

copy /y "StandaloneLoader.local.swf" "StandaloneLoader.swf" >nul
if errorlevel 1 (
    echo ERROR: Could not activate the local loader.
    pause
    exit /b 1
)

if not exist "local_client" mkdir "local_client"

call :PortCheck
if "!PORT_OPEN!"=="0" (
    echo Starting the local file server...
    start "ProTanki Local File Server" /min powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0LocalProxy.ps1"
)

echo Waiting for the local file server...
for /l %%I in (1,1,20) do (
    timeout /t 1 /nobreak >nul
    call :PortCheck
    if "!PORT_OPEN!"=="1" goto ServerReady
)

echo.
echo ERROR: The local file server did not start on port 8765.
echo Check local_proxy.log in this folder.
pause
exit /b 1

:ServerReady
echo Local file server is ready:
echo http://127.0.0.1:8765
echo.
echo Starting ProTanki...
echo The first launch may take longer while SWF files are downloaded.
start "" "%~dp0ProTanki.exe"
exit /b 0

:PortCheck
set PORT_OPEN=0
powershell -NoProfile -Command "$c=New-Object Net.Sockets.TcpClient;try{$c.Connect('127.0.0.1',8765);exit 0}catch{exit 1}finally{$c.Dispose()}" >nul 2>nul
if not errorlevel 1 set PORT_OPEN=1
exit /b 0
