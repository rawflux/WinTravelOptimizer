@echo off
rem Starts WinTravelOptimizer (menu when run without parameters). It asks for administrator rights itself.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0WinTravelOptimizer.ps1" %*
