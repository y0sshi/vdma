# env
set WORKSPACE_DIR ".."
set PROJECT_NAME  "vdma_test"
set TOP_MODULE    "zybo_z7_top"
set JOBS          16
set DEVICE        "xc7z020clg400-1"

# create project
if { [ file exists ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.xpr ] == 0 } then {
	file mkdir ${WORKSPACE_DIR}/vivado_proj
		create_project ${PROJECT_NAME} ${WORKSPACE_DIR}/vivado_proj -part ${DEVICE}
}

# import sources (hdl, block design, xdc)
source tcl/add_files.tcl
add_files -fileset constrs_1 -norecurse "${WORKSPACE_DIR}/src/xdc/target.xdc"
set_property target_constrs_file ${WORKSPACE_DIR}/src/xdc/target.xdc [current_fileset -constrset]

# set ip-repository
set_property ip_repo_paths ${WORKSPACE_DIR}/repo/ip_repo [current_project]
update_ip_catalog

# add RGB to DVI IP
create_ip -name rgb2dvi -vendor digilentinc.com -library ip -version 1.4 -module_name rgb2dvi_0
set_property -dict [list CONFIG.kRstActiveHigh {false} CONFIG.kD0Swap {false} CONFIG.kGenerateSerialClk {false}] [get_ips rgb2dvi_0]
generate_target {instantiation_template} [get_files ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.srcs/sources_1/ip/rgb2dvi_0/rgb2dvi_0.xci]

# update compile_order
set_property top ${TOP_MODULE} [current_fileset]
set_property source_mgmt_mode All [current_project]
update_compile_order -fileset sources_1



###################################### Block Design ######################################

# create block design
create_bd_design "block_design"
update_compile_order -fileset sources_1

# add Clocking_Wizard
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
set_property -dict [list CONFIG.PRIM_IN_FREQ.VALUE_SRC USER] [get_bd_cells clk_wiz_0]
set_property -dict [list                                 \
CONFIG.PRIM_IN_FREQ {50.000}                             \
CONFIG.CLKOUT2_USED {true}                               \
CONFIG.CLK_OUT1_PORT {clk_50m}                           \
CONFIG.CLK_OUT2_PORT {clk_150m}                          \
CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50.000}               \
CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {150.000}              \
CONFIG.USE_RESET {false}                                 \
CONFIG.CLKIN1_JITTER_PS {200.0}                          \
CONFIG.MMCM_CLKFBOUT_MULT_F {21.000}                     \
CONFIG.MMCM_CLKIN1_PERIOD {20.000}                       \
CONFIG.MMCM_CLKIN2_PERIOD {10.0}                         \
CONFIG.MMCM_CLKOUT0_DIVIDE_F {21.000}                    \
CONFIG.MMCM_CLKOUT1_DIVIDE {7}                           \
CONFIG.NUM_OUT_CLKS {2}                                  \
CONFIG.CLKOUT1_JITTER {187.143}                          \
CONFIG.CLKOUT1_PHASE_ERROR {164.344}                     \
CONFIG.CLKOUT2_JITTER {144.436}                          \
CONFIG.CLKOUT2_PHASE_ERROR {164.344}                     \
CONFIG.USE_PHASE_ALIGNMENT {false}                       \
CONFIG.PRIM_SOURCE {Global_buffer}                       \
CONFIG.CLKOUT1_DRIVES {BUFG}                             \
CONFIG.CLKOUT2_DRIVES {BUFG}                             \
] [get_bd_cells clk_wiz_0]

