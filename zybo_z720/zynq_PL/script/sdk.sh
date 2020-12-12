#!/bin/sh

WORKSPACE=".."
PROJECT="tremor_detect"
TOP="genesys_zu_3eg_top"

xsdk -workspace ${WORKSPACE}/vivado_proj/${PROJECT}.sdk -hwspec ${WORKSPACE}/vivado_proj/${PROJECT}.sdk/${TOP}.hdf
