# Set up an existing Vivado project for the GUI: design sources and RAM IPs from this
# repository (referenced, not copied), vivado/nexys4.xdc, fpga_top as design top, and
# sim/tb_cnn.sv as simulation top, reading its vectors from sim/vectors and writing its
# dumps to build/sim/project/<project name>/.
#
# Usage, in the Tcl console of the open project:
#   source <repository>/vivado/setup_project.tcl
# then Run Simulation > Run Behavioral Simulation. sim/vectors holds images 1-10; for other
# images: uv run python tools/make_vectors.py tb <images> sim/vectors
# vivado/create_projects.tcl makes ready projects for the grade 4 / grade 5 configurations.
#
# Layers come from rtl/ unless left out of $own, in which case the reference netlist is used,
# e.g.  set own {conv}; source .../setup_project.tcl
# Sourcing again swaps the HDL files and keeps the RAM IPs.

source [file join [file dirname [info script]] sources.tcl]
if {![info exists own]} { set own {conv pool fc} }

# Per layer: own RTL / reference (gate-level VHDL netlists, conv with its SV wrapper)
set layers {
    conv {
        own {rtl/conv_controller.sv rtl/conv_pe.sv rtl/conv_pe_array.sv
             rtl/conv_accumulator.sv rtl/conv_relu.sv rtl/conv_top.sv}
        ref {IPs/Convolution/Controller_Imp/behav_vhdl/Controller_impl.vhd
             IPs/Convolution/PE_Top/behav_vhdl/PE.VHD
             IPs/Convolution/Accumulator/behav_vhdl/accumulator.vhd
             IPs/Convolution/RELU_Conv_Activation/behav_vhdl/RELU.vhd
             top/conv_top.sv}
    }
    pool { own {rtl/pooling_top.sv} ref {IPs/pooling/behav_vhdl/Pooling.vhd} }
    fc   { own {rtl/fc_top.sv}      ref {IPs/FC/behav_vhdl/FC.vhd} }
}
set common {
    IPs/Convolution/RAM_IP_src/RAM_IP_TOP.sv top/network_top.sv top/top_initialize.sv
    top/top.sv rtl/reset_sync.sv rtl/debounce.sv rtl/fpga_top.sv
}
# Plain foreach loops, no lmap: Vivado versions with Tcl 8.5 must run this too.
set files {}
set known [list $root/sim/tb_cnn.sv $root/vivado/nexys4.xdc]
foreach f $common { lappend files $root/$f; lappend known $root/$f }
dict for {layer impl} $layers {
    foreach f [dict get $impl [expr {$layer in $own ? "own" : "ref"}]] { lappend files $root/$f }
    foreach f [concat [dict get $impl own] [dict get $impl ref]] { lappend known $root/$f }
}

# Sourcing again swaps the HDL files, in one remove_files call (removing files one by one,
# IPs included, can crash Vivado). The RAM IPs are the same in every configuration, so they
# are only added when missing.
set present [get_files -quiet $known]
if {[llength $present]} { remove_files $present }
add_files -norecurse -fileset sources_1 $files
set new_xcis {}
foreach x $xcis {
    if {![llength [get_files -quiet $x]]} { lappend new_xcis $x }
}
if {[llength $new_xcis]} { add_files -norecurse -fileset sources_1 $new_xcis }
foreach f $files {
    if {[string match -nocase *.vhd $f]} { set_property file_type VHDL [get_files $f] }
}
add_files -norecurse -fileset constrs_1 $root/vivado/nexys4.xdc
add_files -norecurse -fileset sim_1 $root/sim/tb_cnn.sv
set_property top fpga_top [get_filesets sources_1]
set_property top tb_cnn   [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# Vivado empties its own run directory on every launch, so the vectors and dumps live in
# build/ and the testbench gets absolute paths. The vectors are shared by all projects, the
# dumps are per project. Log every signal so that any of them can be added to the waveform
# after the run.
set vec_dir $root/sim/vectors
set out_dir $root/build/sim/project/[current_project]
file mkdir $out_dir
set_property -dict [list \
    xsim.simulate.runtime          all \
    xsim.simulate.log_all_signals  true \
    xsim.simulate.xsim.more_options "-testplusarg VEC_DIR=$vec_dir -testplusarg OUT_DIR=$out_dir" \
] [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Own layers: [expr {[llength $own] ? $own : "none"}]; vectors: $vec_dir; dumps: $out_dir"
if {![file exists $vec_dir/expected.txt]} {
    puts "WARNING: no vectors yet; run: uv run python tools/make_vectors.py tb 1-10 sim/vectors"
}
