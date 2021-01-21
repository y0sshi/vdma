//-----------------------------------------------------------------------------
// <slsd_mem_overlay>
//  - Overlays memory usage of <simple_lsd> module
//-----------------------------------------------------------------------------
// Version 1.00 (Sep. 15, 2020)
//  - Initial version
//-----------------------------------------------------------------------------
// (C) 2019-2020 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns

module slsd_mem_overlay
  #( parameter int BIT_WIDTH    =    8, // input pixel bit width
     parameter int IMAGE_HEIGHT =   -1, // | image size
     parameter int IMAGE_WIDTH  =   -1, // | 
     parameter int FRAME_HEIGHT =   -1, //  | frame size (including sync.)
     parameter int FRAME_WIDTH  =   -1, //  |
     parameter int RAM_SIZE     = 4096)
   ( clock, n_rst,
     in_flag, in_valid, in_vcnt, in_hcnt, in_r, in_g, in_b, 
     out_vcnt, out_hcnt, out_r, out_g, out_b );

   // following parameters are calculated automatically -----------------------
   localparam int H_BITW      = $clog2(FRAME_WIDTH);
   localparam int V_BITW      = $clog2(FRAME_HEIGHT);
   localparam int COUNT_BITW  = $clog2(RAM_SIZE);
   localparam int SCALE       = (RAM_SIZE <= IMAGE_WIDTH) ? 0 :
		  $clog2((RAM_SIZE - 1) / IMAGE_WIDTH + 1);

   // inputs / outputs --------------------------------------------------------
   input wire 	                clock, n_rst, in_flag, in_valid;
   input wire [V_BITW-1:0] 	in_vcnt;
   input wire [H_BITW-1:0] 	in_hcnt;
   input wire [BIT_WIDTH-1:0] 	in_r,  in_g,  in_b;
   output reg [V_BITW-1:0] 	out_vcnt;
   output reg [H_BITW-1:0] 	out_hcnt;
   output reg [BIT_WIDTH-1:0] 	out_r, out_g, out_b;

   // count -------------------------------------------------------------------
   reg 				counting;
   reg [COUNT_BITW-1:0] 	total_count, valid_count;
   always_ff @(posedge clock) begin
      if(!n_rst) begin
	 counting <= 0;
      end
      else if(!counting) begin
	 if(in_flag) begin
	    counting <= 1;
	    total_count <= 1;
	    valid_count <= in_valid;
	 end
      end
      else begin
	 if(!in_flag) begin
	    counting <= 0;
	 end
	 else begin
	    total_count <= total_count + 1;
	    valid_count <= valid_count + in_valid;
	 end
      end
   end
   
   // draw --------------------------------------------------------------------
   localparam int TOP_POS    = 20;
   localparam int BAR_WIDTH  = (RAM_SIZE >> SCALE);
   localparam int BAR_HEIGHT = 20;
   localparam int LEFT_POS   = (IMAGE_WIDTH - BAR_WIDTH) / 2;
   localparam int DRANGE     = 1 << BIT_WIDTH;
   
   wire signed [V_BITW:0] rel_v  = {1'b0, in_vcnt} - TOP_POS;
   wire signed [H_BITW:0] rel_h  = {1'b0, in_hcnt} - LEFT_POS;
   always_ff @(posedge clock) begin
      // inside the bar
      if((1 <= rel_v) && (rel_v < (BAR_HEIGHT - 1)) &&
	 (1 <= rel_h) && (rel_h < (BAR_WIDTH  - 1)) ) begin
	 if(rel_h == ((RAM_SIZE * 9 / 10) >> SCALE)) begin
	    out_r <= DRANGE - 1;
	    out_g <= DRANGE - 1;
	    out_b <= DRANGE - 1;
	 end
	 else if(rel_h <= (valid_count >> SCALE)) begin
	    out_r <= DRANGE / 2 + DRANGE / 4 + (in_r >> 2);
	    out_g <= in_g >> 2;
	    out_b <= in_b >> 2;
	 end
	 else if(rel_h <= (total_count >> SCALE)) begin
	    out_r <= in_r >> 2;
	    out_g <= DRANGE / 2 + DRANGE / 4 + (in_g >> 2);
	    out_b <= in_b >> 2;
	 end
	 else begin
	    out_r <= in_r >> 2;
	    out_g <= in_g >> 2;
	    out_b <= in_b >> 2;
	 end
      end
      // edge
      else if(((rel_v == 0 || rel_v == (BAR_HEIGHT - 1)) && 
	       (0  < rel_h && rel_h <  (BAR_WIDTH  - 1))) ||
	      ((rel_h == 0 || rel_h == (BAR_WIDTH  - 1)) && 
	       (0  < rel_v && rel_v <  (BAR_HEIGHT - 1))) ) begin
	 out_r <= DRANGE - 1;
	 out_g <= DRANGE - 1;
	 out_b <= DRANGE - 1;
      end
      // outside
      else begin
	 {out_r, out_g, out_b} <= {in_r, in_g, in_b};
      end
      {out_vcnt, out_hcnt} <= {in_vcnt, in_hcnt};
   end
   
endmodule
`default_nettype wire
