# Out-of-context synthesis + place & route of own RTL blocks: checks that they synthesize,
# shows their size and whether they meet 100 MHz. Reports go to build/synth/<top>/.
#
# Usage (from any directory):
#   vivado -mode batch -nojournal -nolog -source vivado/synth_check.tcl -tclargs conv_top Pooling_TOP

set root    [file normalize [file join [file dirname [info script]] ..]]
set sources [concat [glob $root/rtl/*.sv] [list $root/IPs/Convolution/RAM_IP_src/RAM_IP_TOP.sv]]
set xcis    [glob $root/vivado/ip/dist_mem_gen_*/dist_mem_gen_*.xci]
set summary {}

foreach top $argv {
    set out [file join $root build synth $top]
    file mkdir $out

    create_project -in_memory -part xc7a100tcsg324-1
    read_ip $xcis
    # Synthesize the RAM IPs together with the design instead of as separate checkpoints.
    set_property generate_synth_checkpoint false [get_files *.xci]
    read_verilog -sv $sources

    synth_design -top $top -mode out_of_context
    create_clock -name clk -period 10.000 [get_ports clk]
    opt_design
    place_design
    route_design

    set util [report_utilization -return_string]
    set fh [open $out/utilization.rpt w]; puts $fh $util; close $fh
    report_timing_summary -file $out/timing.rpt
    regexp {\|\s*Slice LUTs\*?\s*\|\s*(\d+)}  $util -> luts
    regexp {\|\s*LUT as Memory\s*\|\s*(\d+)}   $util -> lutmem
    regexp {\|\s*Slice Registers\s*\|\s*(\d+)} $util -> ffs
    set wns [get_property SLACK [get_timing_paths -delay_type max]]
    lappend summary [format "%-14s LUT %5d (as memory %3d)  FF %5d  WNS %6.3f ns" \
                         $top $luts $lutmem $ffs $wns]
    close_project
}

puts "\n==== synth_check summary (100 MHz) ===="
foreach line $summary { puts $line }
