connect_debug_port u_ila_0/probe0 [get_nets [list {vdma_test/vid_out_hcnt[0]} {vdma_test/vid_out_hcnt[1]} {vdma_test/vid_out_hcnt[2]} {vdma_test/vid_out_hcnt[3]} {vdma_test/vid_out_hcnt[4]} {vdma_test/vid_out_hcnt[5]} {vdma_test/vid_out_hcnt[6]} {vdma_test/vid_out_hcnt[7]} {vdma_test/vid_out_hcnt[8]} {vdma_test/vid_out_hcnt[9]}]]
connect_debug_port u_ila_0/probe3 [get_nets [list {vdma_test/vid_out_vcnt[0]} {vdma_test/vid_out_vcnt[1]} {vdma_test/vid_out_vcnt[2]} {vdma_test/vid_out_vcnt[3]} {vdma_test/vid_out_vcnt[4]} {vdma_test/vid_out_vcnt[5]} {vdma_test/vid_out_vcnt[6]} {vdma_test/vid_out_vcnt[7]} {vdma_test/vid_out_vcnt[8]} {vdma_test/vid_out_vcnt[9]}]]
connect_debug_port u_ila_0/probe4 [get_nets [list vdma_test/vid_in_hsync]]
connect_debug_port u_ila_0/probe5 [get_nets [list vdma_test/vid_in_VDE]]
connect_debug_port u_ila_0/probe6 [get_nets [list vdma_test/vid_in_vsync]]
connect_debug_port dbg_hub/clk [get_nets u_ila_0_PixelClk]

