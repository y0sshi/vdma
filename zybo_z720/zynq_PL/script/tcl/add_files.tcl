# HDL-Source
add_files "
../src/hdl/zybo_z7_top.sv
../src/hdl/vdma_top.sv
../src/hdl/vid/vid_sync2cnt.sv
../src/hdl/vid/vid_cnt2sync.sv
../src/hdl/image_processor/image_processor.sv
../src/hdl/image_processor/util/coord_adjuster.sv
../src/hdl/image_processor/util/rgb2ycbcr.sv
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
