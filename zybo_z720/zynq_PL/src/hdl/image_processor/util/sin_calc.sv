//-----------------------------------------------------------------------------
// <sin_calc>
//  - Pipelined sine calculation module
//    - <out_val> = sin((in_phase / (2 ^ IN_BITW)) * 2.0 * pi)
//    - To calculate cosine, add (2 ^ (IN_BITW - 2)) to <in_phase>
//  - The implementation is based on a table
//    - Too large <IN_BITW> may result in synthesis failure
//    - Actual table size is (2 ^ (IN_BITW - 2))
//  - Latency: 3 clock cycles
//-----------------------------------------------------------------------------
// Version 1.05 (Aug. 18, 2020)
//  - Improved the table generation method
//-----------------------------------------------------------------------------
// (C) 2018-2020 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns

module sin_calc
  #( parameter int IN_BITW  = 12,  // input phase bit width (>= 3)
     parameter int OUT_BITW = 12 ) // | output bit width (>= 3)
   //                              // | (includes 2 integer bits)
   ( clock, in_phase, out_val );

   // local parameters --------------------------------------------------------
   localparam int ADDR_BITW     = IN_BITW  - 2;
   localparam int FRAC_BITW     = OUT_BITW - 2;
   localparam int QUARTER_STEPS = 1 << ADDR_BITW;
   
   // inputs / outputs --------------------------------------------------------
   input wire                       clock;
   input wire [IN_BITW-1:0] 	    in_phase;  // [0, 2pi)
   output reg signed [OUT_BITW-1:0] out_val;   // [-1.0, 1.0]

   // tables ------------------------------------------------------------------
   logic signed [OUT_BITW-1:0] 	    sine_table [QUARTER_STEPS];
   always_comb begin
      for(int i = 0; i < QUARTER_STEPS; i = i + 1)
	sine_table[i] = $sin(i * 3.1415926535897931 / (QUARTER_STEPS * 2.0))
	  * $pow(2.0, FRAC_BITW);
   end
   
   // [stage 1] calculates an address for the wave table ----------------------
   reg [ADDR_BITW-1:0] 		    addr;
   reg 				    s1_half, s1_neg;
   always_ff @(posedge clock) begin
      if(in_phase < QUARTER_STEPS)
	addr <= in_phase;
      else if(in_phase < QUARTER_STEPS * 2)
	addr <= QUARTER_STEPS * 2 - in_phase;
      else if(in_phase < QUARTER_STEPS * 3)
	addr <= in_phase - QUARTER_STEPS * 2;
      else
	addr <= QUARTER_STEPS * 4 - in_phase;
   end
   always_ff @(posedge clock) begin
      s1_half <= (in_phase == QUARTER_STEPS) || (in_phase == QUARTER_STEPS *3);
      s1_neg  <= (QUARTER_STEPS * 2 < in_phase);
   end
   
   // [stage 2] reads from wave table -----------------------------------------
   reg signed [OUT_BITW-1:0] 	    s2_val;
   reg 				    s2_half, s2_neg;
   always_ff @(posedge clock) begin
      s2_val <= sine_table[addr];
      {s2_half, s2_neg} <= {s1_half, s1_neg};
   end

   // [stage 3] generates a result --------------------------------------------
   wire signed [OUT_BITW-1:0]       value;
   assign value = (s2_half) ? {1'b1, {FRAC_BITW{1'b0}}} : s2_val;
   always_ff @(posedge clock)
     out_val <= (s2_neg) ? value * (-1) : value;
   
endmodule
`default_nettype wire
