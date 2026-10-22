@echo off
rem Cross-platform launcher for e2e.py. Windows: e2e.cmd <command>
setlocal

set "ROOT=%~dp0"

where py >nul 2>nul
if %ERRORLEVEL%==0 (
    py -3 "%ROOT%e2e.py" %*
    exit /b %ERRORLEVEL%
)

where python >nul 2>nul
if %ERRORLEVEL%==0 (
    python "%ROOT%e2e.py" %*
    exit /b %ERRORLEVEL%
)

echo error: Python 3.9+ is required. Install it from https://www.python.org/downloads/ 1>&2
exit /b 1
