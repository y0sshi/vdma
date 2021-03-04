//-----------------------------------------------------------------------------
// <image_processor>
//  - Simple-LSD module
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
		/* clock and reset */
		input  wire  pixelclk, psclk, rst,
		input  wire  [3:0] sw,

		/* input image */
		input  wire  [DATA_WIDTH*3-1:0]    in_data,
		input  wire  [$clog2(V_FRAME)-1:0] in_vcnt,
		input  wire  [$clog2(H_FRAME)-1:0] in_hcnt,

		/* a buffer of LSD */
		input  wire  [$clog2(RAM_SIZE)-1:0] in_lsdbuf_raddr,
		input  wire  in_lsdbuf_write_protect,
		output logic [$clog2(RAM_SIZE)-1:0] out_lsdbuf_line_num,
		output logic [$clog2(V_FRAME)-1:0]  out_lsdbuf_start_v, out_lsdbuf_end_v,
		output logic [$clog2(H_FRAME)-1:0]  out_lsdbuf_start_h, out_lsdbuf_end_h,
		output logic out_lsdbuf_ready,

		/* output image */
		output logic [DATA_WIDTH*3-1:0]    out_data,
		output logic [$clog2(V_FRAME)-1:0] out_vcnt,
		output logic [$clog2(H_FRAME)-1:0] out_hcnt,
		output logic out_hblank, out_vblank,
		output logic out_field,
		output logic out_vde
	);

	wire in_hblank, in_vblank, in_vde;
	assign in_hblank = (H_ACTIVE <= in_hcnt);
	assign in_vblank = (V_ACTIVE <= in_vcnt);
	assign in_vde    = (in_vcnt < V_ACTIVE) & (in_hcnt < H_ACTIVE);

	/* Gray Scaling */
	wire [DATA_WIDTH-1:0] gray_data;
	wire [$clog2(V_FRAME)-1:0] gray_vcnt;
	wire [$clog2(H_FRAME)-1:0] gray_hcnt;
	wire gray_vde, gray_hblank, gray_vblank, gray_field;
	rgb2ycbcr #(
		.BIT_WIDTH (DATA_WIDTH)
	)
	rgb2ycbcr_inst (
		.clock (pixelclk                                 ),
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
		.clock    (pixelclk      ),
		.in_vcnt  (in_vcnt  ),
		.in_hcnt  (in_hcnt  ),
		.out_vcnt (gray_vcnt),
		.out_hcnt (gray_hcnt)
	);
	assign gray_hblank = (H_ACTIVE <= gray_hcnt);
	assign gray_vblank = (V_ACTIVE <= gray_vcnt);
	assign gray_field  = 1'b0;
	assign gray_vde    = (gray_vcnt < V_ACTIVE) & (gray_hcnt < H_ACTIVE);

	/* Stretch contrast */
	wire [DATA_WIDTH-1:0] cs_data;
	wire [$clog2(V_FRAME)-1:0] cs_vcnt;
	wire [$clog2(H_FRAME)-1:0] cs_hcnt;
	wire cs_vde, cs_hblank, cs_vblank, cs_field;
	contrast_stretch #(
		.BIT_WIDTH     (DATA_WIDTH),
		.IMAGE_HEIGHT  (V_ACTIVE  ),
		.IMAGE_WIDTH   (H_ACTIVE  ),
		.FRAME_HEIGHT  (V_FRAME   ),
		.FRAME_WIDTH   (H_FRAME   ),
		.WINDOW_RANGE  (),
		.EQUALIZE_HIST ()
	)
	contrast_stretch_inst (
		.clock     (pixelclk      ),
		.n_rst     (!rst     ),
		.in_pixel  (gray_data),
		.in_vcnt   (gray_vcnt),
		.in_hcnt   (gray_hcnt),
		.out_pixel (cs_data  ),
		.out_vcnt  (cs_vcnt  ),
		.out_hcnt  (cs_hcnt  )
	);
	assign cs_hblank = (H_ACTIVE <= cs_hcnt);
	assign cs_vblank = (V_ACTIVE <= cs_vcnt);
	assign cs_field  = 1'b0;
	assign cs_vde    = (cs_vcnt < V_ACTIVE) & (cs_hcnt < H_ACTIVE);

	/* Simplified Line Segment Detector (Simple-LSD) */
	wire lsd_flag, lsd_valid;
	wire [$clog2(V_FRAME)-1:0] lsd_start_v, lsd_end_v;
	wire [$clog2(H_FRAME)-1:0] lsd_start_h, lsd_end_h;
	wire [7:0] lsd_angle;
	simple_lsd #(
		.BIT_WIDTH    (DATA_WIDTH),
		.IMAGE_HEIGHT (V_ACTIVE  ),
		.IMAGE_WIDTH  (H_ACTIVE  ),
		.FRAME_HEIGHT (V_FRAME   ),
		.FRAME_WIDTH  (H_FRAME   ),
		.ANGLE_THRES  (),
		.GRAD_THRES   (),
		.LENGTH_THRES (),
		.START_VCNT   (),
		.RAM_SIZE     (RAM_SIZE  )
	)
	lsd_inst (
		.clock       (pixelclk        ),
		.n_rst       (!rst       ),
		.in_y        (cs_data    ),
		.in_vcnt     (cs_vcnt    ),
		.in_hcnt     (cs_hcnt    ),
		.out_flag    (lsd_flag   ),
		.out_valid   (lsd_valid  ),
		.out_start_v (lsd_start_v),
		.out_end_v   (lsd_end_v  ),
		.out_start_h (lsd_start_h),
		.out_end_h   (lsd_end_h  ),
		.out_angle   (lsd_angle  )
	);

	/* Buffering result of Simple-LSD */
	lsd_output_buffer_wp #(
		.BIT_WIDTH    (DATA_WIDTH),
		.IMAGE_HEIGHT (V_ACTIVE  ),
		.IMAGE_WIDTH  (H_ACTIVE  ),
		.FRAME_HEIGHT (V_FRAME   ),
		.FRAME_WIDTH  (H_FRAME   ),
		.RAM_SIZE     (RAM_SIZE  )
	)
	lsd_output_buffer_wp_inst (
		.wclock           (pixelclk                    ),
		.rclock           (psclk),
		.n_rst            (!rst                   ),
		.in_flag          (lsd_flag               ),
		.in_valid         (lsd_valid              ),
		.in_start_v       (lsd_start_v            ),
		.in_end_v         (lsd_end_v              ),
		.in_start_h       (lsd_start_h            ),
		.in_end_h         (lsd_end_h              ),
		.in_rd_addr       (in_lsdbuf_raddr        ),
		.in_write_protect (in_lsdbuf_write_protect),
		.out_ready        (out_lsdbuf_ready       ),
		.out_line_num     (out_lsdbuf_line_num    ),
		.out_start_v      (out_lsdbuf_start_v     ),
		.out_end_v        (out_lsdbuf_end_v       ),
		.out_start_h      (out_lsdbuf_start_h     ),
		.out_end_h        (out_lsdbuf_end_h       )
	);

	wire [DATA_WIDTH-1:0] lsd_r, lsd_g, lsd_b;
	wire [$clog2(V_FRAME)-1:0] lsd_vcnt;
	wire [$clog2(H_FRAME)-1:0] lsd_hcnt;
	wire lsd_vde, lsd_hblank, lsd_vblank, lsd_field;
	lsd_visualizer #(
		.BIT_WIDTH    (DATA_WIDTH),
		.IMAGE_HEIGHT (V_ACTIVE  ),
		.IMAGE_WIDTH  (H_ACTIVE  ),
		.FRAME_HEIGHT (V_FRAME   ),
		.FRAME_WIDTH  (H_FRAME   ),
		.RAM_SIZE     (RAM_SIZE  )
	)
	lsd_visualizer_inst (
		.pixel_clk  (pixelclk        ),
		.rst        (rst        ),
		.in_valid   (lsd_valid  ),
		.in_flag    (lsd_flag   ),
		.in_vcnt    (cs_vcnt    ),
		.in_hcnt    (cs_hcnt    ),
		.in_start_v (lsd_start_v),
		.in_start_h (lsd_start_h),
		.in_end_v   (lsd_end_v  ),
		.in_end_h   (lsd_end_h  ),
		.out_r      (lsd_r      ),
		.out_g      (lsd_g      ),
		.out_b      (lsd_b      ),
		.out_vcnt   (lsd_vcnt   ),
		.out_hcnt   (lsd_hcnt   )
	);
	assign lsd_hblank = (H_ACTIVE <= lsd_hcnt);
	assign lsd_vblank = (V_ACTIVE <= lsd_vcnt);
	assign lsd_vde    = (lsd_vcnt < V_ACTIVE) & (lsd_hcnt < H_ACTIVE);

	always_comb begin
		out_field <= 1'b0;
		case (sw)
			4'd0: begin
				out_data   <= in_data;
				out_vcnt   <= in_vcnt;
				out_hcnt   <= in_hcnt;
				out_vblank <= in_vblank;
				out_hblank <= in_hblank;
				out_vde    <= in_vde;
			end
			4'd1 : begin
				out_data   <= {3{gray_data}};
				out_vcnt   <= gray_vcnt;
				out_hcnt   <= gray_hcnt;
				out_vblank <= gray_vblank;
				out_hblank <= gray_hblank;
				out_vde    <= gray_vde;
			end
			4'd2 : begin
				out_data   <= {3{cs_data}};
				out_vcnt   <= cs_vcnt;
				out_hcnt   <= cs_hcnt;
				out_vblank <= cs_vblank;
				out_hblank <= cs_hblank;
				out_vde    <= cs_vde;
			end
			4'd3 : begin
				out_data   <= {lsd_r, lsd_g, lsd_b};
				out_vcnt   <= lsd_vcnt;
				out_hcnt   <= lsd_hcnt;
				out_vblank <= lsd_vblank;
				out_hblank <= lsd_hblank;
				out_vde    <= lsd_vde;
			end
		endcase
	end

endmodule

`default_nettype wire
