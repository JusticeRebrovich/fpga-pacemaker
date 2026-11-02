@echo off
REM Compile, elaborate and simulate the pacemaker testbench with Vivado xsim.
setlocal
cd /d "%~dp0"
set VIV=C:\Xilinx\Vivado\2020.2\bin
call %VIV%\xvlog.bat ..\rtl\pacemaker.v ..\tb\tb_pacemaker.v || goto :fail
call %VIV%\xelab.bat -timescale 1ns/1ps testbench -s tb_sim || goto :fail
call %VIV%\xsim.bat tb_sim -runall -log sim.log
exit /b %errorlevel%
:fail
echo *** BUILD FAILED ***
exit /b 1
