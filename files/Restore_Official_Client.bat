@echo off
setlocal
cd /d "%~dp0"

call "%~dp0Stop_Local_Proxy.bat"

if exist "StandaloneLoader.original.swf" (
    copy /y "StandaloneLoader.original.swf" "StandaloneLoader.swf" >nul
    echo The untouched official StandaloneLoader.swf was restored.
) else (
    echo ERROR: StandaloneLoader.original.swf was not found.
)

pause
