# Create one Vivado project per lab configuration, each filled by setup_project.tcl:
#   reference  all layers from the course netlists        (grade 4, part 1)
#   grade4     own conv + ReLU + max-pool, reference FC   (grade 4, part 2)
#   grade5     all layers own                             (grade 5)
#
# Usage (from any directory):
#   vivado -mode batch -nojournal -nolog -source vivado/create_projects.tcl -tclargs <dir> [config ...]
# e.g. -tclargs D:/Program/Vivado grade4 grade5 gives D:/Program/Vivado/CNN_grade4/CNN_grade4.xpr
# and D:/Program/Vivado/CNN_grade5/CNN_grade5.xpr. Without configs, all three are created.
# <dir> is created if needed; a project directory that already exists is an error.
#
# The RAM IPs (vivado/ip/) are not checked in; after a fresh clone they are generated first,
# with image 1 (vivado/coe/img_00001).

set configs [dict create reference {} grade4 {conv pool} grade5 {conv pool fc}]
set here    [file dirname [file normalize [info script]]]

if {[llength $argv] < 1} {
    error "usage: -tclargs <dir> ?config ...?  (configs: [dict keys $configs])"
}
set dir   [file normalize [lindex $argv 0]]
set names [lrange $argv 1 end]
if {![llength $names]} { set names [dict keys $configs] }

foreach name $names {
    if {![dict exists $configs $name]} {
        error "unknown configuration '$name' (known: [dict keys $configs])"
    }
    if {[file exists [file join $dir CNN_$name]]} {
        error "[file join $dir CNN_$name] exists already"
    }
}

file mkdir $dir
set ip_root [file join [file dirname $here] vivado ip]
if {[llength [glob -nocomplain $ip_root/dist_mem_gen_*/dist_mem_gen_*.xci]] < 4} {
    set argv [list [file join [file dirname $here] vivado coe img_00001]]
    source [file join $here create_dist_mem.tcl]
    close_project
}

foreach name $names {
    create_project CNN_$name [file join $dir CNN_$name] -part xc7a100tcsg324-1
    set own [dict get $configs $name]
    source [file join $here setup_project.tcl]
    close_project
}
set created {}
foreach n $names { lappend created [file join $dir CNN_$n CNN_$n.xpr] }
puts "Created: [join $created {, }]"
