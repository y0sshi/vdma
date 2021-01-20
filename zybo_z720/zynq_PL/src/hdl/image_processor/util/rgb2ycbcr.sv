//-----------------------------------------------------------------------------
// <rgb2ycbcr> 
//  - Pipelined converter from RGB to full-scale YCbCr (BT.709)
//    - Latency: 4 clock cycles
//-----------------------------------------------------------------------------
// Version 1.05 (Aug. 21, 2020)
//  - Fixed the bug where <cb> and <cr> are not calculated properly
//    because of the incorrect bias value and overflow
//  - Other minor refinements
//-----------------------------------------------------------------------------
// (C) 2018-2020 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns
  
module rgb2ycbcr
  #( parameter int BIT_WIDTH = -1 )  // I/O bit width
   ( clock, in_r, in_g, in_b, out_y, out_cb, out_cr );

   // local parameters --------------------------------------------------------
   localparam int FRAC_BITW  = BIT_WIDTH + 3;
   localparam int FIXED_BITW = BIT_WIDTH + FRAC_BITW + 1;
   
   // inputs/outputs ----------------------------------------------------------
   input wire       	       clock;
   input wire [BIT_WIDTH-1:0]  in_r,   in_g,   in_b;
   output reg [BIT_WIDTH-1:0]  out_y,  out_cb, out_cr;

   //--------------------------------------------------------------------------
   // [stage 1] multiplication
   reg signed [FIXED_BITW-1:0] s1_y1,  s1_y2,  s1_y3;
   reg signed [FIXED_BITW-1:0] s1_cb1, s1_cb2, s1_cb3;
   reg signed [FIXED_BITW-1:0] s1_cr1, s1_cr2, s1_cr3;
   always_ff @(posedge clock) begin
      s1_y1  <= fixed_mult(in_r,  0.2126  );
      s1_y2  <= fixed_mult(in_g,  0.7152  );
      s1_y3  <= fixed_mult(in_b,  0.0722  );
      s1_cb1 <= fixed_mult(in_r, -0.114572);
      s1_cb2 <= fixed_mult(in_g, -0.385428);
      s1_cb3 <= {({2'd0, in_b} + {BIT_WIDTH{1'b1}}), {(FRAC_BITW-1){1'b0}}};
      s1_cr1 <= {({2'd0, in_r} + {BIT_WIDTH{1'b1}}), {(FRAC_BITW-1){1'b0}}};
      s1_cr2 <= fixed_mult(in_g, -0.454153);
      s1_cr3 <= fixed_mult(in_b, -0.045847);
   end
   
   // [stage 2] buffer
   reg signed [FIXED_BITW-1:0] s2_y1,  s2_y2,  s2_y3;
   reg signed [FIXED_BITW-1:0] s2_cb1, s2_cb2, s2_cb3;
   reg signed [FIXED_BITW-1:0] s2_cr1, s2_cr2, s2_cr3;
   always_ff @(posedge clock) begin
      {s2_y1,  s2_y2,  s2_y3 } <= {s1_y1,  s1_y2,  s1_y3 };
      {s2_cb1, s2_cb2, s2_cb3} <= {s1_cb1, s1_cb2, s1_cb3};
      {s2_cr1, s2_cr2, s2_cr3} <= {s1_cr1, s1_cr2, s1_cr3};
   end

   // [stage 3] addition
   reg signed [FIXED_BITW-1:0] s3_y, s3_cb, s3_cr;
   always_ff @(posedge clock) begin
      s3_y  <= s2_y1  + s2_y2  + s2_y3 ;
      s3_cb <= s2_cb1 + s2_cb2 + s2_cb3;
      s3_cr <= s2_cr1 + s2_cr2 + s2_cr3;
   end

   // [stage 4] rounding
   always_ff @(posedge clock) begin
      out_y  <= ((s3_y  >>> (FRAC_BITW - 1)) + 1) >>> 1;
      out_cb <= ((s3_cb >>> (FRAC_BITW - 1)) + 1) >>> 1;
      out_cr <= ((s3_cr >>> (FRAC_BITW - 1)) + 1) >>> 1;
   end

   // functions ---------------------------------------------------------------
   function [FIXED_BITW-1:0] fixed_mult;
      input [BIT_WIDTH-1:0] val;
      input real 	    weight;  // constant
      reg [FIXED_BITW-1:0]  f_wgt;   // not a register
      begin
	 f_wgt   = weight * $pow(2.0, FRAC_BITW);
	 fixed_mult = val * f_wgt;
      end
   endfunction
   
endmodule
`default_nettype wire

