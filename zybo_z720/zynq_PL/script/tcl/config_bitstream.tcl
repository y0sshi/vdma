# env
set BITSTREAM     "zybo_z7_top.bit"
set PROJECT_NAME  "vdma_test"
set WORKSPACE_DIR ".."
set DEVICE        "xc7z020_1"

open_hw
connect_hw_server
open_hw_target
current_hw_device [get_hw_devices ${DEVICE}]
refresh_hw_device -update_hw_probes false [lindex [get_hw_devices ${DEVICE}] 0]
set_property PROBES.FILE {} [get_hw_devices ${DEVICE}]
set_property FULL_PROBES.FILE {} [get_hw_devices ${DEVICE}]
set_property PROGRAM.FILE ${WORKSPACE_DIR}/vivado_proj/${PROJECT_NAME}.runs/impl_1/${BITSTREAM} [get_hw_devices ${DEVICE}]
program_hw_devices [get_hw_devices ${DEVICE}]
refresh_hw_device [lindex [get_hw_devices ${DEVICE}] 0]
exit