# add Zynq Processing System ip
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable" }  [get_bd_cells processing_system7_0]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins clk_wiz_0/clk_in1]
set_property -dict [list                      \
CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1}         \
CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1}      \
CONFIG.PCW_QSPI_GRP_FBCLK_ENABLE {1}          \
CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1}        \
CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27}      \
CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1}          \
CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53}   \
CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1}          \
CONFIG.PCW_SD0_GRP_CD_ENABLE {1}              \
CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1}        \
CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1}         \
CONFIG.PCW_I2C0_PERIPHERAL_ENABLE {1}         \
CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {1}           \
CONFIG.PCW_GPIO_MIO_GPIO_IO {MIO}             \
CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1}          \
CONFIG.PCW_USE_S_AXI_HP0 {1}                  \
CONFIG.PCW_USE_S_AXI_HP1 {1}                  \
CONFIG.PCW_USE_FABRIC_INTERRUPT {1}           \
] [get_bd_cells processing_system7_0]
set_property -dict [list CONFIG.PCW_IRQ_F2P_INTR {1}] [get_bd_cells processing_system7_0]

connect_bd_net [get_bd_pins clk_wiz_0/clk_50m] [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins processing_system7_0/S_AXI_HP1_ACLK]

# add Processor System Reset IP
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_clk_wiz_0_50M
connect_bd_net [get_bd_pins clk_wiz_0/clk_50m] [get_bd_pins rst_clk_wiz_0_50M/slowest_sync_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins rst_clk_wiz_0_50M/ext_reset_in]
connect_bd_net [get_bd_pins clk_wiz_0/locked] [get_bd_pins rst_clk_wiz_0_50M/dcm_locked]

# add AXI Periphral InterConnect
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps7_0_axi_periph
set_property -dict [list CONFIG.NUM_MI {4}] [get_bd_cells ps7_0_axi_periph]
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] -boundary_type upper [get_bd_intf_pins ps7_0_axi_periph/S00_AXI]
connect_bd_net [get_bd_pins clk_wiz_0/clk_50m] [get_bd_pins ps7_0_axi_periph/ACLK]
connect_bd_net [get_bd_pins clk_wiz_0/clk_50m] [get_bd_pins ps7_0_axi_periph/S00_ACLK]
connect_bd_net [get_bd_pins clk_wiz_0/clk_50m] [get_bd_pins ps7_0_axi_periph/M00_ACLK]
connect_bd_net [get_bd_pins clk_wiz_0/clk_50m] [get_bd_pins ps7_0_axi_periph/M01_ACLK]
connect_bd_net [get_bd_pins clk_wiz_0/clk_50m] [get_bd_pins ps7_0_axi_periph/M02_ACLK]
connect_bd_net [get_bd_pins clk_wiz_0/clk_50m] [get_bd_pins ps7_0_axi_periph/M03_ACLK]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/interconnect_aresetn] [get_bd_pins ps7_0_axi_periph/ARESETN]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins ps7_0_axi_periph/S00_ARESETN]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins ps7_0_axi_periph/M00_ARESETN]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins ps7_0_axi_periph/M01_ARESETN]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins ps7_0_axi_periph/M02_ARESETN]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins ps7_0_axi_periph/M03_ARESETN]

# add Userspace I/O ip
create_bd_cell -type ip -vlnv pcalab:user:zynq_processor:1.0 zynq_processor_0
connect_bd_intf_net -boundary_type upper [get_bd_intf_pins ps7_0_axi_periph/M00_AXI] [get_bd_intf_pins zynq_processor_0/S00_AXI]
connect_bd_net [get_bd_pins clk_wiz_0/clk_50m] [get_bd_pins zynq_processor_0/s00_axi_aclk]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins zynq_processor_0/s00_axi_aresetn]

