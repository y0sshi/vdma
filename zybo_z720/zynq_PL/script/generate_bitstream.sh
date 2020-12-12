#!/bin/sh

vivado -mode tcl -source tcl/generate_bitstream.tcl
rm -rf .Xil .srcs vivado*
