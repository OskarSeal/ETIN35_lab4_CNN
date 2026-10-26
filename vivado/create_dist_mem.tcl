# Generate the four distributed-memory image banks instantiated by RAM_IP_TOP
# (dist_mem_gen_0..3: single-port RAM, 16 x 64, asynchronous read), into vivado/ip/.
#
# Usage (from any directory):
#   vivado -mode batch -nojournal -nolog -source vivado/create_dist_mem.tcl -tclargs <coe_dir>
# <coe_dir> must contain bank0.coe .. bank3.coe, e.g. from
#   uv run python tools/make_vectors.py coe 1 build/coe/img_00001

if {[llength $argv] != 1} {
    error "usage: -tclargs <coe_dir>"
}
set coe_src [file normalize [lindex $argv 0]]
set ip_dir  [file normalize [file join [file dirname [info script]] ip]]
set coe_dir [file join $ip_dir coe]
file mkdir $coe_dir

create_project -in_memory -part xc7a100tcsg324-1
for {set k 0} {$k < 4} {incr k} {
    set name dist_mem_gen_$k
    # Keep a copy of the init file next to the IPs so they don't depend on build/.
    file copy -force [file join $coe_src bank$k.coe] $coe_dir
    file delete -force [file join $ip_dir $name]

    create_ip -name dist_mem_gen -vendor xilinx.com -library ip -module_name $name -dir $ip_dir
    set_property -dict [list \
        CONFIG.memory_type      single_port_ram \
        CONFIG.depth            16 \
        CONFIG.data_width       64 \
        CONFIG.output_options   non_registered \
        CONFIG.coefficient_file [file join $coe_dir bank$k.coe] \
    ] [get_ips $name]
    generate_target all [get_ips $name]
}
puts "Generated dist_mem_gen_0..3 in $ip_dir"
