//-----------------------------------------------------------------------------
// <coord_adjuster>
//  - Adjusts coordinates based on the given latency
//  - <LATENCY> must be >= 1
//-----------------------------------------------------------------------------
// Version 1.02 (Dec. 18, 2019)
//  - Code refinement
//-----------------------------------------------------------------------------
// (C) 2018-2019 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns

module coord_adjuster
  #( parameter int FRAME_HEIGHT = -1,  // | frame size (including sync.)
     parameter int FRAME_WIDTH  = -1,  // |
     parameter int LATENCY      = -1 )
   ( clock, in_vcnt, in_hcnt, out_vcnt, out_hcnt );

   // local parameters --------------------------------------------------------
   localparam int V_BITW        = $clog2(FRAME_HEIGHT);
   localparam int H_BITW        = $clog2(FRAME_WIDTH);
   localparam int EQUIV_LATENCY = 
		  (LATENCY - 1) % (FRAME_HEIGHT * FRAME_WIDTH);
   localparam int V_LATENCY     = EQUIV_LATENCY / FRAME_WIDTH;
   localparam int H_LATENCY     = EQUIV_LATENCY % FRAME_WIDTH;

   // inputs / outputs --------------------------------------------------------
   input wire              clock;
   input wire [V_BITW-1:0] in_vcnt;
   input wire [H_BITW-1:0] in_hcnt;
   output reg [V_BITW-1:0] out_vcnt;
   output reg [H_BITW-1:0] out_hcnt;

   // vcount adjustment -------------------------------------------------------
   wire [V_BITW-1:0] 	   v_diff;
   assign v_diff = V_LATENCY + (in_hcnt < H_LATENCY);
   always_ff @(posedge clock) begin
      if(in_vcnt < v_diff)
	out_vcnt <= ({1'b0, in_vcnt} + FRAME_HEIGHT) - v_diff;
      else
	out_vcnt <= in_vcnt - v_diff;
   end

   // hcount adjustment -------------------------------------------------------
   always_ff @(posedge clock) begin
      if(in_hcnt < H_LATENCY)
	out_hcnt <= ({1'b0, in_hcnt} + FRAME_WIDTH) - H_LATENCY;
      else
	out_hcnt <= in_hcnt - H_LATENCY;
   end
   
endmodule
`default_nettype wire
