//-----------------------------------------------------------------------------
// <stream_patch> 
//  - Extracts a patch from an input image for stream processing
//    - <PATCH_WIDTH> must be less than <WIDTH>
//-----------------------------------------------------------------------------
// Version 1.14 (Feb. 20, 2020)
//  - Improved <out_patch> port by using multi-dimensional packed array
//-----------------------------------------------------------------------------
// (C) 2018-2020 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns

module stream_patch
  #( parameter int BIT_WIDTH    = -1, // image bit width
     parameter int IMAGE_HEIGHT = -1, // | image size
     parameter int IMAGE_WIDTH  = -1, // |
     parameter int FRAME_HEIGHT = -1, //   | frame size (including sync.)
     parameter int FRAME_WIDTH  = -1, //   |
     parameter int PATCH_HEIGHT = -1, // | patch size
     parameter int PATCH_WIDTH  = -1, // |
     parameter int CENTER_V     = PATCH_HEIGHT / 2, // | center position
     parameter int CENTER_H     = PATCH_WIDTH  / 2, // |
     parameter int PADDING      = 1 ) // to apply padding or not
   ( clock,     n_rst,
     in_pixel,  in_vcnt,  in_hcnt,
     out_patch, out_vcnt, out_hcnt );

   // local parameters --------------------------------------------------------
   localparam int V_BITW = $clog2(FRAME_HEIGHT);
   localparam int H_BITW = $clog2(FRAME_WIDTH);

   // inputs ------------------------------------------------------------------
   input wire 	               clock, n_rst;
   input wire [BIT_WIDTH-1:0]  in_pixel;
   input wire [V_BITW-1:0]     in_vcnt;
   input wire [H_BITW-1:0]     in_hcnt;
   
   // outputs -----------------------------------------------------------------
   output wire [0:PATCH_HEIGHT-1][0:PATCH_WIDTH-1][BIT_WIDTH-1:0] out_patch;
   // example where the patch size is (3, 3) and the bit width is 8:
   //
   //   \ h  0 1 2 
   //   v\  _______    ________a________ ____b____ ____c____ ____d____
   //   0  | a b c |  |_7_6_5_4_3_2_1_0_|_7_..._0_|_7_..._0_|_7_..._0_|...
   //   1  | d e f |    0 1    ...    7   8 ... 15 16 ... 23 24 ... 31 ...
   //   2  |_g_h_i_|
   //
   // i.e. out_patch = {a[7:0], b[7:0], c[7:0], d[7:0], ..., i[7:0]}
   output wire [V_BITW-1:0]     out_vcnt;
   output wire [H_BITW-1:0] 	out_hcnt;
   // if the center position is (2, 1) in the example above,
   // these output coordinates correspond to the pixel <h>

   // patch extraction --------------------------------------------------------
   reg [0:PATCH_HEIGHT-1][0:PATCH_WIDTH-1][BIT_WIDTH-1:0] patch;
   generate
      // <delay> modules (FIFO)
      for(genvar v = 1; v < PATCH_HEIGHT; v = v + 1) begin: stp_delay_v
	 wire [BIT_WIDTH-1:0] delay_out;
	 delay
	   #( .BIT_WIDTH(BIT_WIDTH), .LATENCY(FRAME_WIDTH - PATCH_WIDTH) )
	 dly_0
	   (  .clock(clock),         .n_rst(n_rst),
	      .in_data(patch[v][0]), .out_data(delay_out) );
      end
      // patch (shift registers)
      for(genvar v = 0; v < PATCH_HEIGHT; v = v + 1) begin: stp_patch_v
	 for(genvar h = 0; h < PATCH_WIDTH - 1; h = h + 1) begin: stp_patch_h
	    always_ff @(posedge clock)
	      patch[v][h] <= patch[v][h+1];
	 end
	 if(v == PATCH_HEIGHT - 1) begin
	    always_ff @(posedge clock)
	      patch[v][PATCH_WIDTH-1] <= in_pixel;
	 end
	 else begin
	    always_ff @(posedge clock)
	      patch[v][PATCH_WIDTH-1] <= stp_delay_v[v+1].delay_out;
	 end
      end     
   endgenerate

   // coordinates adjustment based on the given center position ---------------
   wire [V_BITW-1:0]     ctr_vcnt;
   wire [H_BITW-1:0] 	 ctr_hcnt;
   coord_adjuster
     #( .FRAME_HEIGHT(FRAME_HEIGHT), .FRAME_WIDTH(FRAME_WIDTH), 
	.LATENCY( (PATCH_HEIGHT - 1 - CENTER_V) * FRAME_WIDTH +
		  (PATCH_WIDTH  - 1 - CENTER_H) + 1 )           )
   ca_0
     (  .clock(clock), .in_vcnt(in_vcnt), .in_hcnt(in_hcnt),
	.out_vcnt(ctr_vcnt), .out_hcnt(ctr_hcnt)  );

   // padding and output ------------------------------------------------------
   generate
      if(PADDING == 0) begin
	 assign out_patch = patch;
	 assign {out_vcnt, out_hcnt} = {ctr_vcnt, ctr_hcnt};
      end
      else begin
	 // applies padding
	 reg [0:PATCH_HEIGHT-1][0:PATCH_WIDTH-1][BIT_WIDTH-1:0] out_patch_buf;
	 for(genvar v = 0; v < PATCH_HEIGHT; v = v + 1) begin: stp_pad_v
	    for(genvar h = 0; h < PATCH_WIDTH; h = h + 1) begin: stp_pad_h
	       wire [$clog2(PATCH_HEIGHT)-1:0] tgt_v;
	       wire [$clog2(PATCH_WIDTH)-1:0]  tgt_h;
	       assign tgt_v = (v + ctr_vcnt < CENTER_V) ? CENTER_V - ctr_vcnt :
			      (IMAGE_HEIGHT + CENTER_V <= v + ctr_vcnt) ?
			      (CENTER_V + IMAGE_HEIGHT - 1) - ctr_vcnt : v;
	       assign tgt_h = (h + ctr_hcnt < CENTER_H) ? CENTER_H - ctr_hcnt :
			      (IMAGE_WIDTH  + CENTER_H <= h + ctr_hcnt) ?
			      (CENTER_H + IMAGE_WIDTH  - 1) - ctr_hcnt : h;
	       always_ff @(posedge clock)
		 out_patch_buf[v][h]
		   <= ((ctr_vcnt < IMAGE_HEIGHT) && (ctr_hcnt < IMAGE_WIDTH)) ?
		      patch[tgt_v][tgt_h] : 0;
	    end
	 end
	 // buffering and assignment
	 reg [V_BITW-1:0] out_vcnt_buf;
	 reg [H_BITW-1:0] out_hcnt_buf;
	 always_ff @(posedge clock)
	   {out_vcnt_buf, out_hcnt_buf} <= {ctr_vcnt, ctr_hcnt};
	 assign out_patch = out_patch_buf;
	 assign {out_vcnt, out_hcnt} = {out_vcnt_buf, out_hcnt_buf};
      end
   endgenerate
   
endmodule
`default_nettype wire
