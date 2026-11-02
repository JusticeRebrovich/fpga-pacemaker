# Full implementation check (synthesis, place, route) for the Nexys A7-100T.
# Run:  vivado -mode batch -source sim/synth/impl.tcl   (from the repository root)
read_verilog rtl/pacemaker.v
read_xdc constraints/nexys_a7.xdc
synth_design -top pacemaker_top -part xc7a100tcsg324-1
opt_design
place_design
route_design
report_utilization -file sim/synth/utilization_impl.rpt
report_timing_summary -file sim/synth/timing_impl.rpt
# write_bitstream -force pacemaker.bit   ;# uncomment to program the board
