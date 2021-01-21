//-----------------------------------------------------------------------------
// <ram_dc>
//  - Dual-clock random access memory module without reset
//    - Read latency: 1 clock cycle
//-----------------------------------------------------------------------------
// Version 1.03 (Dec. 18, 2019)
//  - Code refinement
//-----------------------------------------------------------------------------
// (C) 2019 Taito Manabe
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns
  
module ram_dc
  #( parameter int WORD_SIZE = -1,  // bit width of each word
     parameter int RAM_SIZE  = -1 ) // # of words
   ( wr_clock, rd_clock, 
     wr_en, wr_addr, wr_data,
     rd_addr, rd_data         );

   // local parameters --------------------------------------------------------
   localparam int ADDR_BITW = $clog2(RAM_SIZE);

   // inputs/outputs ----------------------------------------------------------
   input wire 	              wr_clock, rd_clock, wr_en;
   input wire [ADDR_BITW-1:0] wr_addr,  rd_addr;
   input wire [WORD_SIZE-1:0] wr_data;
   output reg [WORD_SIZE-1:0] rd_data;

   // memory ------------------------------------------------------------------
   reg [WORD_SIZE-1:0] 	      memory [0:RAM_SIZE-1];

   always_ff @(posedge wr_clock) begin
      if(wr_en)
	memory[wr_addr] <= wr_data;
   end
   
   always_ff @(posedge rd_clock) begin
      rd_data <= memory[rd_addr];
   end
   
endmodule
`default_nettype wire
