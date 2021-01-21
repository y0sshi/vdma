//-----------------------------------------------------------------------------
// <arctan_calc> 
//  - Pipelined arctangent calculation module
//    - behaves like numpy.arctan2(in_y, in_x)
//    - <in_y>, <in_x>: <IN_BITW>-bit signed coordinates
//    - <out_val>: <OUT_BITW>-bit angle (equivalent to [0, 2pi))
//  - The implementation is based on a table
//    - Too large <OUT_BITW> may result in synthesis failure
//    - Actual table size is less than (2 ** (OUT_BITW * 2 - 5))
//  - Input/output bit widths must satisfy the following inequalities:
//    - <IN_BITW> >= <OUT_BITW> - 2, <OUT_BITW> >= 4
//  - Latency: 5 clock cycles
//-----------------------------------------------------------------------------
// Version 1.03 (Sep. 11, 2020)
//  - Improved accuracy
//-----------------------------------------------------------------------------
// (C) 2019-2020 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns
  
module arctan_calc
  #( parameter int IN_BITW  = 9,    // input bit width  (>= OUT_BITW - 2)
     parameter int OUT_BITW = 8 )   // output bit width (>= 4)
  ( clock, in_y, in_x, out_val );

   // local parameters --------------------------------------------------------
   localparam int ADDR_BITW  = (OUT_BITW - 2) * 2 - 1;
   
   // inputs / outputs --------------------------------------------------------
   input wire       	           clock;
   input wire signed [IN_BITW-1:0] in_y, in_x;  // signed coordinates
   output reg [OUT_BITW-1:0] 	   out_val;     // output angle ([0, 2pi))

   // tables ------------------------------------------------------------------
   logic [(OUT_BITW-3)-1:0] 	   arctan_table [1 << ADDR_BITW];
   always_comb begin
      for(int i = 0; i < (1 << ADDR_BITW); i = i + 1)
	arctan_table[i] = 0;
      for(int x = 1; x < (1 << (OUT_BITW - 2)); x = x + 1) begin
	 for(int y = 1; y <= x; y = y + 1)
	   arctan_table[(x * (x - 1)) / 2 + y - 1] 
		     = clip(($atan2(y, x) / (3.1415926535897931 * 2))
			    * $pow(2.0, OUT_BITW));
      end
   end
   function real clip;
      input real val;
      real 	 max_val;
      begin
	 max_val = (1 << (OUT_BITW - 3)) - 1;
	 clip = (val <= max_val) ? val : max_val;
      end
   endfunction
   
   //--------------------------------------------------------------------------
   // [stage 1] bounds x and y (x >= 0, y >= 0, y <= x)
   // - based on the following relationships
   //   - atan((-y), x) = 0 - atan(y, x)
   //   - atan(y, (-x)) = pi - atan(y, x)
   //   - atan(x, y)    = pi/2 - atan(y, x)
   reg [IN_BITW-1:0]       s1_abs_y,  s1_abs_x;
   reg 			   s1_neg_y,  s1_neg_x,  s1_swap;
   wire [IN_BITW-1:0] 	   abs_y,     abs_x;
   wire 		   neg_y,     neg_x;
   assign neg_y = (in_y < 0);
   assign neg_x = (in_x < 0);
   assign abs_y = neg_y ? -in_y : in_y;
   assign abs_x = neg_x ? -in_x : in_x;
   always_ff @(posedge clock) begin
      {s1_neg_y, s1_neg_x} <= {neg_y, neg_x};
      if(abs_y <= abs_x)
	{s1_abs_y, s1_abs_x, s1_swap} <= {abs_y, abs_x, 1'b0};
      else
	{s1_abs_y, s1_abs_x, s1_swap} <= {abs_x, abs_y, 1'b1};
   end
   
   // [stage 2] bit truncation
   reg [(OUT_BITW-2)-1:0]  s2_abs_y,  s2_abs_x;
   reg 			   s2_neg_y,  s2_neg_x,  s2_swap;
   wire [(OUT_BITW-2):0]   trunc_y,   trunc_x;
   logic [$clog2(IN_BITW - OUT_BITW + 3)-1:0]    trunc_width;
   logic [(IN_BITW - OUT_BITW + 2)-1:0] 	 trunc_bias;
   always_comb begin
      trunc_width = 0;
      trunc_bias  = 0;
      for(int i = 1; i <= IN_BITW - OUT_BITW + 2; i = i + 1) begin
	 if(s1_abs_x[i + OUT_BITW - 3]) begin
	    trunc_width = i;
	    trunc_bias  = 1 << (i - 1);
	 end
      end
   end
   assign trunc_y = (s1_abs_y + trunc_bias) >> trunc_width;
   assign trunc_x = (s1_abs_x + trunc_bias) >> trunc_width;
   always_ff @(posedge clock) begin
      s2_abs_y <= (trunc_y >= (1 << (OUT_BITW - 2))) ? 
		  {(OUT_BITW-2){1'b1}} : trunc_y;
      s2_abs_x <= (trunc_x >= (1 << (OUT_BITW - 2))) ? 
		  {(OUT_BITW-2){1'b1}} : trunc_x;
      {s2_neg_y, s2_neg_x, s2_swap} <= {s1_neg_y, s1_neg_x, s1_swap};
   end

   // [stage 3] address calculation
   reg [ADDR_BITW-1:0] 	   s3_addr;
   reg 			   s3_neg_y,  s3_neg_x,  s3_swap;
   reg 			   s3_zero_y, s3_zero_x, s3_equal;
   always_ff @(posedge clock) begin
      s3_addr <= (s2_abs_x * (s2_abs_x - 1)) / 2 + s2_abs_y - 1;
      // if (y == 0 or x == 0 or x == y): don't care
      {s3_neg_y, s3_neg_x, s3_swap} <= {s2_neg_y, s2_neg_x, s2_swap};
      s3_zero_y <= (s2_abs_y == 0);      
      s3_zero_x <= (s2_abs_x == 0);
      s3_equal  <= (s2_abs_y == s2_abs_x);
   end
   
   // [stage 4] reads data from ROM
   reg [(OUT_BITW-3)-1:0]  s4_angle;
   reg 			   s4_neg_y,  s4_neg_x,  s4_swap;
   reg 			   s4_zero_y, s4_zero_x, s4_equal;
   always @(posedge clock) begin
      s4_angle <= arctan_table[s3_addr];
      {s4_neg_y, s4_neg_x, s4_swap, s4_zero_y, s4_zero_x, s4_equal}
	<= {s3_neg_y, s3_neg_x, s3_swap, s3_zero_y, s3_zero_x, s3_equal};
   end

   // [stage 5] generates a result
   wire [OUT_BITW-1:0]     res_1, res_2, res_3, res_4, res_5;
   assign res_1 = s4_equal  ? (1 << (OUT_BITW - 3)) : s4_angle;
   assign res_2 = s4_zero_y ? 0 : 
		  s4_zero_x ? (1 << (OUT_BITW - 2)) : res_1;
   assign res_3 = s4_swap   ? (1 << (OUT_BITW - 2)) - res_2 : res_2;
   assign res_4 = s4_neg_x  ? (1 << (OUT_BITW - 1)) - res_3 : res_3;
   assign res_5 = s4_neg_y  ? -res_4 : res_4;
   always @(posedge clock)
     out_val <= res_5;
   
endmodule
`default_nettype wire