# add Video_DynClk (Clocking Wizard)
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 video_dynclk
set_property -dict [list CONFIG.PRIM_IN_FREQ.VALUE_SRC USER] [get_bd_cells video_dynclk]
# 1080p
set_property -dict [list                                 \
CONFIG.USE_DYN_RECONFIG {true}                           \
CONFIG.PRIM_IN_FREQ {50.000}                             \
CONFIG.CLK_OUT1_PORT {pixelClk_5x}                       \
CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {742.5}                \
CONFIG.CLKIN1_JITTER_PS {200.0}                          \
CONFIG.MMCM_DIVCLK_DIVIDE {4}                            \
CONFIG.MMCM_CLKFBOUT_MULT_F {59.375}                     \
CONFIG.MMCM_CLKIN1_PERIOD {20.000}                       \
CONFIG.MMCM_CLKIN2_PERIOD {10.0}                         \
CONFIG.MMCM_CLKOUT0_DIVIDE_F {1.000}                     \
CONFIG.CLKOUT1_JITTER {340.171}                          \
CONFIG.CLKOUT1_PHASE_ERROR {610.813}                     \
CONFIG.USE_PHASE_ALIGNMENT {false}                       \
CONFIG.PRIM_SOURCE {No_buffer}                           \
CONFIG.CLKOUT1_DRIVES {No_buffer}                        \
CONFIG.FEEDBACK_SOURCE {FDBK_ONCHIP}                     \
] [get_bd_cells video_dynclk]
# VGA
set_property -dict [list                \
CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125} \
CONFIG.MMCM_DIVCLK_DIVIDE {1}           \
CONFIG.MMCM_CLKFBOUT_MULT_F {20.000}    \
CONFIG.MMCM_CLKOUT0_DIVIDE_F {8.000}    \
CONFIG.CLKOUT1_JITTER {154.207}         \
CONFIG.CLKOUT1_PHASE_ERROR {164.985}    \
] [get_bd_cells video_dynclk]
connect_bd_intf_net -boundary_type upper [get_bd_intf_pins ps7_0_axi_periph/M02_AXI] [get_bd_intf_pins video_dynclk/s_axi_lite]
connect_bd_net [get_bd_pins clk_wiz_0/clk_50m] [get_bd_pins video_dynclk/s_axi_aclk]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins video_dynclk/s_axi_aresetn]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins video_dynclk/clk_in1]

# add DVIClocking
create_bd_cell -type module -reference DVIClocking DVIClocking_0
connect_bd_net [get_bd_pins video_dynclk/pixelClk_5x] [get_bd_pins DVIClocking_0/PixelClk5X]
connect_bd_net [get_bd_pins video_dynclk/locked] [get_bd_pins DVIClocking_0/aLockedIn]

# add Video_DynClk Reset
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_video_dynclk
connect_bd_net [get_bd_pins DVIClocking_0/PixelClk] [get_bd_pins rst_video_dynclk/slowest_sync_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins rst_video_dynclk/ext_reset_in]
connect_bd_net [get_bd_pins DVIClocking_0/aLockedOut] [get_bd_pins rst_video_dynclk/dcm_locked]

# add AXI_Memory_InterConnect_0
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_mem_intercon_0
set_property -dict [list CONFIG.NUM_MI {1}] [get_bd_cells axi_mem_intercon_0]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins axi_mem_intercon_0/ACLK]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins axi_mem_intercon_0/S00_ACLK]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins axi_mem_intercon_0/M00_ACLK]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/interconnect_aresetn] [get_bd_pins axi_mem_intercon_0/ARESETN]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins axi_mem_intercon_0/S00_ARESETN]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins axi_mem_intercon_0/M00_ARESETN]
connect_bd_intf_net -boundary_type upper [get_bd_intf_pins axi_mem_intercon_0/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

# add AXI_Memory_InterConnect_1
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_mem_intercon_1
set_property -dict [list CONFIG.NUM_MI {1}] [get_bd_cells axi_mem_intercon_1]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins axi_mem_intercon_1/ACLK]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins axi_mem_intercon_1/S00_ACLK]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins axi_mem_intercon_1/M00_ACLK]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/interconnect_aresetn] [get_bd_pins axi_mem_intercon_1/ARESETN]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins axi_mem_intercon_1/S00_ARESETN]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins axi_mem_intercon_1/M00_ARESETN]
connect_bd_intf_net -boundary_type upper [get_bd_intf_pins axi_mem_intercon_1/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP1]

