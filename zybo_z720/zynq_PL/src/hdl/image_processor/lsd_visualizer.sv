//-----------------------------------------------------------------------------
// <lsd_visualizer>
//  - visualize <simple_lsd> for debug
//  - display with HDMI
//-----------------------------------------------------------------------------
// Version 1.00 (Sep. 23, 2020)
//  - Connected Simple-LSD line-draw module
//  - Connected Simple-LSD mem-overlay module
//  - Other minor refinements
//-----------------------------------------------------------------------------
// (C) 2020 Naofumi Yoshinaga. All rights reserved.
//-----------------------------------------------------------------------------

`default_nettype none

module lsd_visualizer
	#(
		parameter integer BIT_WIDTH    =    8,
		parameter integer IMAGE_WIDTH  =  640,
		parameter integer IMAGE_HEIGHT =  480,
		parameter integer FRAME_WIDTH  =   -1,
		parameter integer FRAME_HEIGHT =   -1,
		parameter integer RAM_SIZE     = 4096
	)
	(
		/* Clocks and Reset */
		input  wire pixel_clk, rst,

		/* Inputs from S-LSD */
		input  wire in_valid, in_flag,
		input  wire [$clog2(FRAME_HEIGHT)-1:0] in_vcnt,
		input  wire [$clog2(FRAME_WIDTH )-1:0] in_hcnt,
		input  wire [$clog2(FRAME_HEIGHT)-1:0] in_start_v, in_end_v,
		input  wire [$clog2(FRAME_WIDTH )-1:0] in_start_h, in_end_h,

		/* Outputs to HDMI */
		output wire [BIT_WIDTH-1:0] out_r, out_g, out_b,
		output wire [$clog2(FRAME_HEIGHT)-1:0] out_vcnt,
		output wire [$clog2(FRAME_WIDTH )-1:0] out_hcnt
	);

	/* draw result of Simple-LSD result */
	wire [$clog2(FRAME_HEIGHT)-1:0] line_draw_vcnt;
	wire [$clog2(FRAME_WIDTH )-1:0] line_draw_hcnt;
	wire [BIT_WIDTH-1:0] line_draw_r, line_draw_g, line_draw_b;
	line_draw #(
		.BIT_WIDTH    (BIT_WIDTH),
		.IMAGE_HEIGHT (IMAGE_HEIGHT),
		.IMAGE_WIDTH  (IMAGE_WIDTH),
		.FRAME_HEIGHT (FRAME_HEIGHT),
		.FRAME_WIDTH  (FRAME_WIDTH),
		.FIFO_SIZE    (),
		.AUTO_ERASE   ()
	)
	line_draw_inst (
		.clock      (pixel_clk),
		.n_rst      (!rst),
		.in_en      (in_valid & in_flag),
		.in_vcnt    (in_vcnt),
		.in_hcnt    (in_hcnt),
		.in_start_h (in_start_h),
		.in_start_v (in_start_v),
		.in_end_h   (in_end_h),
		.in_end_v   (in_end_v),
		.out_r      (line_draw_r),
		.out_g      (line_draw_g),
		.out_b      (line_draw_b),
		.out_vcnt   (line_draw_vcnt),
		.out_hcnt   (line_draw_hcnt)
	);

	/* overlay utilization of memory */
	slsd_mem_overlay #(
		.BIT_WIDTH    (BIT_WIDTH),
		.IMAGE_HEIGHT (IMAGE_HEIGHT),
		.IMAGE_WIDTH  (IMAGE_WIDTH),
		.FRAME_HEIGHT (FRAME_HEIGHT),
		.FRAME_WIDTH  (FRAME_WIDTH),
		.RAM_SIZE     (RAM_SIZE)
	)
	slsd_mem_overlay_inst (
		.clock    (pixel_clk),
		.n_rst    (!rst),
		.in_valid (in_valid),
		.in_flag  (in_flag),
		.in_vcnt  (line_draw_vcnt),
		.in_hcnt  (line_draw_hcnt),
		.in_r     (line_draw_r),
		.in_g     (line_draw_g),
		.in_b     (line_draw_b),
		.out_vcnt (out_vcnt),
		.out_hcnt (out_hcnt),
		.out_r    (out_r),
		.out_g    (out_g),
		.out_b    (out_b)
	);

endmodule

`default_nettype wire
