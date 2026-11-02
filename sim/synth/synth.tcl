# Out-of-context synthesis check for the Nexys A7-100T (xc7a100tcsg324-1).
# Run:  vivado -mode batch -source sim/synth/synth.tcl   (from the repository root)
read_verilog rtl/pacemaker.v
read_xdc constraints/nexys_a7.xdc
synth_design -top pacemaker_top -part xc7a100tcsg324-1
report_utilization -file sim/synth/utilization.rpt
report_timing_summary -file sim/synth/timing.rpt