# add AXI-VDMA ip
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 axi_vdma_0
set_property -dict [list CONFIG.c_m_axi_s2mm_data_width.VALUE_SRC PROPAGATED] [get_bd_cells axi_vdma_0]
set_property -dict [list CONFIG.c_m_axis_mm2s_tdata_width {24} CONFIG.c_mm2s_linebuffer_depth {1024} CONFIG.c_s2mm_linebuffer_depth {1024}] [get_bd_cells axi_vdma_0]
connect_bd_intf_net -boundary_type upper [get_bd_intf_pins ps7_0_axi_periph/M01_AXI] [get_bd_intf_pins axi_vdma_0/S_AXI_LITE]
connect_bd_net [get_bd_pins clk_wiz_0/clk_50m] [get_bd_pins axi_vdma_0/s_axi_lite_aclk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins axi_vdma_0/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins axi_vdma_0/m_axis_mm2s_aclk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins axi_vdma_0/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins axi_vdma_0/axi_resetn]
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXI_MM2S] -boundary_type upper [get_bd_intf_pins axi_mem_intercon_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXI_S2MM] -boundary_type upper [get_bd_intf_pins axi_mem_intercon_1/S00_AXI]

# add Video Timing Contoroller
create_bd_cell -type ip -vlnv xilinx.com:ip:v_tc:6.1 v_tc_0
## 1080p
set_property -dict [list           \
CONFIG.VIDEO_MODE {1080p}          \
CONFIG.GEN_F0_VSYNC_VSTART {1083}  \
CONFIG.GEN_F1_VSYNC_VSTART {1083}  \
CONFIG.GEN_HACTIVE_SIZE {1920}     \
CONFIG.GEN_HSYNC_END {2052}        \
CONFIG.GEN_HFRAME_SIZE {2200}      \
CONFIG.GEN_F0_VSYNC_HSTART {1920}  \
CONFIG.GEN_F1_VSYNC_HSTART {1920}  \
CONFIG.GEN_F0_VSYNC_HEND {1920}    \
CONFIG.GEN_F1_VSYNC_HEND {1920}    \
CONFIG.GEN_F0_VFRAME_SIZE {1125}   \
CONFIG.GEN_F1_VFRAME_SIZE {1125}   \
CONFIG.GEN_F0_VSYNC_VEND {1088}    \
CONFIG.GEN_F1_VSYNC_VEND {1088}    \
CONFIG.GEN_F0_VBLANK_HEND {1920}   \
CONFIG.GEN_F1_VBLANK_HEND {1920}   \
CONFIG.GEN_HSYNC_START {2008}      \
CONFIG.GEN_VACTIVE_SIZE {1080}     \
CONFIG.GEN_F0_VBLANK_HSTART {1920} \
CONFIG.GEN_F1_VBLANK_HSTART {1920} \
CONFIG.enable_detection {false}    \
CONFIG.enable_generation {true}    \
] [get_bd_cells v_tc_0]
## VGA
set_property -dict [list          \
CONFIG.VIDEO_MODE {640x480p}      \
CONFIG.GEN_F0_VSYNC_VSTART {489}  \
CONFIG.GEN_F1_VSYNC_VSTART {489}  \
CONFIG.GEN_HACTIVE_SIZE {640}     \
CONFIG.GEN_HSYNC_END {752}        \
CONFIG.GEN_HFRAME_SIZE {800}      \
CONFIG.GEN_F0_VSYNC_HSTART {640}  \
CONFIG.GEN_F1_VSYNC_HSTART {640}  \
CONFIG.GEN_F0_VSYNC_HEND {640}    \
CONFIG.GEN_F1_VSYNC_HEND {640}    \
CONFIG.GEN_F0_VFRAME_SIZE {525}   \
CONFIG.GEN_F1_VFRAME_SIZE {525}   \
CONFIG.GEN_F0_VSYNC_VEND {491}    \
CONFIG.GEN_F1_VSYNC_VEND {491}    \
CONFIG.GEN_F0_VBLANK_HEND {640}   \
CONFIG.GEN_F1_VBLANK_HEND {640}   \
CONFIG.GEN_HSYNC_START {656}      \
CONFIG.GEN_VACTIVE_SIZE {480}     \
CONFIG.GEN_F0_VBLANK_HSTART {640} \
CONFIG.GEN_F1_VBLANK_HSTART {640} \
] [get_bd_cells v_tc_0]
connect_bd_intf_net -boundary_type upper [get_bd_intf_pins ps7_0_axi_periph/M03_AXI] [get_bd_intf_pins v_tc_0/ctrl]
connect_bd_net [get_bd_pins DVIClocking_0/PixelClk] [get_bd_pins v_tc_0/clk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_50m] [get_bd_pins v_tc_0/s_axi_aclk]
connect_bd_net [get_bd_pins rst_video_dynclk/peripheral_aresetn] [get_bd_pins v_tc_0/resetn]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins v_tc_0/s_axi_aresetn]

