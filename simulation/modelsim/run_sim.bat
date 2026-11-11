PATH "C:\intelFPGA_lite\18.1\modelsim_ase\win32aloem";%PATH%
REM Edit the path before the semicolon!


REM Don't touch this
vlib work
vlog tb.v
vlog main.vo
vsim -pli fakefpga.vpi +nowarn3116 -c -t 1ps -L cyclonev_ver -L altera_ver -L altera_mf_ver -L 220model_ver -L sgate_ver -L altera_lnsim_ver tb -voptargs="+acc" -do "run -all"

pause