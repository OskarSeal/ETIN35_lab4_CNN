# Design sources shared by synth_check.tcl and build_fpga.tcl. Sets:
#   root     project root
#   sources  own RTL + the course top level (not top/conv_top.sv: that is the reference conv
#            wrapper, replaced by rtl/conv_top.sv)
#   xcis     the four RAM IPs (vivado/create_dist_mem.tcl)
#   mems     the board's image and label ROM files (rtl/image_loader.sv reads them by name)

set root    [file normalize [file join [file dirname [info script]] ..]]
set sources [concat [glob $root/rtl/*.sv] [list \
    $root/IPs/Convolution/RAM_IP_src/RAM_IP_TOP.sv \
    $root/top/top.sv $root/top/network_top.sv $root/top/top_initialize.sv]]
set xcis    [glob $root/vivado/ip/dist_mem_gen_*/dist_mem_gen_*.xci]
set mems    [list $root/vivado/board/board_images.mem $root/vivado/board/board_labels.mem]

# Read the RAM IPs and synthesize them with the design instead of as separate checkpoints.
proc read_design {} {
    global sources xcis mems
    read_ip $xcis
    set_property generate_synth_checkpoint false [get_files *.xci]
    read_verilog -sv $sources
    read_mem $mems
}
