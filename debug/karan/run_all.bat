@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ==============================================================================
REM  MICRON PIM (DDR3 Micron Verilog Model) - Windows Runner
REM  Flow: compile -> gen_testcase -> sweep sparsity -> parse RESULT line
REM ==============================================================================

set SIM_DIR=sim
set LOG_DIR=logs
set OUTPUT_VVP=tb.vvp

REM ---- Micron DDR3 compile config ----
set MICRON_DIR=rtl\micron_ddr3
set DENSITY_DEF=den1024Mb
set ORG_DEF=x8
set SPEED_DEF=sg25

REM 1) PREP DIRS
if not exist "%SIM_DIR%" mkdir "%SIM_DIR%"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

REM 2) COMPILE
echo 🔨 [1/3] Compiling Verilog (Micron DDR3 Model)...

iverilog -g2012 -o "%SIM_DIR%\%OUTPUT_VVP%" ^
  -I rtl ^
  -I "%MICRON_DIR%" ^
  -D%DENSITY_DEF% -D%ORG_DEF% -D%SPEED_DEF% ^
  rtl\ddr3_blackbox.v ^
  rtl\dram_controller_ddr3.v ^
  rtl\pim_system_top.v ^
  rtl\pim_mac_engine.v ^
  "%MICRON_DIR%\ddr3.v" ^
  testbench\tb_pim_system.v

if errorlevel 1 (
  echo ❌ Compile Failed!
  exit /b 1
)

REM 3) GENERATE DATA
echo 🎲 [2/3] Generating Testcases (firmware + meta)...
py gen_testcase.py
if errorlevel 1 (
  echo ❌ Data generation failed!
  exit /b 1
)

REM 4) RUN SIMULATION SWEEP
echo 🚀 [3/3] Running Sparsity Sweep...
echo.

echo  SPARSITY   ^| BASE E (uJ)      ^| PIM E (uJ)       ^| SAVING      ^| SPARSE PKTS  ^| TOTAL PKTS
echo ================================================================================================

for %%S in (0 25 50 75 85 90 95) do (

  REM Copy firmware+meta into sim/ so $readmemh() finds them (relative path)
  copy /y "sim_cases\firmware_sparse_%%S.hex" "%SIM_DIR%\firmware.hex" >nul
  copy /y "sim_cases\meta_sparse_%%S.hex"     "%SIM_DIR%\meta.hex"     >nul
  if errorlevel 1 (
  echo ❌ Failed to copy meta_sparse_%%S.hex
  )

  REM Run vvp from sim/ so reads resolve; log to logs/
  pushd "%SIM_DIR%"
  vvp "%OUTPUT_VVP%" "+model_data+%CD%" > "..\%LOG_DIR%\log_sparse_%%S.txt"
  popd

  REM Parse RESULT line: RESULT,Total,Sparse,BaseEnergy,PIMEnergy,Saving
  set LINE=
  for /f "usebackq delims=" %%L in (`findstr /c:"RESULT," "%LOG_DIR%\log_sparse_%%S.txt"`) do (
    set LINE=%%L
  )

  if defined LINE (
    for /f "tokens=2-6 delims=," %%a in ("!LINE!") do (
      set TOTAL=%%a
      set SPARSE=%%b
      set BASE_E=%%c
      set PIM_E=%%d
      set SAVE=%%e
    )
    echo  %%S%%      ^| !BASE_E!          ^| !PIM_E!           ^| !SAVE! ^| !SPARSE!        ^| !TOTAL!
  ) else (
    echo  %%S%%      ^| ERR              ^| ERR              ^| ERR         ^| ERR          ^| ERR
  )
)

echo ================================================================================================
echo Done.
endlocal