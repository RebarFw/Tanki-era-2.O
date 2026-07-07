@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

if exist "local_proxy.pid" (
    set /p PROXY_PID=<"local_proxy.pid"
    if defined PROXY_PID (
        taskkill /pid !PROXY_PID! /t /f >nul 2>nul
    )
    del /q "local_proxy.pid" >nul 2>nul
)

echo Local ProTanki file server stopped.
timeout /t 2 /nobreak >nul
