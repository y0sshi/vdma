//-----------------------------------------------------------------------------
// <batch_norm>
//  - Normalizes the given value based on the pre-computed
//    population mean <AVG_MEANS>, variance <AVG_VARS>,
//    scaling parameter <GAMMAS>, and shifting parameter <BETAS>
//    - x' = (in_val - AVG_MEAN) / sqrt(AVG_VAR + EPSILON)
//    - out_val = x' * GAMMA + BETA
//  - Since these parameters are all constant values,
//    what this module performs is just the simple linear transformation
//  - Latency: 3 clock cycles
//-----------------------------------------------------------------------------
// Version 1.00 (Jul. 22, 2020)
//  - Initial version
//-----------------------------------------------------------------------------
// (C) 2020 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns

module batch_norm
  #( parameter int  BIT_WIDTH = -1,     // bit width
     parameter int  FRAC_BITW = -1,     // fractional bit width
     parameter real AVG_MEAN  =  0.0,   // mean
     parameter real AVG_VAR   =  1.0,   // variance
     parameter real GAMMA     =  1.0,   // scaling param.
     parameter real BETA      =  0.0 )  // shifting param.
   ( clock, in_val, out_val );

   // local parameters --------------------------------------------------------
   localparam int  MID_BITW = BIT_WIDTH + FRAC_BITW;
   localparam real EPSILON  = 2.0 * $pow(10.0, -5);
   
   // input / outputs ---------------------------------------------------------
   input wire 	                     clock;
   input wire signed [BIT_WIDTH-1:0] in_val;   // input value
   output reg signed [BIT_WIDTH-1:0] out_val;  // output value

   //--------------------------------------------------------------------------
   localparam real AVG_STD = $sqrt(AVG_VAR + EPSILON);
   localparam real SCALE   = GAMMA / AVG_STD;
   localparam signed [MID_BITW-1:0]  MULTIPLIER 
     = SCALE * $pow(2.0, FRAC_BITW);
   localparam signed [BIT_WIDTH-1:0] BIAS 
     = (BETA - AVG_MEAN * SCALE) * $pow(2.0, FRAC_BITW);

   // multiplication
   reg signed [MID_BITW-1:0] prod, prod_buf;
   always_ff @(posedge clock) begin
      prod_buf <= in_val * MULTIPLIER;
      prod     <= prod_buf;
   end

   // bit trancation and bias addition
   generate
      if(FRAC_BITW >= 1) begin
	 always_ff @(posedge clock)
	   out_val <= (((prod >>> (FRAC_BITW-1)) + 1) >>> 1) + BIAS;
      end
      else begin
	 always_ff @(posedge clock)
	   out_val <= prod;
      end
   endgenerate

      
endmodule
`default_nettype wire
