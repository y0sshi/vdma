#!/bin/bash

cd ./libuio
make && sudo make install && make clean
cd ../

cd ./libvdma
make && sudo make install && make clean
