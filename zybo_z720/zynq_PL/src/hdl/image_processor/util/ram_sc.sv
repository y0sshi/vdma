//-----------------------------------------------------------------------------
// <ram_sc>
//  - Single-clock random access memory module without reset
//    - Read latency: 1 clock cycle
//  - If write and read to the same address occur at the same time,
//    <rd_data> of the next clock will be:
//    - FORWARD == 0: previously stored data
//    - else        : newly written data
//-----------------------------------------------------------------------------
// Version 1.02 (Jul. 29, 2020)
//  - Fixed the bug where <wr_data> is forwarded even if <wr_en> is 0
//  - Fixed the problem where distributed RAMs are inferred instead of
//    BRAMs in Vivado (and possibly other CADs) when using data forwarding
//-----------------------------------------------------------------------------
// (C) 2019-2020 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns

module ram_sc
  #( parameter int WORD_SIZE = -1,  // bit width of each word
     parameter int RAM_SIZE  = -1,  // # of words
     parameter int FORWARD   =  0 ) // whether to use forwarding
   ( clock,
     wr_en, wr_addr, wr_data,
     rd_addr, rd_data         );

   // local parameters --------------------------------------------------------
   localparam int ADDR_BITW = $clog2(RAM_SIZE);

   // inputs/outputs ----------------------------------------------------------
   input wire 	               clock,   wr_en;
   input wire [ADDR_BITW-1:0]  wr_addr, rd_addr;
   input wire [WORD_SIZE-1:0]  wr_data;
   output wire [WORD_SIZE-1:0] rd_data;

   // write -------------------------------------------------------------------
   reg [WORD_SIZE-1:0] 	      memory [0:RAM_SIZE-1];
   always_ff @(posedge clock) begin
      if(wr_en)
	memory[wr_addr] <= wr_data;
   end

   // read --------------------------------------------------------------------
   generate
      reg [WORD_SIZE-1:0] rd_data_buf;
      always_ff @(posedge clock)
	rd_data_buf <= memory[rd_addr];
      if(FORWARD == 0) begin: ram_sc_without_forward
	 assign rd_data = rd_data_buf;
      end
      else begin: ram_sc_with_forward
	 reg [WORD_SIZE-1:0] wr_data_buf;
	 reg 		     collision;
	 always_ff @(posedge clock) begin
	    collision   <= wr_en && (wr_addr == rd_addr);
	    wr_data_buf <= wr_data;
	 end
	 assign rd_data = collision ? wr_data_buf : rd_data_buf;
      end
   endgenerate
	 
endmodule
`default_nettype wire
