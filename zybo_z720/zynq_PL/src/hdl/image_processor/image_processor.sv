//-----------------------------------------------------------------------------
// <image_processor>
//  - gray scaling module
//  - filter module
//-----------------------------------------------------------------------------
// Version 1.00 (Sep. 23, 2020)
//  - Connected rgb2ycbcr module
//  - Connected filter_3x3 module
//  - Other minor refinements
//-----------------------------------------------------------------------------
// (C) 2020 Naofumi Yoshinaga. All rights reserved.
//-----------------------------------------------------------------------------

`default_nettype none

module image_processor
	#(
		parameter integer DATA_WIDTH =    8,
		parameter integer H_ACTIVE   =   -1,
		parameter integer V_ACTIVE   =   -1,
		parameter integer H_FRAME    =   -1,
		parameter integer V_FRAME    =   -1,
		parameter integer RAM_SIZE   = 4096
	)
	(
		input  wire  clk,
		input  wire  rst,
		input  wire  [DATA_WIDTH*3-1:0]    in_data,
		input  wire  [$clog2(V_FRAME)-1:0] in_vcnt,
		input  wire  [$clog2(H_FRAME)-1:0] in_hcnt,
		output logic [DATA_WIDTH*3-1:0]    out_data,
		output logic [$clog2(V_FRAME)-1:0] out_vcnt,
		output logic [$clog2(H_FRAME)-1:0] out_hcnt,
		output logic out_vde
	);

	/* Gray Scaling */
	wire [DATA_WIDTH-1:0] gray_data;
	wire [$clog2(V_FRAME)-1:0] gray_vcnt;
	wire [$clog2(H_FRAME)-1:0] gray_hcnt;
	wire gray_vde;
	rgb2ycbcr #(
		.BIT_WIDTH (DATA_WIDTH)
	)
	rgb2ycbcr_inst (
		.clock  (clk                                 ),
		.in_r   (in_data[DATA_WIDTH*3-1:DATA_WIDTH*2]),
		.in_g   (in_data[DATA_WIDTH*2-1:DATA_WIDTH*1]),
		.in_b   (in_data[DATA_WIDTH  -1:           0]),
		.out_y  (gray_data                           ),
		.out_cb (                                    ),
		.out_cr (                                    )
	);
	coord_adjuster #(
		.FRAME_HEIGHT (V_FRAME),
		.FRAME_WIDTH  (H_FRAME),
		.LATENCY      (4      )
	)
	coord_adjuster (
		.clock    (clk      ),
		.in_vcnt  (in_vcnt  ),
		.in_hcnt  (in_hcnt  ),
		.out_vcnt (gray_vcnt),
		.out_hcnt (gray_hcnt)
	);
	assign gray_vde = (gray_vcnt < V_ACTIVE) & (gray_hcnt < H_ACTIVE);

	assign out_data = {3{gray_data}};
	assign out_vcnt = gray_vcnt;
	assign out_hcnt = gray_hcnt;
	assign out_vde  = gray_vde;

endmodule

`default_nettype wire
