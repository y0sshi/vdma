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
	wire vid_hsync, vid_vsync, vid_VDE;
	wire [7:0] vid_r, vid_g, vid_b;

	/* Zynq Interface */
	zynq_ps_interface #(
		.C_S_AXI_DATA_WIDTH (C_S_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH (C_S_AXI_ADDR_WIDTH)
	)
	zynq_ps_interface_inst0 (
		/* Clock */
		.ps_clk    (ps_clk), // 50 MHz

		/* Video Direct Memory Access */
		.PixelClk  (PixelClk ),
		.SerialClk (SerialClk),
		.vid_rstn  (vid_rstn ),
		.vid_VDE   (vid_VDE  ),
		.vid_hsync (vid_hsync),
		.vid_vsync (vid_vsync),
		.vid_data  ({vid_r, vid_g, vid_b}),

		/* debug */
		.led       (),
		.sw        (sw)
	);
	
	rgb2dvi_0 rgb2dvi_inst (
	   .PixelClk    (PixelClk     ),
	   .SerialClk   (SerialClk    ),
	   .aRst_n      (vid_rstn     ),
	   .vid_pData   ({vid_r, vid_b, vid_g}),
	   .vid_pVDE    (vid_VDE      ),
	   .vid_pHSync  (vid_hsync    ),
	   .vid_pVSync  (vid_vsync    ),
	   .TMDS_Data_p (hdmi_tx_p    ),
	   .TMDS_Data_n (hdmi_tx_n    ),
	   .TMDS_Clk_p  (hdmi_tx_clk_p),
	   .TMDS_Clk_n  (hdmi_tx_clk_n)
	);
	
	assign led[2:0]  = {vid_rstn, vid_VDE, vid_vsync, vid_hsync};
	assign led5 = {vid_r[6], vid_g[6], vid_b[6]};
	assign led6 = {vid_r[7], vid_g[7], vid_b[7]};

endmodule
`default_nettype wire
