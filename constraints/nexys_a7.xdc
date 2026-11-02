## CLOCK (100 MHz onboard oscillator)
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { CLK }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK }];

## RESET BUTTON (CPU RESET, active low)
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports { RSTn }];

## SCENARIO SWITCHES: 00 normal, 01 sinus arrest, 10 AV block, 11 noisy normal
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports { SW[0] }];
set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports { SW[1] }];

## LD0 atrial sense, LD1 ventricular sense, LD2 atrial pace, LD3 ventricular pace
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { LED_A_SENSE }];
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { LED_V_SENSE }];
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports { LED_A_PACE }];
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports { LED_V_PACE }];

## Sample-domain logic (ecg_gen, pacemaker_core, LED stretchers) only updates when the
## 1 kHz sample enable is high, i.e. once per 100,000 clocks, so register-to-register
## paths inside it have many cycles to settle. If SAMPLE_RATE or BOARD_CLK_HZ change,
## keep this value no larger than BOARD_CLK_HZ / SAMPLE_RATE.
set slow_regs [get_cells -hierarchical -filter {IS_PRIMITIVE && IS_SEQUENTIAL && (NAME =~ gen/* || NAME =~ core/* || NAME =~ hold_*)}]
set_multicycle_path -setup 100000 -from $slow_regs -to $slow_regs
set_multicycle_path -hold  99999  -from $slow_regs -to $slow_regs
