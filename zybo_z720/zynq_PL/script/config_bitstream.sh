#!/bin/sh

vivado -mode tcl -source tcl/config_bitstream.tcl
rm -rf .Xil .srcs vivado*
