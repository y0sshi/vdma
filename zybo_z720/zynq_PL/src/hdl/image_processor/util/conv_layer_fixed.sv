//-----------------------------------------------------------------------------
// <conv_layer_fixed>
//  - Pipelined 2D convolution layer using fixed-point arithmetic
//    - Convolution and bias addition
//    - Batch normalization and Leaky ReLU (if necessary)
//    - Residual Connection (if necessary)
//  - <in_vals> and <out_vals> are represented in fixed-point format
//    with the bit widths specified by the parameters
//  - <WEIGHTS> is a 1D array of real, 
//    which can be obtained by raveling the 4D weight array of
//    a shape (out_channel, in_channel, filter_height, filter_width)
//  - <BIASES> is a 1D array of real,
//    which contains bias values for all the output channels
//  - <WEIGHTS> and <BIASES> are automatically converted into
//    fixed-point format with the following fractional bits:
//    - <WEIGHTS>: WGT_FRAC_BITW
//    - <BIASES> : IN_FRAC_BITW + WGT_FRAC_BITW
//  - Activation function is Leaky ReLU 
//    f(x) = max(x, (x * LRELU_SLOPE) / 16))   (0 <= LRELU_SLOPE < 16)
//    - It is recommended to set LRELU_SLOPE to the power of 2
//    - If LRELU_SLOPE == 0, this is the same as common ReLU
//    - If LRELU_SLOPE  < 0, no activation is applied
//  - If <BATCH_NORM> == 1, batch normalization is applied based on
//    the given population means <AVG_MEANS>, variances <AVG_VARS>,
//    scaling parameters <GAMMAS>, and shifting parameters <BETAS>,
//    each of which is a 1D array of real containing <OUT_CHS> elements
//  - If <RESIDUAL> == 1, each of input values is buffered and added to 
//    the corresponding result (residual block)
//  - Given that expected value distribution before activation is [a, b],
//    the following inequalities must be satisfied:
//    - a >= -2 ^ (OUT_BITW - OUT_FRAC_BITW - 1)
//    - b <=  2 ^ (OUT_BITW - OUT_FRAC_BITW - 1) - 1
//-----------------------------------------------------------------------------
// Version 1.02 (Jul. 30, 2020)
//  - Reduced resource utilization and latency 
//    by using ternary adder trees instead of binary adder trees
//-----------------------------------------------------------------------------
// (C) 2017-2020 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns

