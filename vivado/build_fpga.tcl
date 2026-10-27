# Build the bitstream for the Nexys4 rev B: synthesis and implementation of fpga_top with
# vivado/nexys4.xdc, reports (utilization, timing, power, DRC) and build/fpga/cnn.bit.
#
# Usage (from any directory):
#   vivado -mode batch -nojournal -nolog -source vivado/build_fpga.tcl [-tclargs <name>]
# The board loads the image selected by the switches (images 1-256, vivado/board/) into the RAM
# before each run, so the RAM IPs' init file does not matter. With <name> everything goes to
# build/fpga/<name>/ instead of build/fpga/.

if {[llength $argv] > 1} {
    error "usage: \[-tclargs <name>\]"
}
source [file join [file dirname [info script]] sources.tcl]
set out [file join $root build fpga {*}$argv]
file mkdir $out

create_project -in_memory -part xc7a100tcsg324-1
read_design
read_xdc $root/vivado/nexys4.xdc

synth_design -top fpga_top
opt_design
place_design
phys_opt_design
route_design

set util  [report_utilization -return_string]
set power [report_power -return_string]
foreach {name text} [list utilization $util power $power] {
    set fh [open $out/$name.rpt w]; puts $fh $text; close $fh
}
report_timing_summary -file $out/timing.rpt
report_drc            -file $out/drc.rpt
write_bitstream -force $out/cnn.bit

set bram ?
regexp {\|\s*Slice LUTs\*?\s*\|\s*(\d+)}          $util  -> luts
regexp {\|\s*LUT as Memory\s*\|\s*(\d+)}           $util  -> lutmem
regexp {\|\s*Slice Registers\s*\|\s*(\d+)}         $util  -> ffs
regexp {\|\s*Bonded IOB\s*\|\s*(\d+)}              $util  -> iobs
regexp {\|\s*Block RAM Tile\s*\|\s*([0-9.]+)}       $util  -> bram
regexp {Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)} $power -> p_total
regexp {Dynamic \(W\)\s*\|\s*([0-9.]+)}            $power -> p_dyn
regexp {Device Static \(W\)\s*\|\s*([0-9.]+)}      $power -> p_static
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]

puts "\n==== build_fpga summary ===="
puts [format "LUT %d (as memory %d)  FF %d  BRAM tiles %s  IO %d" $luts $lutmem $ffs $bram $iobs]
puts [format "WNS %.3f ns  WHS %.3f ns  @ 100 MHz" $wns $whs]
puts [format "Power %.3f W (dynamic %.3f W, static %.3f W)" $p_total $p_dyn $p_static]
puts "Bitstream: $out/cnn.bit"
