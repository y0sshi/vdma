//-----------------------------------------------------------------------------
// <line_draw>
//  - Draws line segments
//    - Line data is given as a pair of start and end points
//      ((start_v, start_h), (end_v, end_h)) with <in_en> == 1
//    - If <AUTO_ERASE> == 1, lines will be erased after displayed.
//      Therefore line data must be given constantly at every frame
//    - The given line data is stored into a queue and drawn one by one,
//      which takes some time. That is why line data should be given
//      at a moderate pace
//  - Can be used to visualize the line segments output from <simple_lsd>
//    - in_en = out_flag && out_valid
//    - Compatible with <simple_lsd> from version 1.06 to 1.10
//-----------------------------------------------------------------------------
// Version 1.01 (Aug. 4, 2020)
//  - Renamed from <visualizer>
//  - Combined <in_flag> and <in_valid> ports into <in_en> port
//  - Reduced drawing latency
//-----------------------------------------------------------------------------
// (C) 2019-2020 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns

module line_draw
  #( parameter int BIT_WIDTH    =    8, // input pixel bit width
     parameter int IMAGE_HEIGHT =   -1, // | image size
     parameter int IMAGE_WIDTH  =   -1, // | 
     parameter int FRAME_HEIGHT =   -1, //  | frame size (including sync.)
     parameter int FRAME_WIDTH  =   -1, //  |
     parameter int FIFO_SIZE    = 4096, // should be the power of 2
     parameter int AUTO_ERASE   =    1) // to erase lines at every frame
   ( clock, n_rst,
     in_en, in_start_v, in_start_h, in_end_v, in_end_h, 
     in_vcnt, in_hcnt, out_vcnt, out_hcnt, out_r, out_g, out_b );

   // local parameters --------------------------------------------------------
   localparam int FRAC_BITW   = 8;
   
   // following parameters are calculated automatically -----------------------
   localparam int H_BITW      = $clog2(FRAME_WIDTH);
   localparam int V_BITW      = $clog2(FRAME_HEIGHT);
   localparam int COORD_BITW  = (H_BITW > V_BITW) ? H_BITW : V_BITW;
   localparam int FIXED_BITW  = COORD_BITW + FRAC_BITW + 2;
   localparam int ADDR_BITW   = $clog2(IMAGE_HEIGHT * IMAGE_WIDTH);
   
   // inputs / outputs --------------------------------------------------------
   input wire 	                clock, n_rst, in_en;
   input wire [V_BITW-1:0] 	in_vcnt, in_start_v, in_end_v;
   input wire [H_BITW-1:0] 	in_hcnt, in_start_h, in_end_h;
   output wire [BIT_WIDTH-1:0] 	out_r, out_g, out_b;
   output reg [V_BITW-1:0] 	out_vcnt;
   output reg [H_BITW-1:0] 	out_hcnt;

   // state registers ---------------------------------------------------------
   reg [1:0] 			slp_state, drw_state;
   
   // preparation -------------------------------------------------------------
   // [stage 1]
   reg 				ps1_en;
   reg [V_BITW-1:0] 		ps1_dist_v, ps1_start_v, ps1_end_v;
   reg [H_BITW-1:0] 		ps1_dist_h, ps1_start_h, ps1_end_h;
   always_ff @(posedge clock) begin
      ps1_dist_v <= (in_start_v > in_end_v) ?
		    (in_start_v - in_end_v) : (in_end_v - in_start_v);
      ps1_dist_h <= (in_start_h > in_end_h) ?
		    (in_start_h - in_end_h) : (in_end_h - in_start_h);
      {ps1_en, ps1_start_v, ps1_start_h, ps1_end_v, ps1_end_h}
	<= {in_en, in_start_v, in_start_h, in_end_v, in_end_h};
   end
   // [stage 2]
   reg                          ps2_en;
   reg [(COORD_BITW*4+1)-1:0] 	ps2_wr_data;
   wire 			tmp_swap;
   wire [COORD_BITW-1:0] 	tmp_sx, tmp_sy, tmp_ex, tmp_ey;
   assign tmp_swap = (ps1_dist_v > ps1_dist_h);
   assign tmp_sx   = tmp_swap ? ps1_start_v : ps1_start_h;
   assign tmp_sy   = tmp_swap ? ps1_start_h : ps1_start_v;
   assign tmp_ex   = tmp_swap ? ps1_end_v   : ps1_end_h;
   assign tmp_ey   = tmp_swap ? ps1_end_h   : ps1_end_v;
   always_ff @(posedge clock) begin
      ps2_en <= ps1_en;
      if(tmp_ex < tmp_sx)
	ps2_wr_data <= {tmp_swap, tmp_ex, tmp_ey, tmp_sx, tmp_sy};
      else
	ps2_wr_data <= {tmp_swap, tmp_sx, tmp_sy, tmp_ex, tmp_ey};
   end

   // line segment queue ------------------------------------------------------
   wire 			lsq_swap;
   wire [COORD_BITW-1:0] 	lsq_lx, lsq_ly, lsq_rx, lsq_ry;
   wire [$clog2(FIFO_SIZE)-1:0] lsq_count;   // not used
   wire 			lsq_full, lsq_empty;
   fifo_sc
     #( .BIT_WIDTH(COORD_BITW * 4 + 1), .FIFO_SIZE(FIFO_SIZE) )
   lsq_0
     (  .clock(clock),         .n_rst(n_rst), 
	.wr_en(ps2_en),        .wr_data(ps2_wr_data),
	.rd_en((slp_state == 0) && (ps2_en || !lsq_empty)),
	.rd_data({lsq_swap, lsq_lx, lsq_ly, lsq_rx, lsq_ry}),
	.out_count(lsq_count), .out_full(lsq_full),   .out_empty(lsq_empty) );

   // slope calculation -------------------------------------------------------
   wire 			div_ready;
   wire signed [FIXED_BITW-1:0] div_slope;
   wire signed [FIXED_BITW-2:0] div_r;      // not used
   divider_iter_s
     #( .BIT_WIDTH(COORD_BITW + 1),   .OUT_FRAC_BITW(FRAC_BITW) )
   div_0
     (  .clock(clock), .n_rst(n_rst), .in_en(slp_state == 1),
	.in_a({1'b0, lsq_ry} - lsq_ly),       
	.in_b({1'b0, lsq_rx} - lsq_lx), 
	.out_ready(div_ready), .out_q(div_slope), .out_r(div_r) );
   
   reg [(COORD_BITW*3+1)-1:0] 	slp_wr_data;
   always_ff @(posedge clock) begin
      if(!n_rst) begin
	 slp_state <= 0;
      end
      // [0] waits for data being stored in the line segment queue
      else if(slp_state == 0) begin
	 if(ps2_en || !lsq_empty)
	   slp_state <= 1;
      end
      // [1] reads line segment data from the queue
      else if(slp_state == 1) begin
	 slp_wr_data <= {lsq_swap, lsq_lx, lsq_ly, lsq_rx};
	 slp_state   <= 2;
      end
      // [2] waits until the division ends
      else if(slp_state == 2) begin
	 if(div_ready)
	   slp_state <= 0;
      end
   end

   // slope queue -------------------------------------------------------------
   wire 			spq_swap;
   wire [COORD_BITW-1:0] 	spq_sx, spq_sy, spq_ex;
   wire signed [FRAC_BITW+1:0] 	spq_slope;   // [-1, 1]
   wire [$clog2(FIFO_SIZE)-1:0] spq_count;   // not used
   wire 			spq_full, spq_empty;
   wire 			spq_wr_en;
   assign spq_wr_en = (slp_state == 2) && div_ready;
   fifo_sc
     #( .BIT_WIDTH(COORD_BITW*3 + FRAC_BITW + 3), .FIFO_SIZE(FIFO_SIZE) )
   spq_0
     (  .clock(clock),         .n_rst(n_rst),         .wr_en(spq_wr_en),
	.wr_data({slp_wr_data, div_slope[0 +: (FRAC_BITW+2)]}),
	.rd_en((drw_state == 0) && (spq_wr_en || !spq_empty)),
	.rd_data({spq_swap, spq_sx, spq_sy, spq_ex, spq_slope}),
	.out_count(spq_count), .out_full(spq_full),   .out_empty(spq_empty) );
   
   // 1-bit frame buffer ------------------------------------------------------
   reg 				fb_wr_en;
   reg [ADDR_BITW-1:0] 		fb_wr_addr, fb_rd_addr;
   wire 			fb_rd_data;
   wire 			fb_valid;
   assign fb_valid = (in_vcnt < IMAGE_HEIGHT) && (in_hcnt < IMAGE_WIDTH);
   always_ff @(posedge clock) begin
      if((in_vcnt == FRAME_HEIGHT - 1) && (in_hcnt == FRAME_WIDTH - 1))
	fb_rd_addr <= 0;
      else if(fb_valid)
	fb_rd_addr <= fb_rd_addr + 1;
   end
   ram_sc
     #( .WORD_SIZE(1), .RAM_SIZE(IMAGE_HEIGHT * IMAGE_WIDTH), .FORWARD(0) )
   fb_ram_0
     (  .clock(clock),        
	.wr_en(fb_wr_en || (fb_valid && (AUTO_ERASE == 1))),
	.wr_data(fb_wr_en ? 1'b1 : 1'b0),
	.wr_addr(fb_wr_en ? fb_wr_addr : fb_rd_addr),
	.rd_addr(fb_rd_addr), .rd_data(fb_rd_data) );

   // line draw state machine -------------------------------------------------
   reg                          swap, drawing;
   reg [COORD_BITW-1:0]         current_x, end_x;
   reg signed [FIXED_BITW-1:0] 	current_y;
   reg signed [FRAC_BITW+1:0] 	slope;
   always_ff @(posedge clock) begin
      if(!n_rst) begin
	 drw_state <= 0;
	 drawing   <= 0;
      end
      // [0] waits for data being stored in the slope queue
      else if(drw_state == 0) begin
	 if(spq_wr_en || !spq_empty)
	   drw_state <= 1;
      end
      // [1] reads start position and slope from the queue
      else if(drw_state == 1) begin
	 {swap, current_x, end_x} <= {spq_swap, spq_sx, spq_ex};
	 current_y <= {spq_sy, 1'b1, {(FRAC_BITW - 1){1'b0}}};
	 slope     <= spq_slope;
	 drawing   <= 1;
	 drw_state <= 2;
      end
      // [2] draws until current_x reaches end_x
      else if(drw_state == 2) begin
	 current_x <= current_x + 1;
	 current_y <= current_y + slope;
	 if(current_x == end_x) begin
	    drawing   <= 0;
	    drw_state <= 0;
	 end
      end
   end

   // pipelined multiplier for address calculation ----------------------------
   // [stage 1] swap and bit trancation
   reg                          ml1_en;
   reg [COORD_BITW-1:0] 	ml1_v, ml1_h;
   always_ff @(posedge clock) begin
      if(swap) begin
	 ml1_v <= current_x;
	 ml1_h <= current_y >>> FRAC_BITW;
      end
      else begin
	 ml1_v <= current_y >>> FRAC_BITW;
	 ml1_h <= current_x;
      end
      ml1_en <= drawing;
   end
   // [stage 2] multiplication
   reg                          ml2_en;
   reg [ADDR_BITW-1:0] 		ml2_prod, ml2_h;
   always_ff @(posedge clock) begin
      ml2_prod <= ml1_v * IMAGE_WIDTH;
      {ml2_h, ml2_en} <= {ml1_h, ml1_en};
   end
   // [stage 3] buffer
   reg                          ml3_en;
   reg [ADDR_BITW-1:0]          ml3_prod, ml3_h;
   always_ff @(posedge clock)
     {ml3_prod, ml3_h, ml3_en} <= {ml2_prod, ml2_h, ml2_en};
   // [stage 4] finish
   always_ff @(posedge clock) begin
      fb_wr_en   <= ml3_en;
      fb_wr_addr <= ml3_prod + ml3_h;
   end

   // outputs -----------------------------------------------------------------
   always_ff @(posedge clock) begin
      {out_vcnt, out_hcnt} <= {in_vcnt, in_hcnt};
   end
   wire valid_pixel;
   assign valid_pixel 
     = fb_rd_data && (out_vcnt < IMAGE_HEIGHT) && (out_hcnt < IMAGE_WIDTH);
   assign out_r = valid_pixel ? -1 : 0;
   assign out_g = valid_pixel ? -1 : 0;
   assign out_b = valid_pixel ? -1 : 0;
   
endmodule
`default_nettype wire