module conv_layer_fixed
  #( parameter int IMAGE_HEIGHT  = -1,  // | image size
     parameter int IMAGE_WIDTH   = -1,  // |
     parameter int FRAME_HEIGHT  = -1,  //  | frame size (including sync.)
     parameter int FRAME_WIDTH   = -1,  //  |
     parameter int IN_BITW       = -1,  // input bit width  (> IN_FRAC_BITW)
     parameter int OUT_BITW      = -1,  // output bit width (> OUT_FRAC_BITW)
     parameter int IN_FRAC_BITW  =  0,  // input fractional bit width
     parameter int WGT_FRAC_BITW =  0,  // weight fractional bit width
     parameter int OUT_FRAC_BITW =  0,  // output fractional bit width
     //                                 // (<= IN_FRAC_BITW + WGT_FRAC_BITW)
     parameter int IN_CHS        =  1,  // # of input channels
     parameter int OUT_CHS       =  1,  // # of output channels
     parameter int FLT_SIZE      =  1,  // filter size
     parameter int LRELU_SLOPE   = -1,  // slope (*16) for Leaky ReLU (<= 16)
     //                                 // 0: ReLU, -1: disables activation
     parameter int BATCH_NORM    =  0,  // to use batch normalization or not
     parameter int RESIDUAL      =  0,  // to use residual connection or not
     parameter real AVG_MEANS[OUT_CHS] = '{default: 0.0}, //  |
     parameter real AVG_VARS [OUT_CHS] = '{default: 1.0}, //  | batch norm.
     parameter real GAMMAS   [OUT_CHS] = '{default: 1.0}, //  | parameters
     parameter real BETAS    [OUT_CHS] = '{default: 0.0}, //  |
     parameter real WEIGHTS  [OUT_CHS*IN_CHS*FLT_SIZE*FLT_SIZE] = '{0.0},
     parameter real BIASES   [OUT_CHS]                          = '{0.0} )
   ( clock,    n_rst, 
     in_vals,  in_vcnt,  in_hcnt,
     out_vals, out_vcnt, out_hcnt );

   // local parameters --------------------------------------------------------
   localparam int V_BITW     = $clog2(FRAME_HEIGHT);
   localparam int H_BITW     = $clog2(FRAME_WIDTH);
   localparam int RES_SHIFT  = IN_FRAC_BITW + WGT_FRAC_BITW - OUT_FRAC_BITW;
   localparam int SKIP_SHIFT = OUT_FRAC_BITW - IN_FRAC_BITW;
   localparam int MID_BITW   = OUT_BITW + RES_SHIFT;
   localparam int FLT_PIXS   = FLT_SIZE * FLT_SIZE;
   localparam int LATENCY    = $ceil($ln(IN_CHS * FLT_PIXS) / $ln(3)) + 3 +
		  ((RESIDUAL == 0) ? 0 : 1) + ((BATCH_NORM == 0) ? 0 : 3) +
		  ((LRELU_SLOPE < 0) ? 0 : 1);
   
   // inputs / outputs --------------------------------------------------------
   input wire  	                           clock, n_rst;
   input wire [0:IN_CHS-1][IN_BITW-1:0]    in_vals;   // signed
   input wire [V_BITW-1:0] 		   in_vcnt;
   input wire [H_BITW-1:0] 		   in_hcnt;
   output wire [0:OUT_CHS-1][OUT_BITW-1:0] out_vals;  // signed
   output wire [V_BITW-1:0] 		   out_vcnt;
   output wire [H_BITW-1:0] 		   out_hcnt;
   
   // -------------------------------------------------------------------------
   generate
      // patch extraction for each input pixel
      for(genvar ic = 0; ic < IN_CHS; ic = ic + 1) begin: cvf_patch_ic
	 // patch extraction
	 wire [0:FLT_PIXS-1][IN_BITW-1:0] stp_patch;
	 wire [V_BITW-1:0] 		  stp_vcnt;
	 wire [H_BITW-1:0] 		  stp_hcnt;
	 stream_patch
	   #( .BIT_WIDTH(IN_BITW),         .PADDING(1),
	      .IMAGE_HEIGHT(IMAGE_HEIGHT), .IMAGE_WIDTH(IMAGE_WIDTH),
	      .FRAME_HEIGHT(FRAME_HEIGHT), .FRAME_WIDTH(FRAME_WIDTH), 
	      .PATCH_HEIGHT(FLT_SIZE),     .PATCH_WIDTH(FLT_SIZE),
	      .CENTER_V(FLT_SIZE / 2),     .CENTER_H(FLT_SIZE / 2)    )
	 stp_0
	   (  .clock(clock),               .n_rst(n_rst),
	      .in_pixel(in_vals[ic]),      .out_patch(stp_patch), 
	      .in_vcnt(in_vcnt),           .in_hcnt(in_hcnt),
	      .out_vcnt(stp_vcnt),         .out_hcnt(stp_hcnt)        );
      end

      // convolution
      for(genvar oc = 0; oc < OUT_CHS; oc = oc + 1) begin: cvf_conv_oc
	 // multiplication
	 reg [0:IN_CHS*FLT_PIXS-1][MID_BITW-1:0] prods;
	 for(genvar ic = 0; ic < IN_CHS; ic = ic + 1) begin: cvf_conv_ic
	    for(genvar p = 0; p < FLT_PIXS; p = p + 1) begin: cvf_conv_p
	       reg signed [MID_BITW-1:0] prod_buf;
	       localparam signed [MID_BITW-1:0] SCALE 
		 = WEIGHTS[(oc*IN_CHS+ic)*FLT_PIXS+p] 
		   * $pow(2.0, WGT_FRAC_BITW);
	       always_ff @(posedge clock) begin
		  prod_buf <= $signed(cvf_patch_ic[ic].stp_patch[p]) * SCALE;
		  prods[ic*FLT_PIXS+p] <= prod_buf;
	       end
	    end
	 end

	 // tree adder
	 wire signed [MID_BITW-1:0] sum;
	 tree_adder
	   #( .IN_NUM(IN_CHS * FLT_PIXS), .IN_BITW(MID_BITW), 
	      .BIT_EXTEND(0),             .TERNARY(1) )
	 tadd_0
	   (  .clock(clock), .in_vals(prods), .out_sum(sum) );

	 // bias addition and rounding
	 reg signed [OUT_BITW-1:0]  biased;
	 localparam signed [MID_BITW-1:0] OFFSET 
	   = BIASES[oc] * $pow(2.0, IN_FRAC_BITW + WGT_FRAC_BITW) +
	     ((RES_SHIFT > 0) ? $pow(2.0, RES_SHIFT - 1) : 0.0);
	 always_ff @(posedge clock)
	   biased <= (sum + OFFSET) >>> RES_SHIFT;

	 // batch normalization
	 wire signed [OUT_BITW-1:0] bn_val;
	 if(BATCH_NORM != 0) begin
	    batch_norm
	      #( .BIT_WIDTH(OUT_BITW),     .FRAC_BITW(OUT_FRAC_BITW),
		 .AVG_MEAN(AVG_MEANS[oc]), .AVG_VAR(AVG_VARS[oc]),
		 .GAMMA(GAMMAS[oc]),       .BETA(BETAS[oc])           )
	    bnm_0
	      (  .clock(clock), .in_val(biased), .out_val(bn_val) );
	 end
	 else begin
	    assign bn_val = biased;
	 end

	 // applies activation (Leaky ReLU)
	 wire signed [OUT_BITW-1:0] result;
	 if(LRELU_SLOPE < 0) begin
	    assign result = bn_val;
	 end
	 else begin
	    reg signed [OUT_BITW-1:0] res_buf;
	    always_ff @(posedge clock)
	      res_buf <= (bn_val >= 0) ? bn_val : 
			 (bn_val * LRELU_SLOPE + 8) / 16;
	    assign result = res_buf;
	 end

	 // residual connection
	 if(RESIDUAL != 0) begin
	    reg signed [OUT_BITW-1:0] fused;
	    if(oc < IN_CHS) begin
	       wire signed [IN_BITW-1:0] skip_raw;
	       delay
		 #( .BIT_WIDTH(IN_BITW), .LATENCY(LATENCY - 1) )
	       dly_0
		 (  .clock(clock), .n_rst(n_rst), .out_data(skip_raw),
		    .in_data(cvf_patch_ic[oc].stp_patch[(FLT_SIZE/2)*FLT_SIZE
							+ (FLT_SIZE/2)]) );
	       if(SKIP_SHIFT >= 0) begin
		  wire signed [OUT_BITW-1:0] skip_ext = skip_raw;
		  always_ff @(posedge clock)
		    fused <= result + (skip_ext <<< SKIP_SHIFT);
	       end
	       else begin
		  always_ff @(posedge clock)
		    fused <= result + 
			     (((skip_raw >>> (-SKIP_SHIFT - 1)) + 1) >>> 1);
	       end
	    end
	    else begin
	       always_ff @(posedge clock)
		 fused <= result;
	    end
	    assign out_vals[oc] = fused;
	 end
	 else
	   assign out_vals[oc] = result;
      end
   endgenerate
   
   // coordinates adjustment
   coord_adjuster
     #( .FRAME_HEIGHT(FRAME_HEIGHT), .FRAME_WIDTH(FRAME_WIDTH),
	.LATENCY(LATENCY) )
   cad_1
     (  .clock(clock), .out_vcnt(out_vcnt), .out_hcnt(out_hcnt),
	.in_vcnt(cvf_patch_ic[0].stp_vcnt), 
	.in_hcnt(cvf_patch_ic[0].stp_hcnt)                         );

endmodule
`default_nettype wire
