@echo off
REM run_xsim.bat -- compile, elaborate and simulate a testbench with Vivado xsim.
REM
REM   sim\run_xsim.bat                    self-checking core testbench (all tests)
REM   sim\run_xsim.bat tb_pacemaker directed
REM   sim\run_xsim.bat tb_top_demo        board-level demo scenarios
REM   sim\run_xsim.bat gui                open the waveform viewer
REM
REM Set DEFS to inject a fault, e.g.  set DEFS=-d FI_AV
setlocal
cd /d "%~dp0"
set VIV=C:\Xilinx\Vivado\2020.2\bin
set TB=%1
set TST=%2
if "%TB%"=="" set TB=tb_pacemaker
if /i "%TB%"=="gui" (set GUI=1 & set TB=tb_pacemaker)
if "%TST%"=="" set TST=all

call "%VIV%\xvlog.bat" %DEFS% ..\rtl\pacemaker.v || goto :fail
call "%VIV%\xvlog.bat" -sv ..\tb\%TB%.sv || goto :fail
call "%VIV%\xelab.bat" -debug typical -timescale 1ns/1ps %TB% -s %TB%_sim || goto :fail
if defined GUI (
  call "%VIV%\xsim.bat" %TB%_sim -gui
) else (
  call "%VIV%\xsim.bat" %TB%_sim -runall -log sim.log -testplusarg "TEST=%TST%"
)
exit /b %errorlevel%

:fail
echo *** BUILD FAILED ***
exit /b 1
