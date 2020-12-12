set WORKSPACE_DIR ".."
set PROJECT_NAME  "vdma_test"
set TOP_MODULE    "zybo_z7_top"
set JOBS          8

open_project ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.xpr

# synthesis
reset_run synth_1
launch_runs synth_1 -jobs ${JOBS}
wait_on_run synth_1

# impl
launch_runs impl_1 -jobs ${JOBS}
wait_on_run impl_1

# generate bitstream
launch_runs impl_1 -to_step write_bitstream -jobs ${JOBS}
wait_on_run impl_1

# export hardware to SDK
file mkdir ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.sdk
file copy -force ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.runs/impl_1/${TOP_MODULE}.sysdef ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.sdk/${TOP_MODULE}.hdf
exit