# add Concat IP
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0
set_property -dict [list CONFIG.NUM_PORTS {3}] [get_bd_cells xlconcat_0]
connect_bd_net [get_bd_pins v_tc_0/irq] [get_bd_pins xlconcat_0/In0]
connect_bd_net [get_bd_pins axi_vdma_0/mm2s_introut] [get_bd_pins xlconcat_0/In1]
connect_bd_net [get_bd_pins axi_vdma_0/s2mm_introut] [get_bd_pins xlconcat_0/In2]
connect_bd_net [get_bd_pins xlconcat_0/dout] [get_bd_pins processing_system7_0/IRQ_F2P]

# add AXI4-Stream to Video Out ip
create_bd_cell -type ip -vlnv xilinx.com:ip:v_axi4s_vid_out:4.0 v_axi4s_vid_out_0
set_property -dict [list \
CONFIG.C_HAS_ASYNC_CLK {1}\
CONFIG.C_VTG_MASTER_SLAVE {1} \
] [get_bd_cells v_axi4s_vid_out_0]
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXIS_MM2S] [get_bd_intf_pins v_axi4s_vid_out_0/video_in]
connect_bd_intf_net [get_bd_intf_pins v_tc_0/vtiming_out] [get_bd_intf_pins v_axi4s_vid_out_0/vtiming_in]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins v_axi4s_vid_out_0/aclk]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins v_axi4s_vid_out_0/aresetn]
connect_bd_net [get_bd_pins DVIClocking_0/PixelClk] [get_bd_pins v_axi4s_vid_out_0/vid_io_out_clk]
connect_bd_net [get_bd_pins rst_video_dynclk/peripheral_reset] [get_bd_pins v_axi4s_vid_out_0/vid_io_out_reset]
connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vtg_ce] [get_bd_pins v_tc_0/gen_clken]

# add Video In to AXI4-Stream IP
create_bd_cell -type ip -vlnv xilinx.com:ip:v_vid_in_axi4s:4.0 v_vid_in_axi4s_0
set_property -dict [list \
CONFIG.C_HAS_ASYNC_CLK {1} \
] [get_bd_cells v_vid_in_axi4s_0]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins v_vid_in_axi4s_0/aclk]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins v_vid_in_axi4s_0/aresetn]
connect_bd_net [get_bd_pins DVIClocking_0/PixelClk] [get_bd_pins v_vid_in_axi4s_0/vid_io_in_clk]
connect_bd_net [get_bd_pins rst_video_dynclk/peripheral_reset] [get_bd_pins v_vid_in_axi4s_0/vid_io_in_reset]
make_bd_intf_pins_external  [get_bd_intf_pins v_vid_in_axi4s_0/vid_io_in]
set_property name vid_io_in [get_bd_intf_ports vid_io_in_0]

