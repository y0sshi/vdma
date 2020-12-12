#!/bin/sh

vivado -mode tcl -source tcl/create_proj.tcl
rm -rf .Xil .srcs vivado*
