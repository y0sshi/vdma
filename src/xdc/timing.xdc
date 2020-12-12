# Timing Constraint
## create clock (pixel-clock from camera)
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets {je_IBUF[5]}]
create_clock -period 41.667 -name {pclk_f} -waveform {0.000 20.834} [get_nets {je_IBUF[5]}]

## set false_path (inter-clock path)
set_false_path -from [get_clocks -of_objects [get_pins slab_contest2020/clocking_wizard_inst0/inst/mmcm_adv_inst/CLKOUT1]] -to [get_clocks clk_fpga_0]; # clk_12m -> ps_clk
set_false_path -from [get_clocks pclk_f] -to [get_clocks -of_objects [get_pins slab_contest2020/clocking_wizard_inst0/inst/mmcm_adv_inst/CLKOUT1]];     # pclk_f  -> clk_12m
set_false_path -from [get_clocks clk_fpga_0] -to [get_clocks -of_objects [get_pins slab_contest2020/clocking_wizard_inst0/inst/mmcm_adv_inst/CLKOUT1]]; # ps_clk  -> clk_12m
set_false_path -from [get_clocks clk_fpga_0] -to [get_clocks -of_objects [get_pins slab_contest2020/clocking_wizard_inst0/inst/mmcm_adv_inst/CLKOUT2]]; # ps_clk  -> clk_74_25m
set_false_path -from [get_clocks clk_fpga_0] -to [get_clocks pclk_f];                                                                                   # ps_clk  -> pclk_f