# add AXI4-Stream Subset Converter
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_subset_converter:1.1 axis_subset_converter_0
set_property -dict [list                \
CONFIG.S_TDATA_NUM_BYTES.VALUE_SRC USER \
CONFIG.M_TDATA_NUM_BYTES.VALUE_SRC USER \
CONFIG.S_TUSER_WIDTH.VALUE_SRC USER     \
CONFIG.M_TUSER_WIDTH.VALUE_SRC USER     \
CONFIG.S_HAS_TLAST.VALUE_SRC USER       \
CONFIG.M_HAS_TKEEP.VALUE_SRC USER       \
CONFIG.M_HAS_TLAST.VALUE_SRC USER       \
CONFIG.S_TDATA_NUM_BYTES {3}            \
CONFIG.M_TDATA_NUM_BYTES {3}            \
CONFIG.S_TUSER_WIDTH {1}                \
CONFIG.M_TUSER_WIDTH {1}                \
CONFIG.S_HAS_TLAST {1}                  \
CONFIG.M_HAS_TKEEP {1}                  \
CONFIG.M_HAS_TLAST {1}                  \
CONFIG.TDATA_REMAP {tdata[23:0]}        \
CONFIG.TUSER_REMAP {tuser[0:0]}         \
CONFIG.TKEEP_REMAP {3'b111}             \
CONFIG.TLAST_REMAP {tlast[0]}           \
] [get_bd_cells axis_subset_converter_0]
connect_bd_intf_net [get_bd_intf_pins v_vid_in_axi4s_0/video_out] [get_bd_intf_pins axis_subset_converter_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins axis_subset_converter_0/M_AXIS] [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]
connect_bd_net [get_bd_pins clk_wiz_0/clk_150m] [get_bd_pins axis_subset_converter_0/aclk]
connect_bd_net [get_bd_pins rst_clk_wiz_0_50M/peripheral_aresetn] [get_bd_pins axis_subset_converter_0/aresetn]

# Assign Address-Map
assign_bd_address [get_bd_addr_segs {zynq_processor_0/S00_AXI/S00_AXI_reg }]
assign_bd_address [get_bd_addr_segs {axi_vdma_0/S_AXI_LITE/Reg }]
assign_bd_address [get_bd_addr_segs {v_tc_0/ctrl/Reg }]
assign_bd_address [get_bd_addr_segs {video_dynclk/s_axi_lite/Reg }]
assign_bd_address [get_bd_addr_segs {processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM }]
assign_bd_address [get_bd_addr_segs {processing_system7_0/S_AXI_HP1/HP1_DDR_LOWOCM }]
set_property offset 0x43C50000 [get_bd_addr_segs {processing_system7_0/Data/SEG_video_dynclk_Reg}]

# make externel port
make_bd_pins_external [get_bd_pins zynq_processor_0/reg_data_out] [get_bd_pins zynq_processor_0/slv_wire30] [get_bd_pins zynq_processor_0/slv_wire24] [get_bd_pins zynq_processor_0/slv_wire7] [get_bd_pins zynq_processor_0/slv_wire25] [get_bd_pins zynq_processor_0/slv_wire22] [get_bd_pins zynq_processor_0/slv_wire23] [get_bd_pins zynq_processor_0/slv_wire12] [get_bd_pins zynq_processor_0/slv_wire0] [get_bd_pins zynq_processor_0/slv_wire13] [get_bd_pins zynq_processor_0/slv_wire4] [get_bd_pins zynq_processor_0/slv_wire1] [get_bd_pins zynq_processor_0/slv_wire10] [get_bd_pins zynq_processor_0/slv_wire28] [get_bd_pins zynq_processor_0/slv_wire5] [get_bd_pins zynq_processor_0/slv_wire11] [get_bd_pins zynq_processor_0/slv_wire16] [get_bd_pins zynq_processor_0/slv_wire2] [get_bd_pins zynq_processor_0/axi_araddr] [get_bd_pins zynq_processor_0/slv_wire29] [get_bd_pins zynq_processor_0/slv_wire26] [get_bd_pins zynq_processor_0/slv_wire20] [get_bd_pins zynq_processor_0/slv_wire3] [get_bd_pins zynq_processor_0/slv_wire17] [get_bd_pins zynq_processor_0/slv_wire14] [get_bd_pins zynq_processor_0/slv_wire8] [get_bd_pins zynq_processor_0/slv_wire21] [get_bd_pins zynq_processor_0/slv_wire27] [get_bd_pins zynq_processor_0/slv_wire18] [get_bd_pins zynq_processor_0/slv_wire9] [get_bd_pins zynq_processor_0/slv_wire15] [get_bd_pins zynq_processor_0/slv_wire6] [get_bd_pins zynq_processor_0/slv_wire19] [get_bd_pins zynq_processor_0/slv_wire31]
make_bd_intf_pins_external [get_bd_intf_pins v_axi4s_vid_out_0/vid_io_out]
make_bd_pins_external      [get_bd_pins v_axi4s_vid_out_0/locked]
create_bd_port -dir O PixelClk
connect_bd_net [get_bd_pins /DVIClocking_0/PixelClk] [get_bd_ports PixelClk]
create_bd_port -dir O SerialClk
connect_bd_net [get_bd_pins /DVIClocking_0/SerialClk] [get_bd_ports SerialClk]
create_bd_port -dir O -type clk ps_clk
connect_bd_net [get_bd_pins /clk_wiz_0/clk_50m] [get_bd_ports ps_clk]

# change port name
set_property name reg_data_out [get_bd_ports reg_data_out_0]
set_property name axi_araddr   [get_bd_ports axi_araddr_0]
set_property name slv_wire00   [get_bd_ports slv_wire0_0]
set_property name slv_wire01   [get_bd_ports slv_wire1_0]
set_property name slv_wire02   [get_bd_ports slv_wire2_0]
set_property name slv_wire03   [get_bd_ports slv_wire3_0]
set_property name slv_wire04   [get_bd_ports slv_wire4_0]
set_property name slv_wire05   [get_bd_ports slv_wire5_0]
set_property name slv_wire06   [get_bd_ports slv_wire6_0]
set_property name slv_wire07   [get_bd_ports slv_wire7_0]
set_property name slv_wire08   [get_bd_ports slv_wire8_0]
set_property name slv_wire09   [get_bd_ports slv_wire9_0]
set_property name slv_wire10   [get_bd_ports slv_wire10_0]
set_property name slv_wire11   [get_bd_ports slv_wire11_0]
set_property name slv_wire12   [get_bd_ports slv_wire12_0]
set_property name slv_wire13   [get_bd_ports slv_wire13_0]
set_property name slv_wire14   [get_bd_ports slv_wire14_0]
set_property name slv_wire15   [get_bd_ports slv_wire15_0]
set_property name slv_wire16   [get_bd_ports slv_wire16_0]
set_property name slv_wire17   [get_bd_ports slv_wire17_0]
set_property name slv_wire18   [get_bd_ports slv_wire18_0]
set_property name slv_wire19   [get_bd_ports slv_wire19_0]
set_property name slv_wire20   [get_bd_ports slv_wire20_0]
set_property name slv_wire21   [get_bd_ports slv_wire21_0]
set_property name slv_wire22   [get_bd_ports slv_wire22_0]
set_property name slv_wire23   [get_bd_ports slv_wire23_0]
set_property name slv_wire24   [get_bd_ports slv_wire24_0]
set_property name slv_wire25   [get_bd_ports slv_wire25_0]
set_property name slv_wire26   [get_bd_ports slv_wire26_0]
set_property name slv_wire27   [get_bd_ports slv_wire27_0]
set_property name slv_wire28   [get_bd_ports slv_wire28_0]
set_property name slv_wire29   [get_bd_ports slv_wire29_0]
set_property name slv_wire30   [get_bd_ports slv_wire30_0]
set_property name slv_wire31   [get_bd_ports slv_wire31_0]
set_property name vid_io_out   [get_bd_intf_ports vid_io_out_0]
set_property name vid_locked   [get_bd_ports locked_0]

# close block design
regenerate_bd_layout
save_bd_design
close_bd_design [get_bd_designs block_design]

# Generate IPs and Block Design
generate_target all [get_files ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.srcs/sources_1/ip/rgb2dvi_0/rgb2dvi_0.xci]
generate_target all [get_files ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.srcs/sources_1/bd/block_design/block_design.bd]

catch { config_ip_cache -export [get_ips -all rgb2dvi_0] }
catch { config_ip_cache -export [get_ips -all block_design_clk_wiz_0_0] }
catch { config_ip_cache -export [get_ips -all block_design_processing_system7_0_0] }
catch { config_ip_cache -export [get_ips -all block_design_zynq_processor_0_0] }
catch { config_ip_cache -export [get_ips -all block_design_rst_clk_wiz_0_50M_0] }
catch { config_ip_cache -export [get_ips -all block_design_auto_pc_0] }
catch { config_ip_cache -export [get_ips -all block_design_xbar_0] }
catch { config_ip_cache -export [get_ips -all block_design_video_dynclk_0] }
catch { config_ip_cache -export [get_ips -all block_design_rst_video_dynclk_0] }
catch { config_ip_cache -export [get_ips -all block_design_axi_vdma_0_0] }
catch { config_ip_cache -export [get_ips -all block_design_v_tc_0_0] }
catch { config_ip_cache -export [get_ips -all block_design_v_axi4s_vid_out_0_0] }
catch { config_ip_cache -export [get_ips -all block_design_s00_mmu_0] }
catch { config_ip_cache -export [get_ips -all block_design_auto_pc_1] }
catch { config_ip_cache -export [get_ips -all block_design_auto_pc_2] }
catch { config_ip_cache -export [get_ips -all block_design_v_vid_in_axi4s_0_0] }
catch { config_ip_cache -export [get_ips -all block_design_axis_subset_converter_0] }

export_ip_user_files -of_objects [get_files ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.srcs/sources_1/ip/rgb2dvi_0/rgb2dvi_0.xci] -no_script -sync -force -quiet
export_ip_user_files -of_objects [get_files ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.srcs/sources_1/bd/block_design/block_design.bd] -no_script -sync -force -quiet
create_ip_run [get_files -of_objects [get_fileset sources_1] ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.srcs/sources_1/ip/rgb2dvi_0/rgb2dvi_0.xci]
create_ip_run [get_files -of_objects [get_fileset sources_1] ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.srcs/sources_1/bd/block_design/block_design.bd]
launch_runs -jobs ${JOBS} {rgb2dvi_0_synth_1 block_design_clk_wiz_0_0_synth_1 block_design_processing_system7_0_0_synth_1 block_design_zynq_processor_0_0_synth_1 block_design_rst_clk_wiz_0_50M_0_synth_1 block_design_auto_pc_0_synth_1 block_design_xbar_0_synth_1 block_design_video_dynclk_0_synth_1 block_design_rst_video_dynclk_0_synth_1 block_design_DVIClocking_0_0_synth_1 block_design_axi_vdma_0_0_synth_1 block_design_v_tc_0_0_synth_1 block_design_v_axi4s_vid_out_0_0_synth_1 block_design_s00_mmu_0_synth_1 block_design_auto_pc_1_synth_1 block_design_auto_pc_2_synth_1 block_design_v_vid_in_axi4s_0_0_synth_1 block_design_axis_subset_converter_0_synth_1}
export_simulation -of_objects [get_files ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.srcs/sources_1/bd/block_design/block_design.bd] -directory ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.ip_user_files/sim_scripts -ip_user_files_dir ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.ip_user_files -ipstatic_source_dir ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.ip_user_files/ipstatic -lib_map_path [list {modelsim=${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.cache/compile_simlib/modelsim} {questa=${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.cache/compile_simlib/questa} {ies=${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.cache/compile_simlib/ies} {xcelium=${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.cache/compile_simlib/xcelium} {vcs=${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.cache/compile_simlib/vcs} {riviera=${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.cache/compile_simlib/riviera}] -use_ip_compiled_libs -force -quiet

# create hdl-wrapper of block design
make_wrapper -files [get_files ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.srcs/sources_1/bd/block_design/block_design.bd] -top
add_files -norecurse ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.srcs/sources_1/bd/block_design/hdl/block_design_wrapper.v
update_compile_order -fileset sources_1

exit
