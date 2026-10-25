@echo off
rem Karma Loop launcher - double-click to play fullscreen (F11 toggles window mode).
rem Finds Godot 4.7.1 in this order: GODOT environment variable, godot in PATH,
rem a Godot exe placed next to this file.
title Karma Loop
setlocal
set "GAME=%~dp0."
set "EXE="
if defined GODOT if exist "%GODOT%" set "EXE=%GODOT%"
if not defined EXE for %%G in (godot.exe godot4.exe Godot_v4.7.1-stable_win64.exe) do if not defined EXE for %%P in (%%G) do if not "%%~$PATH:P"=="" set "EXE=%%~$PATH:P"
if not defined EXE for %%F in ("%~dp0Godot*.exe") do if not defined EXE set "EXE=%%~fF"
if not defined EXE (
  echo Godot 4.7.1 was not found.
  echo  1. Download Godot 4.7.1 stable from https://godotengine.org/download
  echo  2. Then do ONE of these:
  echo     - put the Godot .exe in this folder, or
  echo     - add the Godot folder to PATH, or
  echo     - set GODOT=C:\path\to\Godot_v4.7.1-stable_win64.exe
  echo  Or open project.godot in Godot and press F5.
  pause
  exit /b 1
)
start "Karma Loop" "%EXE%" --path "%GAME%" --fullscreen