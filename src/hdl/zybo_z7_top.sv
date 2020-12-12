//-----------------------------------------------------------------------------
// <zybo_z7_top>
//  - Top module of Zybo Z7
//-----------------------------------------------------------------------------
// Version 1.00 (Sep. 25, 2020)
//  - Added I/O ports of Zybo Z7
//  - Connected I/O ports to <slab_top>
//-----------------------------------------------------------------------------
// (C) 2020 Naofumi Yoshinaga. All rights reserved.
//-----------------------------------------------------------------------------

`default_nettype none

module zybo_z7_top
	(
		/* Clock signal */
		//input  wire       sysclk,

		/* Switches */
		input  wire [3:0] sw,

		/* Buttons */
		input  wire [3:0] btn,

		/* LEDs */
		output wire [3:0] led,

		/* RGB LED 5 (Zybo Z7-20 only) */
		output wire       led5_r,
		output wire       led5_g,
		output wire       led5_b,

		/* RGB LED 6 */
		output wire       led6_r,
		output wire       led6_g,
		output wire       led6_b,

		/* Audio Codec */
		//output wire       ac_bclk,
		//output wire       ac_mclk,
		//output wire       ac_muten,
		//output wire       ac_pbdat,
		//output wire       ac_pblrc,
		//input  wire       ac_recdat,
		//output wire       ac_reclrc,
		//output wire       ac_scl,
		//inout  wire       ac_sda,

		/* Additional Ethernet signals */
		//inout  wire       eth_int_pu_b,
		//inout  wire       eth_rst_b,

		/* USB-OTG over-current detect pin */
		//inout  wire       otg_oc,

		/* Fan (Zybo Z7-20 only) */
		//inout  wire       fan_fb_pu,

		/* HDMI RX */
		//output wire       hdmi_rx_hpd,
		//inout  wire       hdmi_rx_scl,
		//inout  wire       hdmi_rx_sda,
		//input  wire       hdmi_rx_clk_n,
		//input  wire       hdmi_rx_clk_p,
		//input  wire [2:0] hdmi_rx_n,
		//input  wire [2:0] hdmi_rx_p,

		/* HDMI RX CEC (Zybo Z7-20 only) */
		//inout  wire       hdmi_rx_cec,

		/* HDMI TX */
		//input  wire       hdmi_tx_hpd,
		//inout  wire       hdmi_tx_scl,
		//inout  wire       hdmi_tx_sda,
		output wire       hdmi_tx_clk_n,
		output wire       hdmi_tx_clk_p,
		output wire [2:0] hdmi_tx_n,
		output wire [2:0] hdmi_tx_p

		/* HDMI TX CEC (Zybo Z7-20 only) */
		//inout  wire       hdmi_tx_cec,

		/* Pmod Header JA (XADC) */
		//inout  wire [7:0] ja,

		/* Pmod Header JB (Zybo Z7-20 only) */
		//inout  wire [7:0] jb,

		/* Pmod Header JC */
		//inout  wire [7:0] jc,

		/* Pmod Header JD */
		//inout  wire [7:0] jd,

		/* Pmod Header JE */
		//inout  wire [7:0] je

		/* Pcam MIPI CSI-2 Connector */
		//input  wire       dphy_clk_lp_n,
		//input  wire       dphy_clk_lp_p,
		//input  wire [1:0] dphy_data_lp_n,
		//input  wire [1:0] dphy_data_lp_p,
		//input  wire       dphy_hs_clock_clk_n,
		//input  wire       dphy_hs_clock_clk_p,
		//input  wire [1:0] dphy_data_hs_n,
		//input  wire [1:0] dphy_data_hs_p,
		//input  wire       cam_clk,
		//inout  wire       cam_gpio,
		//inout  wire       cam_scl,
		//inout  wire       cam_sda,

		/* Unloaded Crypto Chip SWI (for future use) */
		//inout  wire       crypto_sda,

		/* Unconnected Pins (Zybo Z7-20 only) */
		//inout  wire       netic19_t9,
		//inout  wire       netic19_u10,
		//inout  wire       netic19_u5,
		//inout  wire       netic19_u8,
		//inout  wire       netic19_u9,
		//inout  wire       netic19_v10,
		//inout  wire       netic19_v11,
		//inout  wire       netic19_v5,
		//inout  wire       netic19_w10,
		//inout  wire       netic19_w11,
		//inout  wire       netic19_w9,
		//inout  wire       netic19_y9
	);

	vdma_top #(
		/* Clock */
		.PS_CLK_FREQ        (50 * 10 ** 6),

		/* Video */
		.VID_H_ACTIVE       (        1920),
		.VID_H_FRONT_PORCH  (          88),
		.VID_H_SYNC_WIDTH   (          44),
		.VID_H_BACK_PORCH   (         148),
		.VID_V_ACTIVE       (        1080),
		.VID_V_FRONT_PORCH  (           4),
		.VID_V_SYNC_WIDTH   (           5),
		.VID_V_BACK_PORCH   (          36),

		/* System */
		.C_S_AXI_DATA_WIDTH (          32),
		.C_S_AXI_ADDR_WIDTH (           7)
	)
	vdma_test (
		/* HDMI */
		.hdmi_tx_clk_n    (hdmi_tx_clk_n), // output
		.hdmi_tx_clk_p    (hdmi_tx_clk_p), // output
		.hdmi_tx_n        (hdmi_tx_n    ), // output
		.hdmi_tx_p        (hdmi_tx_p    ), // output

		/* System */
		.btn              (btn                     ), // input
		.sw               (sw                      ), // input
		.led5             ({led5_r, led5_g, led5_b}), // output
		.led6             ({led6_r, led6_g, led6_b}), // output
		.led              (led                     )  // output
	);

endmodule

`default_nettype wire
