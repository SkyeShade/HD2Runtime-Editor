@echo off
setlocal
py -3 -B "%~dp0build.py" %*
set "STATUS=%ERRORLEVEL%"
rem Started by a double-click, the window closes on exit: keep it open so the result can be read.
echo %cmdcmdline% | "%SystemRoot%\System32\find.exe" /i "%~nx0" >nul && pause
exit /b %STATUS%
