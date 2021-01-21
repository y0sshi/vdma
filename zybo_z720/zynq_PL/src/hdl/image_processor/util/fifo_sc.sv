//-----------------------------------------------------------------------------
// <fifo_sc> 
//  - Single-clock first-in/first-out (queue) module
//    - <INITIAL_SIZE> is the initial queue size (= write address).
//      If the value is n and both of <wr_en> and <rd_en> keep
//      being active, this module behaves as the (n+1)-clock delay circuit.
//      <INITIAL_SIZE> MUST be in the range of [0, FIFO_SIZE - 1]
//      for this purpose. Be careful for indefinite values output at first.
//  - Read latency: 1 clock cycle
//-----------------------------------------------------------------------------
// Version 1.01 (Feb. 20, 2020)
//  - Added <out_empty> port
//  - Read attempt to empty queue is now properly ignored
//-----------------------------------------------------------------------------
// (C) 2018-2020 Taito Manabe. All rights reserved.
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ns
  
module fifo_sc
  #( parameter int BIT_WIDTH    = -1,
     parameter int FIFO_SIZE    = -1,
     parameter int INITIAL_SIZE =  0 )
   ( clock, n_rst,
     wr_en, wr_data, rd_en, rd_data, 
     out_count, out_full, out_empty );

   // local parameters --------------------------------------------------------
   localparam int ADDR_BITW = $clog2(FIFO_SIZE);

   // inputs/outputs ----------------------------------------------------------
   input wire 	               clock, n_rst, wr_en, rd_en;
   input wire [BIT_WIDTH-1:0]  wr_data;
   output wire [BIT_WIDTH-1:0] rd_data;
   output wire [ADDR_BITW-1:0] out_count;
   output wire 		       out_full, out_empty;

   // registers ---------------------------------------------------------------
   reg [ADDR_BITW-1:0] 	       wr_addr, rd_addr;
   reg 			       rd_en_buf;

   // write address control ---------------------------------------------------
   wire 		       not_full, not_empty;
   assign not_full  = (wr_addr == FIFO_SIZE - 1 && rd_addr != 0) ||
		      (wr_addr != FIFO_SIZE - 1 && wr_addr + 1 != rd_addr);
   assign not_empty = (rd_addr != wr_addr);
   
   always_ff @(posedge clock) begin
      if(!n_rst)
	wr_addr <= INITIAL_SIZE;
      else begin
	 if(wr_en && (rd_en || not_full)) begin
	    if(wr_addr == FIFO_SIZE - 1)
	      wr_addr <= 0;
	    else
	      wr_addr <= wr_addr + 1;
	 end
      end
   end

   // read address control ----------------------------------------------------
   always_ff @(posedge clock) begin
      if(!n_rst)
	rd_addr <= 0;
      else begin
	 rd_en_buf <= (rd_en && (wr_en || not_empty));
	 if(rd_en && (wr_en || not_empty)) begin
	    if(rd_addr == FIFO_SIZE - 1)
	      rd_addr <= 0;
	    else
	      rd_addr <= rd_addr + 1;
	 end
      end
   end    

   // ram ---------------------------------------------------------------------
   wire [BIT_WIDTH-1:0]        ram_rd_data;
   ram_sc
     #( .WORD_SIZE(BIT_WIDTH), .RAM_SIZE(FIFO_SIZE), .FORWARD(1) )
   ram_0
     (  .clock(clock),     .wr_en(wr_en && (rd_en || not_full)),
	.wr_addr(wr_addr), .wr_data(wr_data),
	.rd_addr(rd_addr), .rd_data(ram_rd_data) );

   // assigns results ---------------------------------------------------------
   assign rd_data   = rd_en_buf ? ram_rd_data : 0;
   assign out_count = (rd_addr <= wr_addr) ? wr_addr - rd_addr :
		      FIFO_SIZE - (rd_addr - wr_addr);
   assign out_full  = !not_full;
   assign out_empty = !not_empty;
   
endmodule
`default_nettype wire

