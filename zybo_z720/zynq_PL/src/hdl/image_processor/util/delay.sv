//-----------------------------------------------------------------------------
// <delay> 
//  - Module for delaying an input (like shift registers) using FIFO
//    - Latency: <LATENCY> clock cycles
//      - <LATENCY> should be >= 2
//-----------------------------------------------------------------------------
// Version 1.01 (Dec. 18, 2019)
//  - Simplified by using the new <fifo_sc> module
//-----------------------------------------------------------------------------
// (C) 2018-2019 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns
  
module delay
  #( parameter int BIT_WIDTH = -1,   // I/O bit width
     parameter int LATENCY   = 1 )   
   ( clock, n_rst, in_data, out_data );

   // inputs/outputs ----------------------------------------------------------
   input wire       	       clock, n_rst;
   input wire [BIT_WIDTH-1:0]  in_data;
   output wire [BIT_WIDTH-1:0] out_data;

   // fifo --------------------------------------------------------------------
   generate
      if(LATENCY == 0) begin: delay_no_latency
	 assign out_data = in_data;
      end
      else begin: delay_with_fifo
	 wire [$clog2(LATENCY)-1:0] tmp_count;
	 wire 			    tmp_full, tmp_empty;
	 fifo_sc
	   #( .BIT_WIDTH(BIT_WIDTH), .FIFO_SIZE(LATENCY),
	      .INITIAL_SIZE(LATENCY - 1) )
	 fifo_0
	   (  .clock(clock), .n_rst(n_rst), .wr_en(1'b1), .rd_en(1'b1),
	      .wr_data(in_data), .rd_data(out_data), .out_count(tmp_count), 
	      .out_full(tmp_full), .out_empty(tmp_empty)                    );
      end
   endgenerate
   
endmodule
`default_nettype wire

