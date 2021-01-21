//-----------------------------------------------------------------------------
// <vdma_top>
//  - Top module of vdma_test project
//-----------------------------------------------------------------------------
// Version 1.00 (Sep. 23, 2020)
//  - initial version
//-----------------------------------------------------------------------------
// (C) 2020 Naofumi Yoshinaga. All rights reserved.
//-----------------------------------------------------------------------------

`default_nettype none

module vdma_top
	#(
		/* Clock */
		parameter integer PS_CLK_FREQ      = -1,

		/* HDMI */
		parameter integer VID_H_ACTIVE      = -1,
		parameter integer VID_H_FRONT_PORCH = -1,
		parameter integer VID_H_SYNC_WIDTH  = -1,
		parameter integer VID_H_BACK_PORCH  = -1,
		parameter integer VID_V_ACTIVE      = -1,
		parameter integer VID_V_FRONT_PORCH = -1,
		parameter integer VID_V_SYNC_WIDTH  = -1,
		parameter integer VID_V_BACK_PORCH  = -1,

		/* AXI parameters (PS-PL) */
		parameter integer C_S_AXI_DATA_WIDTH = -1,
		parameter integer C_S_AXI_ADDR_WIDTH = -1
	)
	(
		/* HDMI */
		output wire       hdmi_tx_clk_n, hdmi_tx_clk_p,
		output wire [2:0] hdmi_tx_n, hdmi_tx_p,

		/* System */
		input  wire [3:0] btn,
		input  wire [3:0] sw,
		output wire [2:0] led5, led6,
		output wire [3:0] led
	);

	/* local parameter */
	localparam integer VID_H_BLANK = VID_H_FRONT_PORCH + VID_H_SYNC_WIDTH + VID_H_BACK_PORCH;
	localparam integer VID_V_BLANK = VID_V_FRONT_PORCH + VID_V_SYNC_WIDTH + VID_V_BACK_PORCH;
	localparam integer VID_H_FRAME = VID_H_ACTIVE + VID_H_BLANK;
	localparam integer VID_V_FRAME = VID_V_ACTIVE + VID_V_BLANK;

	/* clock and reset */
	wire ps_clk;     // 50.00 MHz (ps-pl, motor)
	wire rst;
	reg [3:0] sys_reset_sync_regs = 4'h0;
	always @(posedge ps_clk) begin
		sys_reset_sync_regs <= {sys_reset_sync_regs[2:0], !btn[0]};
	end
	assign rst = sys_reset_sync_regs[3];
	
	/* Video Direct Memory Access */
	wire PixelClk, SerialClk, vid_rstn;
	wire vid_in_hsync, vid_in_vsync, vid_in_VDE;
	wire [$clog2(VID_H_FRAME)-1:0] vid_in_hcnt;
	wire [$clog2(VID_V_FRAME)-1:0] vid_in_vcnt;
	wire vid_out_hsync, vid_out_vsync, vid_out_VDE;
	wire [$clog2(VID_H_FRAME)-1:0] vid_out_hcnt;
	wire [$clog2(VID_V_FRAME)-1:0] vid_out_vcnt;
	wire vid_out_hblank, vid_out_vblank, vid_out_field;
	wire [7:0] vid_in_r, vid_in_g, vid_in_b;
	wire [7:0] vid_out_r, vid_out_g, vid_out_b;

	/* Video Sync to Count */
	vid_sync2cnt #(
		.H_ACTIVE      (VID_H_ACTIVE     ),
		.H_FRONT_PORCH (VID_H_FRONT_PORCH),
		.H_SYNC_WIDTH  (VID_H_SYNC_WIDTH ),
		.H_BACK_PORCH  (VID_H_BACK_PORCH ),
		.V_ACTIVE      (VID_V_ACTIVE     ),
		.V_FRONT_PORCH (VID_V_FRONT_PORCH),
		.V_SYNC_WIDTH  (VID_V_SYNC_WIDTH ),
		.V_BACK_PORCH  (VID_V_BACK_PORCH )
	) vid_sync2cnt_inst (
		.clk      (PixelClk    ),
		.rst      (!vid_rstn   ),
		.in_vsync (vid_in_vsync),
		.in_hsync (vid_in_hsync),
		.out_vcnt (vid_in_vcnt ),
		.out_hcnt (vid_in_hcnt )
	);

	/* Image Processing */
	image_processor #(
		.DATA_WIDTH (8           ),
		.H_ACTIVE   (VID_H_ACTIVE),
		.V_ACTIVE   (VID_V_ACTIVE),
		.H_FRAME    (VID_H_FRAME ),
		.V_FRAME    (VID_V_FRAME ),
		.RAM_SIZE   (4096        )
	) image_processor_inst (
		.clk        (PixelClk      ),
		.rst        (!vid_rstn     ),
		.sw         (sw            ),
		.in_data    ({vid_in_r, vid_in_g, vid_in_b}),
		.in_vcnt    (vid_in_vcnt   ),
		.in_hcnt    (vid_in_hcnt   ),
		.out_data   ({vid_out_r, vid_out_g, vid_out_b}),
		.out_vcnt   (vid_out_vcnt  ),
		.out_hcnt   (vid_out_hcnt  ),
		.out_hblank (vid_out_hblank),
		.out_vblank (vid_out_vblank),
		.out_field  (vid_out_field ),
		.out_vde    (vid_out_VDE   ),
		.in_lsdbuf_addr          (),
		.in_lsdbuf_write_protect (),
		.out_lsdbuf_line_num     (),
		.out_lsdbuf_start_v      (),
		.out_lsdbuf_start_h      (),
		.out_lsdbuf_end_v        (),
		.out_lsdbuf_end_h        (),
		.out_lsdbuf_ready        ()
	);

	/* Count to Video Sync */
	vid_cnt2sync #(
		.H_ACTIVE      (VID_H_ACTIVE     ),
		.H_FRONT_PORCH (VID_H_FRONT_PORCH),
		.H_SYNC_WIDTH  (VID_H_SYNC_WIDTH ),
		.H_BACK_PORCH  (VID_H_BACK_PORCH ),
		.V_ACTIVE      (VID_V_ACTIVE     ),
		.V_FRONT_PORCH (VID_V_FRONT_PORCH),
		.V_SYNC_WIDTH  (VID_V_SYNC_WIDTH ),
		.V_BACK_PORCH  (VID_V_BACK_PORCH )
	) vid_cnt2sync_inst (
		.clk       (PixelClk     ),
		.rst       (!vid_rstn    ),
		.in_vcnt   (vid_out_vcnt ),
		.in_hcnt   (vid_out_hcnt ),
		.out_vsync (vid_out_vsync),
		.out_hsync (vid_out_hsync)
	);

	/* Zynq Interface */
	zynq_ps_interface #(
		.C_S_AXI_DATA_WIDTH (C_S_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH (C_S_AXI_ADDR_WIDTH)
	)
	zynq_ps_interface_inst0 (
		/* Clock */
		.ps_clk    (ps_clk), // 50 MHz

		/* Video Direct Memory Access */
		.PixelClk      (PixelClk                         ),
		.SerialClk     (SerialClk                        ),
		.vid_rstn      (vid_rstn                         ),
		.vid_out_VDE   (vid_in_VDE                       ),
		.vid_out_hsync (vid_in_hsync                     ),
		.vid_out_vsync (vid_in_vsync                     ),
		.vid_out_data  ({vid_in_r, vid_in_g, vid_in_b}   ),
		.vid_in_VDE    (vid_out_VDE                      ),
		.vid_in_hsync  (vid_out_hsync                    ),
		.vid_in_vsync  (vid_out_vsync                    ),
		.vid_in_data   ({vid_out_r, vid_out_g, vid_out_b}),

		/* debug */
		.led       (),
		.sw        (sw)
	);
	
	rgb2dvi_0 rgb2dvi_inst (
		.PixelClk    (PixelClk                         ),
		.SerialClk   (SerialClk                        ),
		.aRst_n      (vid_rstn                         ),
		.vid_pData   ({vid_out_r, vid_out_b, vid_out_g}),
		.vid_pVDE    (vid_out_VDE                      ),
		.vid_pHSync  (vid_out_hsync                    ),
		.vid_pVSync  (vid_out_vsync                    ),
		.TMDS_Data_p (hdmi_tx_p                        ),
		.TMDS_Data_n (hdmi_tx_n                        ),
		.TMDS_Clk_p  (hdmi_tx_clk_p                    ),
		.TMDS_Clk_n  (hdmi_tx_clk_n                    )
	);
	
	assign led[2:0]  = {vid_rstn, vid_in_VDE, vid_in_vsync, vid_in_hsync};
	assign led5 = {vid_out_r[7], vid_out_g[7], vid_out_b[7]};
	assign led6 = {vid_in_r[7], vid_in_g[7], vid_in_b[7]};

endmodule
`default_nettype wire
