# HDL-Source
add_files "
../src/hdl/zybo_z7_top.sv
../src/hdl/vdma_top.sv
../src/hdl/vid/vid_sync2cnt.sv
../src/hdl/vid/vid_cnt2sync.sv
../src/hdl/image_processor/image_processor.sv
../src/hdl/image_processor/lsd_visualizer.sv
../src/hdl/image_processor/lsd/contrast_stretch.sv
../src/hdl/image_processor/lsd/simple_lsd.sv
../src/hdl/image_processor/lsd/line_draw.sv
../src/hdl/image_processor/lsd/lsd_output_buffer_wp.sv
../src/hdl/image_processor/lsd/lsd_output_buffer.sv
../src/hdl/image_processor/lsd/slsd_mem_overlay.sv
../src/hdl/image_processor/util/coord_adjuster.sv
../src/hdl/image_processor/util/rgb2ycbcr.sv
../src/hdl/image_processor/util/arctan_calc.sv
../src/hdl/image_processor/util/batch_norm.sv
../src/hdl/image_processor/util/conv_layer_fixed.sv
../src/hdl/image_processor/util/delay.sv
../src/hdl/image_processor/util/divider_iter_s.sv
../src/hdl/image_processor/util/fifo_dc.sv
../src/hdl/image_processor/util/fifo_sc.sv
../src/hdl/image_processor/util/ram_dc.sv
../src/hdl/image_processor/util/ram_sc.sv
../src/hdl/image_processor/util/sin_calc.sv
../src/hdl/image_processor/util/stream_patch.sv
../src/hdl/image_processor/util/tree_adder.sv
../src/hdl/zynq_interface/zynq_interface.sv
../src/hdl/DVIClocking/DVIClocking.vhd
../src/hdl/DVIClocking/SyncAsync.vhd
../src/hdl/DVIClocking/SyncAsyncReset.vhd
"

# XDC
add_files -fileset constrs_1 -norecurse "
../src/xdc/zybo-z7.xdc
../src/xdc/timing.xdc 
"
