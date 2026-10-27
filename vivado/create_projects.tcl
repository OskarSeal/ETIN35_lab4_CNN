# Create one Vivado project per lab configuration, each filled by setup_project.tcl:
#   reference  all layers from the course netlists        (grade 4, part 1)
#   grade4     own conv + ReLU + max-pool, reference FC   (grade 4, part 2)
#   grade5     all layers own                             (grade 5)
#
# Usage (from any directory):
#   vivado -mode batch -nojournal -nolog -source vivado/create_projects.tcl -tclargs <dir> [config ...]
# e.g. -tclargs D:/Program/Vivado grade4 grade5 gives D:/Program/Vivado/CNN_grade4/CNN_grade4.xpr
# and D:/Program/Vivado/CNN_grade5/CNN_grade5.xpr. Without configs, all three are created.
# A project directory that already exists is an error.

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

foreach name $names {
    create_project CNN_$name [file join $dir CNN_$name] -part xc7a100tcsg324-1
    set own [dict get $configs $name]
    source [file join $here setup_project.tcl]
    close_project
}
puts "Created: [join [lmap n $names { file join $dir CNN_$n CNN_$n.xpr }] {, }]"
