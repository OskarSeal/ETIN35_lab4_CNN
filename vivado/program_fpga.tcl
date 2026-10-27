# Program the Nexys4 over USB with build/fpga/cnn.bit, or build/fpga/<name>/cnn.bit (board
# connected and switched on).
#
# Usage (from any directory):
#   vivado -mode batch -nojournal -nolog -source vivado/program_fpga.tcl [-tclargs <name>]

if {[llength $argv] > 1} {
    error "usage: \[-tclargs <name>\]"
}
set root [file normalize [file join [file dirname [info script]] ..]]
set bit  [file join $root build fpga {*}$argv cnn.bit]
if {![file exists $bit]} {
    error "$bit not found: run vivado/build_fpga.tcl first"
}

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
if {$dev eq ""} {
    error "no xc7a100t found on the JTAG chain: is the board connected and on?"
}
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "Programmed $dev with $bit"
close_hw_manager
