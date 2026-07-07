@echo off
setlocal
cd /d "%~dp0"

if not exist "local_client" (
    echo No local_client folder exists yet.
    pause
    exit /b 1
)

for %%F in (Prelauncher Loader library) do (
    if exist "local_client\%%F.original.swf" (
        copy /y "local_client\%%F.original.swf" "local_client\%%F.swf" >nul
        echo Restored %%F.swf
    )
)

if exist "local_client\config.original.xml" (
    copy /y "local_client\config.original.xml" "local_client\config.xml" >nul
    echo Restored config.xml
)

echo.
echo Finished restoring available untouched local files.
pause
