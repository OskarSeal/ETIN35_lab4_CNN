## Nexys4 rev B pin assignments for fpga_top.
## Clock, SW0 and LED0..2 match the course file D:\Program\Vivado\Lund_lab_src\sv\keyboard_top.xdc.
## BTNC (E16), SW1..SW8 and LED3 are from the Digilent Nexys4 master XDC.

## 100 MHz clock
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -add -name clk -period 10.00 -waveform {0 5} [get_ports clk]

## SW0: reset (up = reset)
set_property -dict {PACKAGE_PIN U9 IOSTANDARD LVCMOS33} [get_ports sw_rst]

## SW1..SW8: image number (SW1 = LSB)
set_property -dict {PACKAGE_PIN U8 IOSTANDARD LVCMOS33} [get_ports {sw_img[0]}]
set_property -dict {PACKAGE_PIN R7 IOSTANDARD LVCMOS33} [get_ports {sw_img[1]}]
set_property -dict {PACKAGE_PIN R6 IOSTANDARD LVCMOS33} [get_ports {sw_img[2]}]
set_property -dict {PACKAGE_PIN R5 IOSTANDARD LVCMOS33} [get_ports {sw_img[3]}]
set_property -dict {PACKAGE_PIN V7 IOSTANDARD LVCMOS33} [get_ports {sw_img[4]}]
set_property -dict {PACKAGE_PIN V6 IOSTANDARD LVCMOS33} [get_ports {sw_img[5]}]
set_property -dict {PACKAGE_PIN V5 IOSTANDARD LVCMOS33} [get_ports {sw_img[6]}]
set_property -dict {PACKAGE_PIN U4 IOSTANDARD LVCMOS33} [get_ports {sw_img[7]}]

## BTNC: start
set_property -dict {PACKAGE_PIN E16 IOSTANDARD LVCMOS33} [get_ports btn_start]

## LED0: result valid, LED1: square, LED2: circle, LED3: result matches the label
set_property -dict {PACKAGE_PIN T8 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN V9 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN R8 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN T6 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

## The switches and button are asynchronous (synchronized in the design); the LEDs are static.
set_false_path -from [get_ports {sw_rst sw_img[*] btn_start}]
set_false_path -to [get_ports {led[*]}]

## Configuration bank voltage (Nexys4: 3.3 V)
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
