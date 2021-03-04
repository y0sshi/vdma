/******************************************************************************
*
* Copyright (C) 2012 - 2018 Xilinx, Inc.  All rights reserved.
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
* XILINX  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
* WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
* OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*
* Except as contained in this notice, the name of the Xilinx shall not be used
* in advertising or otherwise to promote the sale, use or other dealings in
* this Software without prior written authorization from Xilinx.
*
******************************************************************************/
/*****************************************************************************/
/**
*
* @file xaxivdma.c
* @addtogroup axivdma_v6_6
* @{
*
* Implementation of the driver API functions for the AXI Video DMA engine.
*
* <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -------------------------------------------------------
* 1.00a jz   08/16/10 First release
* 2.00a jz   12/10/10 Added support for direct register access mode, v3 core
* 2.01a jz   01/19/11 Added ability to re-assign BD addresses
* 	rkv  03/28/11 Added support for frame store register.
* 3.00a srt  08/26/11 Added support for Flush on Frame Sync and dynamic
*		      programming of Line Buffer Thresholds and added API
*		      XAxiVdma_SetLineBufThreshold.
* 4.00a srt  11/21/11 - XAxiVdma_CfgInitialize API is modified to use the
*			EffectiveAddr.
*		      - Added APIs:
*			XAxiVdma_FsyncSrcSelect()
*			XAxiVdma_GenLockSourceSelect()
* 4.01a srt  06/13/12 - Added APIs:
*			XAxiVdma_GetDmaChannelErrors()
*			XAxiVdma_ClearDmaChannelErrors()
* 4.02a srt  09/25/12 - Fixed CR 678734
* 			XAxiVdma_SetFrmStore function changed to remove
*                       Reset logic after setting number of frame stores.
* 4.03a srt  01/18/13 - Updated logic of GenLockSourceSelect() & FsyncSrcSelect()
*                       APIs for newer versions of IP (CR: 691052).
*		      - Modified CfgInitialize() API to initialize
*			StreamWidth parameters. (CR 691866)
* 4.04a srt  03/03/13 - Support for *_ENABLE_DEBUG_INFO_* debug configuration
*			parameters (CR: 703738)
* 6.1   sk   11/10/15 Used UINTPTR instead of u32 for Baseaddress CR# 867425.
*                     Changed the prototype of XAxiVdma_CfgInitialize API.
* 6.6   rsp  07/02/18   Add Vertical flip support. Populate "HasVFlip" from
*                       XAxiVdma_Config(CR-989453)
*
* </pre>
*
******************************************************************************/

/***************************** Include Files *********************************/

#include <slab/bsp/xaxivdma.h>
#include <slab/bsp/xaxivdma_i.h>
#include <slab/bsp/xaxivdma_hw.h>
#include <slab/bsp/xparameters.h>
#include <slab/bsp/xstatus.h>
#include <stdio.h>

/************************** Constant Definitions *****************************/
/* The polling upon starting the hardware
 *
 * We have the assumption that reset is fast upon hardware start
 */
#define INITIALIZATION_POLLING   100000
#ifndef XPAR_XAXIVDMA_NUM_INSTANCES
#define XPAR_XAXIVDMA_NUM_INSTANCES		0
#endif
#define XAXIVDMA_RESET_POLLING      1000

/************************** Function Prototypes ******************************/

/* BD APIs, used by this file only
 */
static u32 XAxiVdma_BdRead(XAxiVdma_Bd *BdPtr, int Offset);
static void XAxiVdma_BdWrite(XAxiVdma_Bd *BdPtr, int Offset, u32 Value);
static void XAxiVdma_BdSetNextPtr(XAxiVdma_Bd *BdPtr, u32 NextPtr);
static void XAxiVdma_BdSetAddr(XAxiVdma_Bd *BdPtr, u32 Addr);
static int XAxiVdma_BdSetVsize(XAxiVdma_Bd *BdPtr, int Vsize);
static int XAxiVdma_BdSetHsize(XAxiVdma_Bd *BdPtr, int Vsize);
static int XAxiVdma_BdSetStride(XAxiVdma_Bd *BdPtr, int Stride);
static int XAxiVdma_BdSetFrmDly(XAxiVdma_Bd *BdPtr, int FrmDly);

/*****************************************************************************/
/**
 * Get a channel
 *
 * @param InstancePtr is the DMA engine to work on
 * @param Direction is the direction for the channel to get
 *
 * @return
 * The pointer to the channel. Upon error, return NULL.
 *
 * @note
 * Since this function is internally used, we assume Direction is valid
 *****************************************************************************/
XAxiVdma_Channel *XAxiVdma_GetChannel(XAxiVdma *InstancePtr,
        u16 Direction)
{

	if (Direction == XAXIVDMA_READ) {
		return &(InstancePtr->ReadChannel);
	}
	else if (Direction == XAXIVDMA_WRITE) {
		return &(InstancePtr->WriteChannel);
	}
	else {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Invalid direction %x\r\n", Direction);

		return NULL;
	}
}

static int XAxiVdma_Major(XAxiVdma *InstancePtr) {
	u32 Reg;

	Reg = XAxiVdma_ReadReg(InstancePtr->BaseAddr, XAXIVDMA_VERSION_OFFSET);

	return (int)((Reg & XAXIVDMA_VERSION_MAJOR_MASK) >>
	          XAXIVDMA_VERSION_MAJOR_SHIFT);
}

/*****************************************************************************/
/**
 * Initialize the driver with hardware configuration
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param CfgPtr is the pointer to the hardware configuration structure
 * @param EffectiveAddr is the virtual address map for the device
 *
 * @return
 *  - XST_SUCCESS if everything goes fine
 *  - XST_FAILURE if reset the hardware failed, need system reset to recover
 *
 * @note
 * If channel fails reset,  then it will be set as invalid
 *****************************************************************************/
int XAxiVdma_CfgInitialize(XAxiVdma *InstancePtr, XAxiVdma_Config *CfgPtr,
				UINTPTR EffectiveAddr)
{
	XAxiVdma_Channel *RdChannel;
	XAxiVdma_Channel *WrChannel;
	int Polls;

	/* Validate parameters */
	Xil_AssertNonvoid(InstancePtr != NULL);
	Xil_AssertNonvoid(CfgPtr != NULL);

	/* Initially, no interrupt callback functions
	 */
	InstancePtr->ReadCallBack.CompletionCallBack = 0x0;
	InstancePtr->ReadCallBack.ErrCallBack = 0x0;
	InstancePtr->WriteCallBack.CompletionCallBack = 0x0;
	InstancePtr->WriteCallBack.ErrCallBack = 0x0;

	InstancePtr->BaseAddr = EffectiveAddr;
	InstancePtr->MaxNumFrames = CfgPtr->MaxFrameStoreNum;
	InstancePtr->HasMm2S = CfgPtr->HasMm2S;
	InstancePtr->HasS2Mm = CfgPtr->HasS2Mm;
	InstancePtr->UseFsync = CfgPtr->UseFsync;
	InstancePtr->InternalGenLock = CfgPtr->InternalGenLock;
	InstancePtr->AddrWidth = CfgPtr->AddrWidth;

	if (XAxiVdma_Major(InstancePtr) < 3) {
		InstancePtr->HasSG = 1;
	}
	else {
		InstancePtr->HasSG = CfgPtr->HasSG;
	}

	/* The channels are not valid until being initialized
	 */
	RdChannel = XAxiVdma_GetChannel(InstancePtr, XAXIVDMA_READ);
	RdChannel->IsValid = 0;

	WrChannel = XAxiVdma_GetChannel(InstancePtr, XAXIVDMA_WRITE);
	WrChannel->IsValid = 0;

	if (InstancePtr->HasMm2S) {
		RdChannel->direction = XAXIVDMA_READ;
		RdChannel->ChanBase = InstancePtr->BaseAddr + XAXIVDMA_TX_OFFSET;
		RdChannel->InstanceBase = InstancePtr->BaseAddr;
		RdChannel->HasSG = InstancePtr->HasSG;
		RdChannel->IsRead = 1;
		RdChannel->StartAddrBase = InstancePtr->BaseAddr +
		                              XAXIVDMA_MM2S_ADDR_OFFSET;

		RdChannel->NumFrames = CfgPtr->MaxFrameStoreNum;

		/* Flush on Sync */
		RdChannel->FlushonFsync = CfgPtr->FlushonFsync;

		/* Dynamic Line Buffers Depth */
		RdChannel->LineBufDepth = CfgPtr->Mm2SBufDepth;
		if(RdChannel->LineBufDepth > 0) {
			RdChannel->LineBufThreshold =
				XAxiVdma_ReadReg(RdChannel->ChanBase,
					XAXIVDMA_BUFTHRES_OFFSET);
			xdbg_printf(XDBG_DEBUG_GENERAL,
				"Read Channel Buffer Threshold %d bytes\n\r",
				RdChannel->LineBufThreshold);
		}
		RdChannel->HasDRE = CfgPtr->HasMm2SDRE;
		RdChannel->WordLength = CfgPtr->Mm2SWordLen >> 3;
		RdChannel->StreamWidth = CfgPtr->Mm2SStreamWidth >> 3;
		RdChannel->AddrWidth = InstancePtr->AddrWidth;

		/* Internal GenLock */
		RdChannel->GenLock = CfgPtr->Mm2SGenLock;

		/* Debug Info Parameter flags */
		if (!CfgPtr->EnableAllDbgFeatures) {
			if (CfgPtr->Mm2SThresRegEn) {
				RdChannel->DbgFeatureFlags |=
					XAXIVDMA_ENABLE_DBG_THRESHOLD_REG;
			}

			if (CfgPtr->Mm2SFrmStoreRegEn) {
				RdChannel->DbgFeatureFlags |=
					XAXIVDMA_ENABLE_DBG_FRMSTORE_REG;
			}

			if (CfgPtr->Mm2SDlyCntrEn) {
				RdChannel->DbgFeatureFlags |=
					XAXIVDMA_ENABLE_DBG_DLY_CNTR;
			}

			if (CfgPtr->Mm2SFrmCntrEn) {
				RdChannel->DbgFeatureFlags |=
					XAXIVDMA_ENABLE_DBG_FRM_CNTR;
			}

		} else {
			RdChannel->DbgFeatureFlags =
				XAXIVDMA_ENABLE_DBG_ALL_FEATURES;
		}

		XAxiVdma_ChannelInit(RdChannel);

		XAxiVdma_ChannelReset(RdChannel);

		/* At time of initialization, no transfers are going on,
		 * reset is expected to be quick
		 */
		Polls = INITIALIZATION_POLLING;

		while (Polls && XAxiVdma_ChannelResetNotDone(RdChannel)) {
			Polls -= 1;
		}

		if (!Polls) {
			xdbg_printf(XDBG_DEBUG_ERROR,
			    "Read channel reset failed %x\n\r",
			    (unsigned int)XAxiVdma_ChannelGetStatus(RdChannel));

			return XST_FAILURE;
		}
	}

	if (InstancePtr->HasS2Mm) {
		WrChannel->direction = XAXIVDMA_WRITE;
		WrChannel->ChanBase = InstancePtr->BaseAddr + XAXIVDMA_RX_OFFSET;
		WrChannel->InstanceBase = InstancePtr->BaseAddr;
		WrChannel->HasSG = InstancePtr->HasSG;
		WrChannel->IsRead = 0;
		WrChannel->StartAddrBase = InstancePtr->BaseAddr +
		                                 XAXIVDMA_S2MM_ADDR_OFFSET;
		WrChannel->NumFrames = CfgPtr->MaxFrameStoreNum;
		WrChannel->AddrWidth = InstancePtr->AddrWidth;
		WrChannel->HasVFlip = CfgPtr->HasVFlip;

		/* Flush on Sync */
		WrChannel->FlushonFsync = CfgPtr->FlushonFsync;

		/* Dynamic Line Buffers Depth */
		WrChannel->LineBufDepth = CfgPtr->S2MmBufDepth;
		if(WrChannel->LineBufDepth > 0) {
			WrChannel->LineBufThreshold =
				XAxiVdma_ReadReg(WrChannel->ChanBase,
					XAXIVDMA_BUFTHRES_OFFSET);
			xdbg_printf(XDBG_DEBUG_GENERAL,
				"Write Channel Buffer Threshold %d bytes\n\r",
				WrChannel->LineBufThreshold);
		}
		WrChannel->HasDRE = CfgPtr->HasS2MmDRE;
		WrChannel->WordLength = CfgPtr->S2MmWordLen >> 3;
		WrChannel->StreamWidth = CfgPtr->S2MmStreamWidth >> 3;

		/* Internal GenLock */
		WrChannel->GenLock = CfgPtr->S2MmGenLock;

		/* Frame Sync Source Selection*/
		WrChannel->S2MmSOF = CfgPtr->S2MmSOF;

		/* Debug Info Parameter flags */
		if (!CfgPtr->EnableAllDbgFeatures) {
			if (CfgPtr->S2MmThresRegEn) {
				WrChannel->DbgFeatureFlags |=
					 XAXIVDMA_ENABLE_DBG_THRESHOLD_REG;
			}

			if (CfgPtr->S2MmFrmStoreRegEn) {
				WrChannel->DbgFeatureFlags |=
					XAXIVDMA_ENABLE_DBG_FRMSTORE_REG;
			}

			if (CfgPtr->S2MmDlyCntrEn) {
				WrChannel->DbgFeatureFlags |=
					XAXIVDMA_ENABLE_DBG_DLY_CNTR;
			}

			if (CfgPtr->S2MmFrmCntrEn) {
				WrChannel->DbgFeatureFlags |=
					XAXIVDMA_ENABLE_DBG_FRM_CNTR;
			}

		} else {
			WrChannel->DbgFeatureFlags =
					XAXIVDMA_ENABLE_DBG_ALL_FEATURES;
		}

		XAxiVdma_ChannelInit(WrChannel);

		XAxiVdma_ChannelReset(WrChannel);

		/* At time of initialization, no transfers are going on,
		 * reset is expected to be quick
		 */
		Polls = INITIALIZATION_POLLING;

		while (Polls && XAxiVdma_ChannelResetNotDone(WrChannel)) {
			Polls -= 1;
		}

		if (!Polls) {
			xdbg_printf(XDBG_DEBUG_ERROR,
			    "Write channel reset failed %x\n\r",
			    (unsigned int)XAxiVdma_ChannelGetStatus(WrChannel));

			return XST_FAILURE;
		}
	}

	InstancePtr->IsReady = XAXIVDMA_DEVICE_READY;

	return XST_SUCCESS;
}

/*****************************************************************************/
/**
 * This function resets one DMA channel
 *
 * The registers will be default values after the reset
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the channel to work on, use XAXIVDMA_READ/WRITE
 *
 * @return
 * None
 *
 * @note
 * Due to undeterminism of system delays, check the reset status through
 * XAxiVdma_ResetNotDone(). If direction is invalid, do nothing.
 *****************************************************************************/
void XAxiVdma_Reset(XAxiVdma *InstancePtr, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		return;
	}

	if (Channel->IsValid) {
		XAxiVdma_ChannelReset(Channel);

		return;
	}
}

/*****************************************************************************/
/**
 * This function checks one DMA channel for reset completion
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the channel to work on, use XAXIVDMA_READ/WRITE
 *
 * @return
 *  - 0 if reset is done
 *  - 1 if reset is ongoing
 *
 * @note
 * We do not check for channel validity, because channel is marked as invalid
 * before reset is done
 *****************************************************************************/
int XAxiVdma_ResetNotDone(XAxiVdma *InstancePtr, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	/* If dirction is invalid, reset is never done
	 */
	if (!Channel) {
		return 1;
	}

	return XAxiVdma_ChannelResetNotDone(Channel);
}

/*****************************************************************************/
/**
 * Check whether a DMA channel is busy
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the channel to work on, use XAXIVDMA_READ/WRITE
 *
 * @return
 * - Non-zero if the channel is busy
 * - Zero if the channel is idle
 *
 *****************************************************************************/
int XAxiVdma_IsBusy(XAxiVdma *InstancePtr, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		return 0;
	}

	if (Channel->IsValid) {
		return XAxiVdma_ChannelIsBusy(Channel);
	}
	else {
		/* An invalid channel is never busy
		 */
		return 0;
	}
}

/*****************************************************************************/
/**
 * Get the current frame that hardware is working on
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the channel to work on, use XAXIVDMA_READ/WRITE
 *
 * @return
 * The current frame that the hardware is working on
 *
 * @note
 * If returned frame number is out of range, then the channel is invalid
 *****************************************************************************/
u32 XAxiVdma_CurrFrameStore(XAxiVdma *InstancePtr, u16 Direction)
{
	u32 Rc;

	Rc = XAxiVdma_ReadReg(InstancePtr->BaseAddr, XAXIVDMA_PARKPTR_OFFSET);

	if (Direction == XAXIVDMA_READ) {
		Rc &= XAXIVDMA_PARKPTR_READSTR_MASK;
		return (Rc >> XAXIVDMA_READSTR_SHIFT);
	}
	else if (Direction == XAXIVDMA_WRITE) {
		Rc &= XAXIVDMA_PARKPTR_WRTSTR_MASK;
		return (Rc >> XAXIVDMA_WRTSTR_SHIFT);
	}
	else {
		return 0xFFFFFFFF;
	}
}

/*****************************************************************************/
/**
 * Get the version of the hardware
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 *
 * @return
 * The version of the hardware
 *
 *****************************************************************************/
u32 XAxiVdma_GetVersion(XAxiVdma *InstancePtr)
{
	return XAxiVdma_ReadReg(InstancePtr->BaseAddr, XAXIVDMA_VERSION_OFFSET);
}

/*****************************************************************************/
/**
 * Get the status of a channel
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the channel to work on, use XAXIVDMA_READ/WRITE
 *
 * @return
 * The status of the channel
 *
 * @note
 * An invalid return value indicates that channel is invalid
 *****************************************************************************/
u32 XAxiVdma_GetStatus(XAxiVdma *InstancePtr, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		return 0xFFFFFFFF;
	}

	if (Channel->IsValid) {
		return XAxiVdma_ChannelGetStatus(Channel);
	}
	else {
		return 0xFFFFFFFF;
	}
}

/*****************************************************************************/
/**
 * Configure Line Buffer Threshold
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param LineBufThreshold is the value to set threshold
 * @param Direction is the DMA channel to work on
 *
 * @return
 * - XST_SUCCESS if successful
 * - XST_FAILURE otherwise
 * - XST_NO_FEATURE if access to Threshold register is disabled
 *****************************************************************************/
int XAxiVdma_SetLineBufThreshold(XAxiVdma *InstancePtr, int LineBufThreshold,
	u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!(Channel->DbgFeatureFlags & XAXIVDMA_ENABLE_DBG_THRESHOLD_REG)) {
		xdbg_printf(XDBG_DEBUG_ERROR,
				"Threshold Register is disabled\n\r");
		return XST_NO_FEATURE;
	}

	if(Channel->LineBufThreshold) {
		if((LineBufThreshold < Channel->LineBufDepth) &&
			(LineBufThreshold % Channel->StreamWidth == 0)) {
			XAxiVdma_WriteReg(Channel->ChanBase,
				XAXIVDMA_BUFTHRES_OFFSET, LineBufThreshold);

			xdbg_printf(XDBG_DEBUG_GENERAL,
				"Line Buffer Threshold set to %x\n\r",
				XAxiVdma_ReadReg(Channel->ChanBase,
				XAXIVDMA_BUFTHRES_OFFSET));
		}
		else {
			xdbg_printf(XDBG_DEBUG_ERROR,
				"Invalid Line Buffer Threshold\n\r");
			return XST_FAILURE;
		}
	}
	else {
		xdbg_printf(XDBG_DEBUG_ERROR,
			"Failed to set Threshold\n\r");
		return XST_FAILURE;
	}
	return XST_SUCCESS;
}


/*****************************************************************************/
/**
 * Configure Frame Sync Source and valid only when C_USE_FSYNC is enabled.
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Source is the value to set the source of Frame Sync
 * @param Direction is the DMA channel to work on
 *
 * @return
 * - XST_SUCCESS if successful
 * - XST_FAILURE if C_USE_FSYNC is disabled.
 *
 *****************************************************************************/
int XAxiVdma_FsyncSrcSelect(XAxiVdma *InstancePtr, u32 Source,
				u16 Direction)
{
	XAxiVdma_Channel *Channel;
	u32 CrBits;
	u32 UseFsync;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (Direction == XAXIVDMA_WRITE) {
		UseFsync = ((InstancePtr->UseFsync == 1) ||
				(InstancePtr->UseFsync == 3)) ? 1 : 0;
	} else {
		UseFsync = ((InstancePtr->UseFsync == 1) ||
				(InstancePtr->UseFsync == 2)) ? 1 : 0;
	}

	if (UseFsync) {
		CrBits = XAxiVdma_ReadReg(Channel->ChanBase,
				XAXIVDMA_CR_OFFSET);

		switch (Source) {
		case XAXIVDMA_CHAN_FSYNC:
			/* Same Channel Frame Sync */
			CrBits &= ~(XAXIVDMA_CR_FSYNC_SRC_MASK);
			break;

		case XAXIVDMA_CHAN_OTHER_FSYNC:
			/* The other Channel Frame Sync */
			CrBits |= (XAXIVDMA_CR_FSYNC_SRC_MASK & ~(1 << 6));
			break;

		case XAXIVDMA_S2MM_TUSER_FSYNC:
			/* S2MM TUser Sync */
			if (Channel->S2MmSOF) {
				CrBits |= (XAXIVDMA_CR_FSYNC_SRC_MASK
						 & ~(1 << 5));
			}
			else
				return XST_FAILURE;
			break;
		}

		XAxiVdma_WriteReg(Channel->ChanBase,
			XAXIVDMA_CR_OFFSET, CrBits);

		return XST_SUCCESS;
	}

	xdbg_printf(XDBG_DEBUG_ERROR,
			"This bit is not valid for this configuration\n\r");
	return XST_FAILURE;
}

/*****************************************************************************/
/**
 * Configure Gen Lock Source
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Source is the value to set the source of Gen Lock
 * @param Direction is the DMA channel to work on
 *
 * @return
 * - XST_SUCCESS if successful
 * - XST_FAILURE if the channel is in GenLock Master Mode.
 *		 if C_INCLUDE_INTERNAL_GENLOCK is disabled.
 *
 *****************************************************************************/
int XAxiVdma_GenLockSourceSelect(XAxiVdma *InstancePtr, u32 Source,
					u16 Direction)
{
	XAxiVdma_Channel *Channel, *XChannel;
	u32 CrBits;

	if (InstancePtr->HasMm2S && InstancePtr->HasS2Mm &&
			InstancePtr->InternalGenLock) {
		if (Direction == XAXIVDMA_WRITE) {
			Channel = XAxiVdma_GetChannel(InstancePtr, Direction);
			XChannel = XAxiVdma_GetChannel(InstancePtr, XAXIVDMA_READ);
		} else {
			Channel = XAxiVdma_GetChannel(InstancePtr, Direction);
			XChannel = XAxiVdma_GetChannel(InstancePtr, XAXIVDMA_WRITE);
		}

		if ((Channel->GenLock == XAXIVDMA_GENLOCK_MASTER &&
			XChannel->GenLock == XAXIVDMA_GENLOCK_SLAVE) ||
			(Channel->GenLock == XAXIVDMA_GENLOCK_SLAVE &&
				XChannel->GenLock == XAXIVDMA_GENLOCK_MASTER) ||
			(Channel->GenLock == XAXIVDMA_DYN_GENLOCK_MASTER &&
				XChannel->GenLock == XAXIVDMA_DYN_GENLOCK_SLAVE) ||
			(Channel->GenLock == XAXIVDMA_DYN_GENLOCK_SLAVE &&
				XChannel->GenLock == XAXIVDMA_DYN_GENLOCK_MASTER)) {

			CrBits = XAxiVdma_ReadReg(Channel->ChanBase,
				XAXIVDMA_CR_OFFSET);

			if (Source == XAXIVDMA_INTERNAL_GENLOCK)
				CrBits |= XAXIVDMA_CR_GENLCK_SRC_MASK;
			else if (Source == XAXIVDMA_EXTERNAL_GENLOCK)
				CrBits &= ~XAXIVDMA_CR_GENLCK_SRC_MASK;
			else {
				xdbg_printf(XDBG_DEBUG_ERROR,
					"Invalid argument\n\r");
				return XST_FAILURE;
			}

			XAxiVdma_WriteReg(Channel->ChanBase,
				XAXIVDMA_CR_OFFSET, CrBits);

			return XST_SUCCESS;
		}
	}

	xdbg_printf(XDBG_DEBUG_ERROR,
			"This bit is not valid for this configuration\n\r");
	return XST_FAILURE;
}

/*****************************************************************************/
/**
 * Start parking mode on a certain frame
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param FrameIndex is the frame to park on
 * @param Direction is the channel to work on, use XAXIVDMA_READ/WRITE
 *
 * @return
 *  - XST_SUCCESS if everything is fine
 *  - XST_INVALID_PARAM if
 *    . channel is invalid
 *    . FrameIndex is invalid
 *    . Direction is invalid
 *****************************************************************************/
int XAxiVdma_StartParking(XAxiVdma *InstancePtr, int FrameIndex,
         u16 Direction)
{
	XAxiVdma_Channel *Channel;
	u32 FrmBits;
	u32 RegValue;
	int Status;

	if (FrameIndex > XAXIVDMA_FRM_MAX) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Invalid frame to park on %d\r\n", FrameIndex);

		return XST_INVALID_PARAM;
	}

	if (Direction == XAXIVDMA_READ) {
		FrmBits = FrameIndex &
			XAXIVDMA_PARKPTR_READREF_MASK;

		RegValue = XAxiVdma_ReadReg(InstancePtr->BaseAddr,
		              XAXIVDMA_PARKPTR_OFFSET);

		RegValue &= ~XAXIVDMA_PARKPTR_READREF_MASK;

		RegValue |= FrmBits;

		XAxiVdma_WriteReg(InstancePtr->BaseAddr,
			    XAXIVDMA_PARKPTR_OFFSET, RegValue);
		}
	else if (Direction == XAXIVDMA_WRITE) {
		FrmBits = FrameIndex << XAXIVDMA_WRTREF_SHIFT;

		FrmBits &= XAXIVDMA_PARKPTR_WRTREF_MASK;

		RegValue = XAxiVdma_ReadReg(InstancePtr->BaseAddr,
		              XAXIVDMA_PARKPTR_OFFSET);

		RegValue &= ~XAXIVDMA_PARKPTR_WRTREF_MASK;

		RegValue |= FrmBits;

		XAxiVdma_WriteReg(InstancePtr->BaseAddr,
		    XAXIVDMA_PARKPTR_OFFSET, RegValue);
	}
	else {
		/* Invalid direction, do nothing
		 */
		return XST_INVALID_PARAM;
	}

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (Channel->IsValid) {
		Status = XAxiVdma_ChannelStartParking(Channel);
		if (Status != XST_SUCCESS) {
			xdbg_printf(XDBG_DEBUG_ERROR,
			    "Failed to start channel %x\r\n",
			    (unsigned int)Channel);

			return XST_FAILURE;
		}
	}

	return XST_SUCCESS;
}

/*****************************************************************************/
/**
 * Exit parking mode, the channel will return to circular buffer mode
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the channel to work on, use XAXIVDMA_READ/WRITE
 *
 * @return
 *   None
 *
 * @note
 * If channel is invalid, then do nothing
 *****************************************************************************/
void XAxiVdma_StopParking(XAxiVdma *InstancePtr, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		return;
	}

	if (Channel->IsValid) {
		XAxiVdma_ChannelStopParking(Channel);
	}

	return;
}

/*****************************************************************************/
/**
 * Start frame count enable on one channel
 *
 * This is needed to start limiting the number of frames to transfer so that
 * software can check the data etc after hardware stops transfer.
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the channel to work on, use XAXIVDMA_READ/WRITE
 *
 * @return
 *   None
 *
 *****************************************************************************/
void XAxiVdma_StartFrmCntEnable(XAxiVdma *InstancePtr, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (Channel->IsValid) {
		XAxiVdma_ChannelStartFrmCntEnable(Channel);
	}
}

/*****************************************************************************/
/**
 * Set BD addresses to be different.
 *
 * In some systems, it is convenient to put BDs into a certain region of the
 * memory. This function enables that.
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param BdAddrPhys is the physical starting address for BDs
 * @param BdAddrVirt is the Virtual starting address for BDs. For systems that
 *         do not use MMU, then virtual address is the same as physical address
 * @param NumBds is the number of BDs to setup with. This is required to be
 *        the same as the number of frame stores for that channel
 * @param Direction is the channel direction
 *
 * @return
 * - XST_SUCCESS for a successful setup
 * - XST_DEVICE_BUSY if the DMA channel is not idle, BDs are still being used
 * - XST_INVALID_PARAM if parameters not valid
 * - XST_DEVICE_NOT_FOUND if the channel is invalid
 *
 * @notes
 * We assume that the memory region starting from BdAddrPhys and BdAddrVirt are
 * large enough to hold all the BDs.
 *****************************************************************************/
int XAxiVdma_SetBdAddrs(XAxiVdma *InstancePtr, u32 BdAddrPhys, u32 BdAddrVirt,
         int NumBds, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (Channel->IsValid) {
		if (NumBds != Channel->AllCnt) {
			return XST_INVALID_PARAM;
		}

		if (BdAddrPhys & (XAXIVDMA_BD_MINIMUM_ALIGNMENT - 1)) {
			return XST_INVALID_PARAM;
		}

		if (BdAddrVirt & (XAXIVDMA_BD_MINIMUM_ALIGNMENT - 1)) {
			return XST_INVALID_PARAM;
		}

		return XAxiVdma_ChannelSetBdAddrs(Channel, BdAddrPhys, BdAddrVirt);
	}
	else {
		return XST_DEVICE_NOT_FOUND;
	}
}

/*****************************************************************************/
/**
 * Start a write operation
 *
 * Write corresponds to send data from device to memory
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param DmaConfigPtr is the pointer to the setup structure
 *
 * @return
 * - XST_SUCCESS for a successful submission
 * - XST_DEVICE_BUSY if the DMA channel is not idle, BDs are still being used
 * - XST_INVAID_PARAM if parameters in config structure not valid
 * - XST_DEVICE_NOT_FOUND if the channel is invalid
 *
 *****************************************************************************/
int XAxiVdma_StartWriteFrame(XAxiVdma *InstancePtr,
    XAxiVdma_DmaSetup *DmaConfigPtr)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, XAXIVDMA_WRITE);

	if (Channel->IsValid) {
		return XAxiVdma_ChannelStartTransfer(Channel,
		    (XAxiVdma_ChannelSetup *)DmaConfigPtr);
	}
	else {
		return XST_DEVICE_NOT_FOUND;
	}
}

/*****************************************************************************/
/**
 * Start a read operation
 *
 * Read corresponds to send data from memory to device
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param DmaConfigPtr is the pointer to the setup structure
 *
 * @return
 * - XST_SUCCESS for a successful submission
 * - XST_DEVICE_BUSY if the DMA channel is not idle, BDs are still being used
 * - XST_INVAID_PARAM if parameters in config structure not valid
 * - XST_DEVICE_NOT_FOUND if the channel is invalid
 *
 *****************************************************************************/
int XAxiVdma_StartReadFrame(XAxiVdma *InstancePtr,
        XAxiVdma_DmaSetup *DmaConfigPtr)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, XAXIVDMA_READ);

	if (Channel->IsValid) {
		return XAxiVdma_ChannelStartTransfer(Channel,
		    (XAxiVdma_ChannelSetup *)DmaConfigPtr);
	}
	else {
		return XST_DEVICE_NOT_FOUND;
	}
}

/*****************************************************************************/
/**
 * Configure one DMA channel using the configuration structure
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the DMA channel to work on
 * @param DmaConfigPtr is the pointer to the setup structure
 *
 * @return
 * - XST_SUCCESS if successful
 * - XST_DEVICE_BUSY if the DMA channel is not idle, BDs are still being used
 * - XST_INVAID_PARAM if buffer address not valid, for example, unaligned
 *   address with no DRE built in the hardware, or Direction invalid
 * - XST_DEVICE_NOT_FOUND if the channel is invalid
 *
 *****************************************************************************/
int XAxiVdma_DmaConfig(XAxiVdma *InstancePtr, u16 Direction,
        XAxiVdma_DmaSetup *DmaConfigPtr)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		return XST_INVALID_PARAM;
	}


	if (Channel->IsValid) {

		return XAxiVdma_ChannelConfig(Channel,
		    (XAxiVdma_ChannelSetup *)DmaConfigPtr);
	}
	else {
		return XST_DEVICE_NOT_FOUND;
	}
}

/*****************************************************************************/
/**
 * Configure buffer addresses for one DMA channel
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the DMA channel to work on
 * @param BufferAddrSet is the set of addresses for the transfers
 *
 * @return
 * - XST_SUCCESS if successful
 * - XST_DEVICE_BUSY if the DMA channel is not idle, BDs are still being used
 * - XST_INVAID_PARAM if buffer address not valid, for example, unaligned
 *   address with no DRE built in the hardware, or Direction invalid
 * - XST_DEVICE_NOT_FOUND if the channel is invalid
 *
 *****************************************************************************/
int XAxiVdma_DmaSetBufferAddr(XAxiVdma *InstancePtr, u16 Direction,
        UINTPTR *BufferAddrSet)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		return XST_INVALID_PARAM;
	}

	if (Channel->IsValid) {
		return XAxiVdma_ChannelSetBufferAddr(Channel, BufferAddrSet,
		    Channel->NumFrames);
	}
	else {
		return XST_DEVICE_NOT_FOUND;
	}
}

/*****************************************************************************/
/**
 * Start one DMA channel
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the DMA channel to work on
 *
 * @return
 * - XST_SUCCESS if channel started successfully
 * - XST_FAILURE otherwise
 * - XST_DEVICE_NOT_FOUND if the channel is invalid
 * - XST_INVALID_PARAM if Direction invalid
 *
 *****************************************************************************/
int XAxiVdma_DmaStart(XAxiVdma *InstancePtr, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		return XST_INVALID_PARAM;
	}

	if (Channel->IsValid) {
		return XAxiVdma_ChannelStart(Channel);
	}
	else {
		return XST_DEVICE_NOT_FOUND;
	}
}

/*****************************************************************************/
/**
 * Stop one DMA channel
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the DMA channel to work on
 *
 * @return
 *  None
 *
 * @note
 * If channel is invalid, then do nothing on that channel
 *****************************************************************************/
void XAxiVdma_DmaStop(XAxiVdma *InstancePtr, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		return;
	}

	if (Channel->IsValid) {
		XAxiVdma_ChannelStop(Channel);
	}

	return;
}

/*****************************************************************************/
/**
 * Dump registers of one DMA channel
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the DMA channel to work on
 *
 * @return
 *  None
 *
 * @note
 * If channel is invalid, then do nothing on that channel
 *****************************************************************************/
void XAxiVdma_DmaRegisterDump(XAxiVdma *InstancePtr, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		return;
	}

	if (Channel->IsValid) {
		XAxiVdma_ChannelRegisterDump(Channel);
	}

	return;
}

/*****************************************************************************/
/**
 * Set the frame counter and delay counter for both channels
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param CfgPtr is the pointer to the configuration structure
 *
 * @return
 *   - XST_SUCCESS if setup finishes successfully
 *   - XST_INVALID_PARAM if the configuration structure has invalid values
 *   - Others if setting channel frame counter fails
 *
 * @note
 * If channel is invalid, then do nothing on that channel
 *****************************************************************************/
int XAxiVdma_SetFrameCounter(XAxiVdma *InstancePtr,
        XAxiVdma_FrameCounter *CfgPtr)
{
	int Status;
	XAxiVdma_Channel *Channel;

	/* Validate parameters */
	Xil_AssertNonvoid(InstancePtr != NULL);
	Xil_AssertNonvoid(InstancePtr->IsReady == XAXIVDMA_DEVICE_READY);
	Xil_AssertNonvoid(CfgPtr != NULL);

	if ((CfgPtr->ReadFrameCount == 0) ||
	    (CfgPtr->WriteFrameCount == 0)) {

		return XST_INVALID_PARAM;
	}

	Channel = XAxiVdma_GetChannel(InstancePtr, XAXIVDMA_READ);

	if (Channel->IsValid) {

		Status = XAxiVdma_ChannelSetFrmCnt(Channel, CfgPtr->ReadFrameCount,
				    CfgPtr->ReadDelayTimerCount);
		if (Status != XST_SUCCESS) {
			xdbg_printf(XDBG_DEBUG_ERROR,
			    "Setting read channel frame counter "
			    "failed with %d\r\n", Status);

			return Status;
		}
	}

	Channel = XAxiVdma_GetChannel(InstancePtr, XAXIVDMA_WRITE);

	if (Channel->IsValid) {

		Status = XAxiVdma_ChannelSetFrmCnt(Channel,
		          CfgPtr->WriteFrameCount,
			      CfgPtr->WriteDelayTimerCount);
		if (Status != XST_SUCCESS) {
			xdbg_printf(XDBG_DEBUG_ERROR,
			    "Setting write channel frame counter "
			    "failed with %d\r\n", Status);

			return Status;
		}
	}

	return XST_SUCCESS;
}

/*****************************************************************************/
/**
 * Get the frame counter and delay counter for both channels
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param CfgPtr is the configuration structure to contain return values
 *
 * @return
 *  None
 *
 * @note
 * If returned frame counter value is 0, then the channel is not valid
 *****************************************************************************/
void XAxiVdma_GetFrameCounter(XAxiVdma *InstancePtr,
        XAxiVdma_FrameCounter *CfgPtr)
{
	XAxiVdma_Channel *Channel;
	u8 FrmCnt;
	u8 DlyCnt;

	/* Validate parameters */
	Xil_AssertVoid(InstancePtr != NULL);
	Xil_AssertVoid(InstancePtr->IsReady == XAXIVDMA_DEVICE_READY);
	Xil_AssertVoid(CfgPtr != NULL);

	/* Use a zero frame counter value to indicate failure
	 */
	FrmCnt = 0;

	Channel = XAxiVdma_GetChannel(InstancePtr, XAXIVDMA_READ);

	if (Channel->IsValid) {
		XAxiVdma_ChannelGetFrmCnt(Channel, &FrmCnt, &DlyCnt);
	}

	CfgPtr->ReadFrameCount = FrmCnt;
	CfgPtr->ReadDelayTimerCount = DlyCnt;

	/* Use a zero frame counter value to indicate failure
	 */
	FrmCnt = 0;

	Channel = XAxiVdma_GetChannel(InstancePtr, XAXIVDMA_WRITE);

	if (Channel->IsValid) {
		XAxiVdma_ChannelGetFrmCnt(Channel, &FrmCnt, &DlyCnt);
	}

	CfgPtr->WriteFrameCount = FrmCnt;
	CfgPtr->WriteDelayTimerCount = DlyCnt;

	return;
}

/*****************************************************************************/
/**
 * Set the number of frame store buffers to use.
 *
 * @param 	InstancePtr is the XAxiVdma instance to operate on
 * @param 	FrmStoreNum is the number of frame store buffers to use.
 * @param	Direction is the channel to work on, use XAXIVDMA_READ/WRITE
 *
 * @return	- XST_SUCCESS if operation is successful
 *		- XST_FAILURE if operation fails.
 *		- XST_NO_FEATURE if access to FrameStore register is disabled
 * @note	None
 *
 *****************************************************************************/
int XAxiVdma_SetFrmStore(XAxiVdma *InstancePtr, u8 FrmStoreNum, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	if(FrmStoreNum > InstancePtr->MaxNumFrames) {
		return XST_FAILURE;
	}

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		return XST_FAILURE;
	}

	if(XAxiVdma_ChannelIsRunning(Channel)) {
		xdbg_printf(XDBG_DEBUG_ERROR, "Cannot set frame store..."
						"channel is running\r\n");
		return XST_FAILURE;
	}

	if (!(Channel->DbgFeatureFlags & XAXIVDMA_ENABLE_DBG_FRMSTORE_REG)) {
		xdbg_printf(XDBG_DEBUG_ERROR,
			"Frame Store Register is disabled\n\r");
		return XST_NO_FEATURE;
	}

	XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_FRMSTORE_OFFSET,
	    FrmStoreNum & XAXIVDMA_FRMSTORE_MASK);

	Channel->NumFrames = FrmStoreNum;

	XAxiVdma_ChannelInit(Channel);

	return XST_SUCCESS;

}

/*****************************************************************************/
/**
 * Get the number of frame store buffers to use.
 *
 * @param 	InstancePtr is the XAxiVdma instance to operate on
 * @param 	FrmStoreNum is the number of frame store buffers to use.
 * @param	Direction is the channel to work on, use XAXIVDMA_READ/WRITE
 *
 * @return	None
 *
 * @note	None
 *
 *****************************************************************************/
void XAxiVdma_GetFrmStore(XAxiVdma *InstancePtr, u8 *FrmStoreNum,
				u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		return;
	}

	if (Channel->DbgFeatureFlags & XAXIVDMA_ENABLE_DBG_FRMSTORE_REG) {
		*FrmStoreNum = (XAxiVdma_ReadReg(Channel->ChanBase,
			XAXIVDMA_FRMSTORE_OFFSET)) & XAXIVDMA_FRMSTORE_MASK;
	} else {
		xdbg_printf(XDBG_DEBUG_ERROR,
			"Frame Store Register is disabled\n\r");
	}
}

/*****************************************************************************/
/**
 * Check for DMA Channel Errors.
 *
 * @param 	InstancePtr is the XAxiVdma instance to operate on
 * @param	Direction is the channel to work on, use XAXIVDMA_READ/WRITE
 *
 * @return	- Errors seen on the channel
 *		- XST_INVALID_PARAM, when channel pointer is invalid.
 *		- XST_DEVICE_NOT_FOUND, when the channel is not valid.
 *
 * @note	None
 *
 *****************************************************************************/
int XAxiVdma_GetDmaChannelErrors(XAxiVdma *InstancePtr, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		return XST_INVALID_PARAM;
	}

	if (Channel->IsValid) {
		return XAxiVdma_ChannelErrors(Channel);
	}
	else {
		return XST_DEVICE_NOT_FOUND;
	}
}

/*****************************************************************************/
/**
 * Clear DMA Channel Errors.
 *
 * @param InstancePtr is the XAxiVdma instance to operate on
 * @param Direction is the channel to work on, use XAXIVDMA_READ/WRITE
 * @param ErrorMask is the mask of error bits to clear
 *
 * @return	- XST_SUCCESS, when error bits are cleared.
 *		- XST_INVALID_PARAM, when channel pointer is invalid.
 *		- XST_DEVICE_NOT_FOUND, when the channel is not valid.
 *
 * @note	None
 *
 *****************************************************************************/
int XAxiVdma_ClearDmaChannelErrors(XAxiVdma *InstancePtr, u16 Direction,
					u32 ErrorMask)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		return XST_INVALID_PARAM;
	}

	if (Channel->IsValid) {
		XAxiVdma_ClearChannelErrors(Channel, ErrorMask);
		return XST_SUCCESS;
	}
	else {
		return XST_DEVICE_NOT_FOUND;
	}
}

/*****************************************************************************/
/**
 * Look up the hardware configuration for a device instance
 *
 * @param DeviceId is the unique device ID of the device to lookup for
 *
 * @return
 * The configuration structure for the device. If the device ID is not found,
 * a NULL pointer is returned.
 *
 ******************************************************************************/
XAxiVdma_Config *XAxiVdma_LookupConfig(u16 DeviceId)
{
	extern XAxiVdma_Config XAxiVdma_ConfigTable[];
	XAxiVdma_Config *CfgPtr = NULL;
	u32 i;

	for (i = 0U; i < XPAR_XAXIVDMA_NUM_INSTANCES; i++) {
		if (XAxiVdma_ConfigTable[i].DeviceId == DeviceId) {
			CfgPtr = &XAxiVdma_ConfigTable[i];
			break;
		}
	}

	return CfgPtr;
}

/*****************************************************************************/
/**
 * Enable specific interrupts for a channel
 *
 * Interrupts not specified by the mask will not be affected
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the DMA channel, use XAXIVDMA_READ or XAXIVDMA_WRITE
 * @param IntrType is the bit mask for the interrups to be enabled
 *
 * @return
 *  None
 *
 * @note
 * If channel is invalid, then nothing is done
 *****************************************************************************/
void XAxiVdma_IntrEnable(XAxiVdma *InstancePtr, u32 IntrType, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (Channel->IsValid) {
		XAxiVdma_ChannelEnableIntr(Channel, IntrType);
	}

	return;
}

/*****************************************************************************/
/**
 * Disable specific interrupts for a channel
 *
 * Interrupts not specified by the mask will not be affected
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param IntrType is the bit mask for the interrups to be disabled
 * @param Direction is the DMA channel, use XAXIVDMA_READ or XAXIVDMA_WRITE
 *
 * @return
 *  None
 *
 * @note
 * If channel is invalid, then nothing is done
 *****************************************************************************/
void XAxiVdma_IntrDisable(XAxiVdma *InstancePtr, u32 IntrType, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (Channel->IsValid) {
		XAxiVdma_ChannelDisableIntr(Channel, IntrType);
	}

	return;
}

/*****************************************************************************/
/**
 * Get the pending interrupts of a channel
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the DMA channel, use XAXIVDMA_READ or XAXIVDMA_WRITE
 *
 * @return
 * The bit mask for the currently pending interrupts
 *
 * @note
 * If Direction is invalid, return 0
 *****************************************************************************/
u32 XAxiVdma_IntrGetPending(XAxiVdma *InstancePtr, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "IntrGetPending: invalid direction %d\n\r", Direction);

		return 0;
	}

	if (Channel->IsValid) {
		return XAxiVdma_ChannelGetPendingIntr(Channel);
	}
	else {
		/* An invalid channel has no intr
		 */
		return 0;
	}
}

/*****************************************************************************/
/**
 * Clear the pending interrupts specified by the bit mask
 *
 * Interrupts not specified by the mask will not be affected
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param Direction is the DMA channel, use XAXIVDMA_READ or XAXIVDMA_WRITE
 * @param IntrType is the bit mask for the interrups to be cleared
 *
 * @return
 *  None
 *
 * @note
 * If channel is invalid, then nothing is done
 *****************************************************************************/
void XAxiVdma_IntrClear(XAxiVdma *InstancePtr, u32 IntrType, u16 Direction)
{
	XAxiVdma_Channel *Channel;

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (Channel->IsValid) {
		XAxiVdma_ChannelIntrClear(Channel, IntrType);
	}
	return;
}

/*****************************************************************************/
/**
 * Masks the S2MM error interrupt for the provided error mask value
 *
 * @param	InstancePtr is the XAxiVdma instance to operate on
 * @param	ErrorMask is the mask of error bits for which S2MM error
 *		interrupt can be disabled.
 * @param	Direction is the channel to work on, use XAXIVDMA_READ/WRITE
 *
 * @return	- XST_SUCCESS, when error bits are cleared.
 *		- XST_INVALID_PARAM, when channel pointer is invalid.
 *		- XST_DEVICE_NOT_FOUND, when the channel is not valid.
 *
 * @note	The register S2MM_DMA_IRQ_MASK is only applicable from IPv6.01a
 *		which is added at offset XAXIVDMA_S2MM_DMA_IRQ_MASK_OFFSET.
 *		For older versions, this offset location is reserved and so
 *		the API does not have any effect.
 *
 *****************************************************************************/
int XAxiVdma_MaskS2MMErrIntr(XAxiVdma *InstancePtr, u32 ErrorMask,
					u16 Direction)
{
	XAxiVdma_Channel *Channel;

	if (Direction != XAXIVDMA_WRITE) {
		return XST_INVALID_PARAM;
	}

	Channel = XAxiVdma_GetChannel(InstancePtr, Direction);

	if (!Channel) {
		return XST_INVALID_PARAM;
	}

	if (Channel->IsValid) {
		XAxiVdma_WriteReg(Channel->ChanBase,
			XAXIVDMA_S2MM_DMA_IRQ_MASK_OFFSET,
			ErrorMask & XAXIVDMA_S2MM_IRQ_ERR_ALL_MASK);

		return XST_SUCCESS;
	}

	return XST_DEVICE_NOT_FOUND;
}

/*****************************************************************************/
/**
 * Interrupt handler for the read channel
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 *
 * @return
 *  None
 *
 * @note
 * If the channel is invalid, then no interrupt handling
 *****************************************************************************/
void XAxiVdma_ReadIntrHandler(void * InstancePtr)
{
	XAxiVdma *DmaPtr;
	XAxiVdma_Channel *Channel;
	XAxiVdma_ChannelCallBack *CallBack;
	u32 PendingIntr;

	DmaPtr = (XAxiVdma *)InstancePtr;

	CallBack = &(DmaPtr->ReadCallBack);

	if (!CallBack->CompletionCallBack) {

		return;
	}

	Channel = XAxiVdma_GetChannel(DmaPtr, XAXIVDMA_READ);

	if (!Channel->IsValid) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Read channel is invalid, no intr handling\n\r");

		return;
	}

	PendingIntr = XAxiVdma_ChannelGetPendingIntr(Channel);
	PendingIntr &= XAxiVdma_ChannelGetEnabledIntr(Channel);

	XAxiVdma_ChannelIntrClear(Channel, PendingIntr);

	if (!PendingIntr || (PendingIntr & XAXIVDMA_IXR_ERROR_MASK)) {

		CallBack->ErrCallBack(CallBack->ErrRef,
		    PendingIntr & XAXIVDMA_IXR_ERROR_MASK);

		/* The channel's error callback should reset the channel
		 * There is no need to handle other interrupts
		 */
		return;
	}

	if (PendingIntr & XAXIVDMA_IXR_COMPLETION_MASK) {

		CallBack->CompletionCallBack(CallBack->CompletionRef,
		    PendingIntr);
	}

	return;
}

/*****************************************************************************/
/**
 * Interrupt handler for the write channel
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 *
 * @return
 *  None
 *
 * @note
 * If the channel is invalid, then no interrupt handling
 *****************************************************************************/
void XAxiVdma_WriteIntrHandler(void * InstancePtr)
{
	XAxiVdma *DmaPtr;
	XAxiVdma_Channel *Channel;
	XAxiVdma_ChannelCallBack *CallBack;
	u32 PendingIntr;

	DmaPtr = (XAxiVdma *)InstancePtr;

	Channel = XAxiVdma_GetChannel(DmaPtr, XAXIVDMA_WRITE);

	if (!Channel->IsValid) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Write channel is invalid, no intr handling\n\r");

		return;
	}

	PendingIntr = XAxiVdma_ChannelGetPendingIntr(Channel);
	PendingIntr &= XAxiVdma_ChannelGetEnabledIntr(Channel);

	XAxiVdma_ChannelIntrClear(Channel, PendingIntr);

	CallBack = &(DmaPtr->WriteCallBack);

	if (!CallBack->CompletionCallBack) {

		return;
	}

	if (!PendingIntr || (PendingIntr & XAXIVDMA_IXR_ERROR_MASK)) {

		CallBack->ErrCallBack(CallBack->ErrRef,
		    PendingIntr & XAXIVDMA_IXR_ERROR_MASK);

		/* The channel's error callback should reset the channel
		 * There is no need to handle other interrupts
		 */
		return;
	}

	if (PendingIntr & XAXIVDMA_IXR_COMPLETION_MASK) {

		CallBack->CompletionCallBack(CallBack->CompletionRef,
		    PendingIntr);
	}

	return;
}

/*****************************************************************************/
/**
 * Set call back function and call back reference pointer for one channel
 *
 * @param InstancePtr is the pointer to the DMA engine to work on
 * @param HandlerType is the interrupt type that this callback handles
 * @param CallBackFunc is the call back function pointer
 * @param CallBackRef is the call back reference pointer
 * @param Direction is the DMA channel, use XAXIVDMA_READ or XAXIVDMA_WRITE
 *
 * @return
 * - XST_SUCCESS if everything is fine
 * - XST_INVALID_PARAM if the handler type or direction invalid
 *
 * @note
 * This function overwrites the existing interrupt handler and its reference
 * pointer. The function sets the handlers even if the channels are invalid.
 *****************************************************************************/
int XAxiVdma_SetCallBack(XAxiVdma * InstancePtr, u32 HandlerType,
        void *CallBackFunc, void *CallBackRef, u16 Direction)
{
	XAxiVdma_ChannelCallBack *CallBack;

	Xil_AssertNonvoid(InstancePtr != NULL);
	Xil_AssertNonvoid(InstancePtr->IsReady == XAXIVDMA_DEVICE_READY);

	if ((HandlerType != XAXIVDMA_HANDLER_GENERAL) &&
	    (HandlerType != XAXIVDMA_HANDLER_ERROR)) {

		return XST_INVALID_PARAM;
	}

	if (Direction == XAXIVDMA_READ) {
		CallBack = &(InstancePtr->ReadCallBack);
	}
	else {
		CallBack = &(InstancePtr->WriteCallBack);
	}

	switch (HandlerType) {
	case XAXIVDMA_HANDLER_GENERAL:
		CallBack->CompletionCallBack = (XAxiVdma_CallBack)CallBackFunc;
		CallBack->CompletionRef = CallBackRef;
		break;

	case XAXIVDMA_HANDLER_ERROR:
		CallBack->ErrCallBack = (XAxiVdma_ErrorCallBack)CallBackFunc;
		CallBack->ErrRef = CallBackRef;
		break;

	default:
		return XST_INVALID_PARAM;
	}

	return XST_SUCCESS;
}

/*****************************************************************************/
/*
 * Translate virtual address to physical address
 *
 * When port this driver to other RTOS, please change this definition to
 * be consistent with your target system.
 *
 * @param VirtAddr is the virtual address to work on
 *
 * @return
 *   The physical address of the virtual address
 *
 * @note
 *   The virtual address and the physical address are the same here.
 *
 *****************************************************************************/
#define XAXIVDMA_VIRT_TO_PHYS(VirtAddr) \
	(VirtAddr)

/*****************************************************************************/
/**
 * Set the channel to enable access to higher Frame Buffer Addresses (SG=0)
 *
 * @param Channel is the pointer to the channel to work on
 *
 *
 *****************************************************************************/
#define XAxiVdma_ChannelHiFrmAddrEnable(Channel) \
{ \
	XAxiVdma_WriteReg(Channel->ChanBase, \
			XAXIVDMA_HI_FRMBUF_OFFSET, XAXIVDMA_REGINDEX_MASK); \
}

/*****************************************************************************/
/**
 * Set the channel to disable access higher Frame Buffer Addresses (SG=0)
 *
 * @param Channel is the pointer to the channel to work on
 *
 *
 *****************************************************************************/
#define XAxiVdma_ChannelHiFrmAddrDisable(Channel) \
{ \
	XAxiVdma_WriteReg(Channel->ChanBase, \
		XAXIVDMA_HI_FRMBUF_OFFSET, (XAXIVDMA_REGINDEX_MASK >> 1)); \
}

/*****************************************************************************/
/**
 * Initialize a channel of a DMA engine
 *
 * This function initializes the BD ring for this channel
 *
 * @param Channel is the pointer to the DMA channel to work on
 *
 * @return
 *   None
 *
 *****************************************************************************/
void XAxiVdma_ChannelInit(XAxiVdma_Channel *Channel)
{
	int i;
	int NumFrames;
	XAxiVdma_Bd *FirstBdPtr = &(Channel->BDs[0]);
	XAxiVdma_Bd *LastBdPtr;

	/* Initialize the BD variables, so proper memory management
	 * can be done
	 */
	NumFrames = Channel->NumFrames;
	Channel->IsValid = 0;
	Channel->HeadBdPhysAddr = 0;
	Channel->HeadBdAddr = 0;
	Channel->TailBdPhysAddr = 0;
	Channel->TailBdAddr = 0;

	LastBdPtr = &(Channel->BDs[NumFrames - 1]);

	/* Setup the BD ring
	 */
	memset((void *)FirstBdPtr, 0, NumFrames * sizeof(XAxiVdma_Bd));

	for (i = 0; i < NumFrames; i++) {
		XAxiVdma_Bd *BdPtr;
		XAxiVdma_Bd *NextBdPtr;

		BdPtr = &(Channel->BDs[i]);

		/* The last BD connects to the first BD
		 */
		if (i == (NumFrames - 1)) {
			NextBdPtr = FirstBdPtr;
		}
		else {
			NextBdPtr = &(Channel->BDs[i + 1]);
		}

		XAxiVdma_BdSetNextPtr(BdPtr,
				XAXIVDMA_VIRT_TO_PHYS((UINTPTR)NextBdPtr));
	}

	Channel->AllCnt = NumFrames;

	/* Setup the BD addresses so that access the head/tail BDs fast
	 *
	 */
	Channel->HeadBdAddr = (UINTPTR)FirstBdPtr;
	Channel->HeadBdPhysAddr = XAXIVDMA_VIRT_TO_PHYS((UINTPTR)FirstBdPtr);

	Channel->TailBdAddr = (UINTPTR)LastBdPtr;
	Channel->TailBdPhysAddr = XAXIVDMA_VIRT_TO_PHYS((UINTPTR)LastBdPtr);


	Channel->IsValid = 1;

	return;
}

/*****************************************************************************/
/**
 * This function checks whether reset operation is done
 *
 * @param Channel is the pointer to the DMA channel to work on
 *
 * @return
 * - 0 if reset is done
 * - 1 if reset is still going
 *
 *****************************************************************************/
int XAxiVdma_ChannelResetNotDone(XAxiVdma_Channel *Channel)
{
	return (XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET) &
	        XAXIVDMA_CR_RESET_MASK);
}

/*****************************************************************************/
/**
 * This function resets one DMA channel
 *
 * The registers will be default values after the reset
 *
 * @param Channel is the pointer to the DMA channel to work on
 *
 * @return
 *  None
 *
 *****************************************************************************/
void XAxiVdma_ChannelReset(XAxiVdma_Channel *Channel)
{
	XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET,
	    XAXIVDMA_CR_RESET_MASK);

	return;
}

/*****************************************************************************/
/*
 * Check whether a DMA channel is running
 *
 * @param Channel is the pointer to the channel to work on
 *
 * @return
 * - non zero if the channel is running
 * - 0 is the channel is idle
 *
 *****************************************************************************/
int XAxiVdma_ChannelIsRunning(XAxiVdma_Channel *Channel)
{
	u32 Bits;

	/* If halted bit set, channel is not running
	 */
	Bits = XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_SR_OFFSET) &
	          XAXIVDMA_SR_HALTED_MASK;

	if (Bits) {
		return 0;
	}

	/* If Run/Stop bit low, then channel is not running
	 */
	Bits = XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET) &
	          XAXIVDMA_CR_RUNSTOP_MASK;

	if (!Bits) {
		return 0;
	}

	return 1;
}

/*****************************************************************************/
/**
 * Check whether a DMA channel is busy
 *
 * @param Channel is the pointer to the channel to work on
 *
 * @return
 * - non zero if the channel is busy
 * - 0 is the channel is idle
 *
 *****************************************************************************/
int XAxiVdma_ChannelIsBusy(XAxiVdma_Channel *Channel)
{
	u32 Bits;

	/* If the channel is idle, then it is not busy
	 */
	Bits = XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_SR_OFFSET) &
	          XAXIVDMA_SR_IDLE_MASK;

	if (Bits) {
		return 0;
	}

	/* If the channel is halted, then it is not busy
	 */
	Bits = XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_SR_OFFSET) &
	          XAXIVDMA_SR_HALTED_MASK;

	if (Bits) {
		return 0;
	}

	/* Otherwise, it is busy
	 */
	return 1;
}

/*****************************************************************************/
/*
 * Check DMA channel errors
 *
 * @param Channel is the pointer to the channel to work on
 *
 * @return
 *  	Error bits of the channel, 0 means no errors
 *
 *****************************************************************************/
u32 XAxiVdma_ChannelErrors(XAxiVdma_Channel *Channel)
{
	return (XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_SR_OFFSET)
			& XAXIVDMA_SR_ERR_ALL_MASK);
}

/*****************************************************************************/
/*
 * Clear DMA channel errors
 *
 * @param Channel is the pointer to the channel to work on
 * @param ErrorMask is the mask of error bits to clear.
 *
 * @return
 *  	None
 *
 *****************************************************************************/
void XAxiVdma_ClearChannelErrors(XAxiVdma_Channel *Channel, u32 ErrorMask)
{
	u32 SrBits;

	/* Write on Clear bits */
        SrBits = XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_SR_OFFSET)
                        | ErrorMask;

	XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_SR_OFFSET,
	    SrBits);

	return;
}

/*****************************************************************************/
/**
 * Get the current status of a channel
 *
 * @param Channel is the pointer to the channel to work on
 *
 * @return
 * The status of the channel
 *
 *****************************************************************************/
u32 XAxiVdma_ChannelGetStatus(XAxiVdma_Channel *Channel)
{
	return XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_SR_OFFSET);
}

/*****************************************************************************/
/**
 * Set the channel to run in parking mode
 *
 * @param Channel is the pointer to the channel to work on
 *
 * @return
 *   - XST_SUCCESS if everything is fine
 *   - XST_FAILURE if hardware is not running
 *
 *****************************************************************************/
int XAxiVdma_ChannelStartParking(XAxiVdma_Channel *Channel)
{
	u32 CrBits;

	if (!XAxiVdma_ChannelIsRunning(Channel)) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Channel is not running, cannot start park mode\r\n");

		return XST_FAILURE;
	}

	CrBits = XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET) &
	            ~XAXIVDMA_CR_TAIL_EN_MASK;

	XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET,
	    CrBits);

	return XST_SUCCESS;
}

/*****************************************************************************/
/**
 * Set the channel to run in circular mode, exiting parking mode
 *
 * @param Channel is the pointer to the channel to work on
 *
 * @return
 *   None
 *
 *****************************************************************************/
void XAxiVdma_ChannelStopParking(XAxiVdma_Channel *Channel)
{
	u32 CrBits;

	CrBits = XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET) |
	            XAXIVDMA_CR_TAIL_EN_MASK;

	XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET,
	    CrBits);

	return;
}

/*****************************************************************************/
/**
 * Set the channel to run in frame count enable mode
 *
 * @param Channel is the pointer to the channel to work on
 *
 * @return
 *   None
 *
 *****************************************************************************/
void XAxiVdma_ChannelStartFrmCntEnable(XAxiVdma_Channel *Channel)
{
	u32 CrBits;

	CrBits = XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET) |
	            XAXIVDMA_CR_FRMCNT_EN_MASK;

	XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET,
	    CrBits);

	return;
}

/*****************************************************************************/
/**
 * Setup BD addresses to a different memory region
 *
 * In some systems, it is convenient to put BDs into a certain region of the
 * memory. This function enables that.
 *
 * @param Channel is the pointer to the channel to work on
 * @param BdAddrPhys is the physical starting address for BDs
 * @param BdAddrVirt is the Virtual starting address for BDs. For systems that
 *         do not use MMU, then virtual address is the same as physical address
 *
 * @return
 * - XST_SUCCESS for a successful setup
 * - XST_DEVICE_BUSY if the DMA channel is not idle, BDs are still being used
 *
 * @notes
 * We assume that the memory region starting from BdAddrPhys is large enough
 * to hold all the BDs.
 *
 *****************************************************************************/
int XAxiVdma_ChannelSetBdAddrs(XAxiVdma_Channel *Channel, UINTPTR BdAddrPhys,
		UINTPTR BdAddrVirt)
{
	int NumFrames = Channel->AllCnt;
	int i;
	UINTPTR NextPhys = BdAddrPhys;
	UINTPTR CurrVirt = BdAddrVirt;

	if (Channel->HasSG && XAxiVdma_ChannelIsBusy(Channel)) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Channel is busy, cannot setup engine for transfer\r\n");

		return XST_DEVICE_BUSY;
	}

	memset((void *)BdAddrPhys, 0, NumFrames * sizeof(XAxiVdma_Bd));
	memset((void *)BdAddrVirt, 0, NumFrames * sizeof(XAxiVdma_Bd));

	/* Set up the BD link list */
	for (i = 0; i < NumFrames; i++) {
		XAxiVdma_Bd *BdPtr;

		BdPtr = (XAxiVdma_Bd *)CurrVirt;

		/* The last BD connects to the first BD
		 */
		if (i == (NumFrames - 1)) {
			NextPhys = BdAddrPhys;
		}
		else {
			NextPhys += sizeof(XAxiVdma_Bd);
		}

		XAxiVdma_BdSetNextPtr(BdPtr, NextPhys);
		CurrVirt += sizeof(XAxiVdma_Bd);
	}

	/* Setup the BD addresses so that access the head/tail BDs fast
	 *
	 */
	Channel->HeadBdPhysAddr = BdAddrPhys;
	Channel->HeadBdAddr = BdAddrVirt;
	Channel->TailBdPhysAddr = BdAddrPhys +
	                          (NumFrames - 1) * sizeof(XAxiVdma_Bd);
	Channel->TailBdAddr = BdAddrVirt +
	                          (NumFrames - 1) * sizeof(XAxiVdma_Bd);

	return XST_SUCCESS;
}

/*****************************************************************************/
/**
 * Start a transfer
 *
 * This function setup the DMA engine and start the engine to do the transfer.
 *
 * @param Channel is the pointer to the channel to work on
 * @param ChannelCfgPtr is the pointer to the setup structure
 *
 * @return
 * - XST_SUCCESS for a successful submission
 * - XST_FAILURE if channel has not being initialized
 * - XST_DEVICE_BUSY if the DMA channel is not idle, BDs are still being used
 * - XST_INVAID_PARAM if parameters in config structure not valid
 *
 *****************************************************************************/
int XAxiVdma_ChannelStartTransfer(XAxiVdma_Channel *Channel,
    XAxiVdma_ChannelSetup *ChannelCfgPtr)
{
	int Status;

	if (!Channel->IsValid) {
		xdbg_printf(XDBG_DEBUG_ERROR, "Channel not initialized\r\n");

		return XST_FAILURE;
	}

	if (Channel->HasSG && XAxiVdma_ChannelIsBusy(Channel)) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Channel is busy, cannot setup engine for transfer\r\n");

		return XST_DEVICE_BUSY;
	}

	Status = XAxiVdma_ChannelConfig(Channel, ChannelCfgPtr);
	if (Status != XST_SUCCESS) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Channel config failed %d\r\n", Status);

		return Status;
	}

	Status = XAxiVdma_ChannelSetBufferAddr(Channel,
	    ChannelCfgPtr->FrameStoreStartAddr, Channel->AllCnt);
	if (Status != XST_SUCCESS) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Channel setup buffer addr failed %d\r\n", Status);

		return Status;
	}

	Status = XAxiVdma_ChannelStart(Channel);
	if (Status != XST_SUCCESS) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Channel start failed %d\r\n", Status);

		return Status;
	}

	return XST_SUCCESS;
}

/*****************************************************************************/
/**
 * Configure one DMA channel using the configuration structure
 *
 * Setup the control register and BDs, however, BD addresses are not set.
 *
 * @param Channel is the pointer to the channel to work on
 * @param ChannelCfgPtr is the pointer to the setup structure
 *
 * @return
 * - XST_SUCCESS if successful
 * - XST_FAILURE if channel has not being initialized
 * - XST_DEVICE_BUSY if the DMA channel is not idle
 * - XST_INVALID_PARAM if fields in ChannelCfgPtr is not valid
 *
 *****************************************************************************/
int XAxiVdma_ChannelConfig(XAxiVdma_Channel *Channel,
        XAxiVdma_ChannelSetup *ChannelCfgPtr)
{
	u32 CrBits;
	int i;
	int NumBds;
	int Status;
	u32 hsize_align;
	u32 stride_align;

	if (!Channel->IsValid) {
		xdbg_printf(XDBG_DEBUG_ERROR, "Channel not initialized\r\n");

		return XST_FAILURE;
	}

	if (Channel->HasSG && XAxiVdma_ChannelIsBusy(Channel)) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Channel is busy, cannot config!\r\n");

		return XST_DEVICE_BUSY;
	}

	Channel->Vsize = ChannelCfgPtr->VertSizeInput;

	/* Check whether Hsize is properly aligned */
	if (Channel->direction == XAXIVDMA_WRITE) {
		if (ChannelCfgPtr->HoriSizeInput < Channel->WordLength) {
			hsize_align = (u32)Channel->WordLength;
		} else {
			hsize_align =
				(u32)(ChannelCfgPtr->HoriSizeInput % Channel->WordLength);
			if (hsize_align > 0)
				hsize_align = (Channel->WordLength - hsize_align);
		}
	} else {
		if (ChannelCfgPtr->HoriSizeInput < Channel->WordLength) {
			hsize_align = (u32)Channel->WordLength;
		} else {
			hsize_align =
				(u32)(ChannelCfgPtr->HoriSizeInput % Channel->StreamWidth);
			if (hsize_align > 0)
				hsize_align = (Channel->StreamWidth - hsize_align);
		}
	}

	/* Check whether Stride is properly aligned */
	if (ChannelCfgPtr->Stride < Channel->WordLength) {
		stride_align = (u32)Channel->WordLength;
	} else {
		stride_align = (u32)(ChannelCfgPtr->Stride % Channel->WordLength);
		if (stride_align > 0)
			stride_align = (Channel->WordLength - stride_align);
	}

	/* If hardware has no DRE, then Hsize and Stride must
	 * be word-aligned
	 */
	if (!Channel->HasDRE) {
		if (hsize_align != 0) {
			/* Adjust hsize to multiples of stream/mm data width*/
			ChannelCfgPtr->HoriSizeInput += hsize_align;
		}
		if (stride_align != 0) {
			/* Adjust stride to multiples of stream/mm data width*/
			ChannelCfgPtr->Stride += stride_align;
		}
	}

	Channel->Hsize = ChannelCfgPtr->HoriSizeInput;

	CrBits = XAxiVdma_ReadReg(Channel->ChanBase,
	     XAXIVDMA_CR_OFFSET);

	CrBits = XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET) &
	    ~(XAXIVDMA_CR_TAIL_EN_MASK | XAXIVDMA_CR_SYNC_EN_MASK |
	      XAXIVDMA_CR_FRMCNT_EN_MASK | XAXIVDMA_CR_RD_PTR_MASK);

	if (ChannelCfgPtr->EnableCircularBuf) {
		CrBits |= XAXIVDMA_CR_TAIL_EN_MASK;
	}
	else {
		/* Park mode */
		u32 FrmBits;
		u32 RegValue;

		if ((!XAxiVdma_ChannelIsRunning(Channel)) &&
		    Channel->HasSG) {
			xdbg_printf(XDBG_DEBUG_ERROR,
			    "Channel is not running, cannot set park mode\r\n");

			return XST_INVALID_PARAM;
		}

		if (ChannelCfgPtr->FixedFrameStoreAddr > XAXIVDMA_FRM_MAX) {
			xdbg_printf(XDBG_DEBUG_ERROR,
			    "Invalid frame to park on %d\r\n",
			    ChannelCfgPtr->FixedFrameStoreAddr);

			return XST_INVALID_PARAM;
		}

		if (Channel->IsRead) {
			FrmBits = ChannelCfgPtr->FixedFrameStoreAddr &
			              XAXIVDMA_PARKPTR_READREF_MASK;

			RegValue = XAxiVdma_ReadReg(Channel->InstanceBase,
			              XAXIVDMA_PARKPTR_OFFSET);

			RegValue &= ~XAXIVDMA_PARKPTR_READREF_MASK;

			RegValue |= FrmBits;

			XAxiVdma_WriteReg(Channel->InstanceBase,
			    XAXIVDMA_PARKPTR_OFFSET, RegValue);
		}
		else {
			FrmBits = ChannelCfgPtr->FixedFrameStoreAddr <<
			            XAXIVDMA_WRTREF_SHIFT;

			FrmBits &= XAXIVDMA_PARKPTR_WRTREF_MASK;

			RegValue = XAxiVdma_ReadReg(Channel->InstanceBase,
			              XAXIVDMA_PARKPTR_OFFSET);

			RegValue &= ~XAXIVDMA_PARKPTR_WRTREF_MASK;

			RegValue |= FrmBits;

			XAxiVdma_WriteReg(Channel->InstanceBase,
			    XAXIVDMA_PARKPTR_OFFSET, RegValue);
		}
	}

	if (ChannelCfgPtr->EnableSync) {
		if (Channel->GenLock != XAXIVDMA_GENLOCK_MASTER)
			CrBits |= XAXIVDMA_CR_SYNC_EN_MASK;
	}

	if (ChannelCfgPtr->GenLockRepeat) {
		if ((Channel->GenLock == XAXIVDMA_GENLOCK_MASTER) ||
			(Channel->GenLock == XAXIVDMA_DYN_GENLOCK_MASTER))
			CrBits |= XAXIVDMA_CR_GENLCK_RPT_MASK;
	}

	if (ChannelCfgPtr->EnableFrameCounter) {
		CrBits |= XAXIVDMA_CR_FRMCNT_EN_MASK;
	}

	CrBits |= (ChannelCfgPtr->PointNum << XAXIVDMA_CR_RD_PTR_SHIFT) &
	    XAXIVDMA_CR_RD_PTR_MASK;

	/* Write the control register value out
	 */
	XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET,
	    CrBits);

	if (Channel->HasVFlip && !Channel->IsRead) {
		u32 RegValue;
		RegValue = XAxiVdma_ReadReg(Channel->InstanceBase,
				XAXIVDMA_VFLIP_OFFSET);
		RegValue &= ~XAXIVDMA_VFLIP_EN_MASK;
		RegValue |= (ChannelCfgPtr->EnableVFlip & XAXIVDMA_VFLIP_EN_MASK);
		XAxiVdma_WriteReg(Channel->InstanceBase, XAXIVDMA_VFLIP_OFFSET,
			RegValue);
	}

	if (Channel->HasSG) {
		/* Setup the information in BDs
		 *
		 * All information is available except the buffer addrs
		 * Buffer addrs are set through XAxiVdma_ChannelSetBufferAddr()
		 */
		NumBds = Channel->AllCnt;

		for (i = 0; i < NumBds; i++) {
			XAxiVdma_Bd *BdPtr = (XAxiVdma_Bd *)(Channel->HeadBdAddr +
			         i * sizeof(XAxiVdma_Bd));

			Status = XAxiVdma_BdSetVsize(BdPtr,
			             ChannelCfgPtr->VertSizeInput);
			if (Status != XST_SUCCESS) {
				xdbg_printf(XDBG_DEBUG_ERROR,
				    "Set vertical size failed %d\r\n", Status);

				return Status;
			}

			Status = XAxiVdma_BdSetHsize(BdPtr,
			    ChannelCfgPtr->HoriSizeInput);
			if (Status != XST_SUCCESS) {
				xdbg_printf(XDBG_DEBUG_ERROR,
				    "Set horizontal size failed %d\r\n", Status);

				return Status;
			}

			Status = XAxiVdma_BdSetStride(BdPtr,
			    ChannelCfgPtr->Stride);
			if (Status != XST_SUCCESS) {
				xdbg_printf(XDBG_DEBUG_ERROR,
				    "Set stride size failed %d\r\n", Status);

				return Status;
			}

			Status = XAxiVdma_BdSetFrmDly(BdPtr,
			ChannelCfgPtr->FrameDelay);
			if (Status != XST_SUCCESS) {
				xdbg_printf(XDBG_DEBUG_ERROR,
				    "Set frame delay failed %d\r\n", Status);

				return Status;
			}
		}
	}
	else {   /* direct register mode */
		if ((ChannelCfgPtr->VertSizeInput > XAXIVDMA_MAX_VSIZE) ||
		    (ChannelCfgPtr->VertSizeInput <= 0) ||
		    (ChannelCfgPtr->HoriSizeInput > XAXIVDMA_MAX_HSIZE) ||
		    (ChannelCfgPtr->HoriSizeInput <= 0) ||
		    (ChannelCfgPtr->Stride > XAXIVDMA_MAX_STRIDE) ||
		    (ChannelCfgPtr->Stride <= 0) ||
		    (ChannelCfgPtr->FrameDelay < 0) ||
		    (ChannelCfgPtr->FrameDelay > XAXIVDMA_FRMDLY_MAX)) {

			return XST_INVALID_PARAM;
		}

		XAxiVdma_WriteReg(Channel->StartAddrBase,
		    XAXIVDMA_HSIZE_OFFSET, ChannelCfgPtr->HoriSizeInput);

		XAxiVdma_WriteReg(Channel->StartAddrBase,
		    XAXIVDMA_STRD_FRMDLY_OFFSET,
		    (ChannelCfgPtr->FrameDelay << XAXIVDMA_FRMDLY_SHIFT) |
		    ChannelCfgPtr->Stride);
	}

	return XST_SUCCESS;
}

/*****************************************************************************/
/**
 * Configure buffer addresses for one DMA channel
 *
 * The buffer addresses are physical addresses.
 * Access to 32 Frame Buffer Addresses in direct mode is done through
 * XAxiVdma_ChannelHiFrmAddrEnable/Disable Functions.
 * 0 - Access Bank0 Registers (0x5C - 0x98)
 * 1 - Access Bank1 Registers (0x5C - 0x98)
 *
 * @param Channel is the pointer to the channel to work on
 * @param BufferAddrSet is the set of addresses for the transfers
 * @param NumFrames is the number of frames to set the address
 *
 * @return
 * - XST_SUCCESS if successful
 * - XST_FAILURE if channel has not being initialized
 * - XST_DEVICE_BUSY if the DMA channel is not idle, BDs are still being used
 * - XST_INVAID_PARAM if buffer address not valid, for example, unaligned
 * address with no DRE built in the hardware
 *
 *****************************************************************************/
int XAxiVdma_ChannelSetBufferAddr(XAxiVdma_Channel *Channel,
        UINTPTR *BufferAddrSet, int NumFrames)
{
	int i;
	u32 WordLenBits;
	int HiFrmAddr = 0;
	int FrmBound;
	if (Channel->AddrWidth > 32) {
		FrmBound = (XAXIVDMA_MAX_FRAMESTORE_64)/2 - 1;
	} else {
		FrmBound = (XAXIVDMA_MAX_FRAMESTORE)/2 - 1;
	}
	int Loop16 = 0;

	if (!Channel->IsValid) {
		xdbg_printf(XDBG_DEBUG_ERROR, "Channel not initialized\r\n");

		return XST_FAILURE;
	}

	WordLenBits = (u32)(Channel->WordLength - 1);

	/* If hardware has no DRE, then buffer addresses must
	 * be word-aligned
	 */
	for (i = 0; i < NumFrames; i++) {
		if (!Channel->HasDRE) {
			if (BufferAddrSet[i] & WordLenBits) {
				xdbg_printf(XDBG_DEBUG_ERROR,
				    "Unaligned address %d: %x without DRE\r\n",
				    i, BufferAddrSet[i]);

				return XST_INVALID_PARAM;
			}
		}
	}

	for (i = 0; i < NumFrames; i++, Loop16++) {
		XAxiVdma_Bd *BdPtr = (XAxiVdma_Bd *)(Channel->HeadBdAddr +
		         i * sizeof(XAxiVdma_Bd));

		if (Channel->HasSG) {
			XAxiVdma_BdSetAddr(BdPtr, BufferAddrSet[i]);
		}
		else {
			if ((i > FrmBound) && !HiFrmAddr) {
				XAxiVdma_ChannelHiFrmAddrEnable(Channel);
				HiFrmAddr = 1;
				Loop16 = 0;
			}

			if (Channel->AddrWidth > 32) {
				/* For a 40-bit address XAXIVDMA_MAX_FRAMESTORE
				 * value should be set to 16 */
				XAxiVdma_WriteReg(Channel->StartAddrBase,
					XAXIVDMA_START_ADDR_OFFSET +
					Loop16 * XAXIVDMA_START_ADDR_LEN + i*4,
					LOWER_32_BITS(BufferAddrSet[i]));

				XAxiVdma_WriteReg(Channel->StartAddrBase,
					XAXIVDMA_START_ADDR_MSB_OFFSET +
					Loop16 * XAXIVDMA_START_ADDR_LEN + i*4,
					UPPER_32_BITS((u64)BufferAddrSet[i]));
			} else {
				XAxiVdma_WriteReg(Channel->StartAddrBase,
					XAXIVDMA_START_ADDR_OFFSET +
					Loop16 * XAXIVDMA_START_ADDR_LEN,
					BufferAddrSet[i]);
			}


			if ((NumFrames > FrmBound) && (i == (NumFrames - 1)))
				XAxiVdma_ChannelHiFrmAddrDisable(Channel);
		}
	}

	return XST_SUCCESS;
}

/*****************************************************************************/
/**
 * Start one DMA channel
 *
 * @param Channel is the pointer to the channel to work on
 *
 * @return
 * - XST_SUCCESS if successful
 * - XST_FAILURE if channel is not initialized
 * - XST_DMA_ERROR if:
 *   . The DMA channel fails to stop
 *   . The DMA channel fails to start
 * - XST_DEVICE_BUSY is the channel is doing transfers
 *
 *****************************************************************************/
int XAxiVdma_ChannelStart(XAxiVdma_Channel *Channel)
{
	u32 CrBits;

	if (!Channel->IsValid) {
		xdbg_printf(XDBG_DEBUG_ERROR, "Channel not initialized\r\n");

		return XST_FAILURE;
	}

	if (Channel->HasSG && XAxiVdma_ChannelIsBusy(Channel)) {

		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Start DMA channel while channel is busy\r\n");

		return XST_DEVICE_BUSY;
	}

	/* If channel is not running, setup the CDESC register and
	 * set the channel to run
	 */
	if (!XAxiVdma_ChannelIsRunning(Channel)) {

		if (Channel->HasSG) {
			/* Set up the current bd register
			 *
			 * Can only setup current bd register when channel is halted
			 */
			XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_CDESC_OFFSET,
			    Channel->HeadBdPhysAddr);
		}

		/* Start DMA hardware
		 */
		CrBits = XAxiVdma_ReadReg(Channel->ChanBase,
		     XAXIVDMA_CR_OFFSET);

		CrBits = XAxiVdma_ReadReg(Channel->ChanBase,
		     XAXIVDMA_CR_OFFSET) | XAXIVDMA_CR_RUNSTOP_MASK;

		XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET,
		    CrBits);

	}

	if (XAxiVdma_ChannelIsRunning(Channel)) {

		/* Start DMA transfers
		 *
		 */

		if (Channel->HasSG) {
			/* SG mode:
			 * Update the tail pointer so that hardware will start
			 * fetching BDs
			 */
			XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_TDESC_OFFSET,
			   Channel->TailBdPhysAddr);
		}
		else {
			/* Direct register mode:
			 * Update vsize to start the channel
			 */
			XAxiVdma_WriteReg(Channel->StartAddrBase,
			    XAXIVDMA_VSIZE_OFFSET, Channel->Vsize);

		}

		return XST_SUCCESS;
	}
	else {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Failed to start channel %x\r\n",
			    (unsigned int)Channel->ChanBase);

		return XST_DMA_ERROR;
	}
}

/*****************************************************************************/
/**
 * Stop one DMA channel
 *
 * @param Channel is the pointer to the channel to work on
 *
 * @return
 *  None
 *
 *****************************************************************************/
void XAxiVdma_ChannelStop(XAxiVdma_Channel *Channel)
{
	u32 CrBits;

	if (!XAxiVdma_ChannelIsRunning(Channel)) {
		return;
	}

	/* Clear the RS bit in CR register
	 */
	CrBits = XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET) &
		(~XAXIVDMA_CR_RUNSTOP_MASK);

	XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET, CrBits);

	return;
}

/*****************************************************************************/
/**
 * Dump registers from one DMA channel
 *
 * @param Channel is the pointer to the channel to work on
 *
 * @return
 *  None
 *
 *****************************************************************************/
void XAxiVdma_ChannelRegisterDump(XAxiVdma_Channel *Channel)
{
	printf("Dump register for channel %p:\r\n", (void *)Channel->ChanBase);
	printf("\tControl Reg: %x\r\n",
	    XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET));
	printf("\tStatus Reg: %x\r\n",
	    XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_SR_OFFSET));
	printf("\tCDESC Reg: %x\r\n",
	    XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_CDESC_OFFSET));
	printf("\tTDESC Reg: %x\r\n",
	    XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_TDESC_OFFSET));

	return;
}

/*****************************************************************************/
/**
 * Set the frame counter and delay counter for one channel
 *
 * @param Channel is the pointer to the channel to work on
 * @param FrmCnt is the frame counter value to be set
 * @param DlyCnt is the delay counter value to be set
 *
 * @return
 *   - XST_SUCCESS if setup finishes successfully
 *   - XST_FAILURE if channel is not initialized
 *   - XST_INVALID_PARAM if the configuration structure has invalid values
 *   - XST_NO_FEATURE if Frame Counter or Delay Counter is disabled
 *
 *****************************************************************************/
int XAxiVdma_ChannelSetFrmCnt(XAxiVdma_Channel *Channel, u8 FrmCnt, u8 DlyCnt)
{
	u32 CrBits;

	if (!Channel->IsValid) {
		xdbg_printf(XDBG_DEBUG_ERROR, "Channel not initialized\r\n");

		return XST_FAILURE;
	}

	if (!FrmCnt) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Frame counter value must be non-zero\r\n");

		return XST_INVALID_PARAM;
	}

	CrBits = XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET) &
		~(XAXIVDMA_DELAY_MASK | XAXIVDMA_FRMCNT_MASK);

	if (Channel->DbgFeatureFlags & XAXIVDMA_ENABLE_DBG_FRM_CNTR) {
		CrBits |= (FrmCnt << XAXIVDMA_FRMCNT_SHIFT);
	} else {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Channel Frame counter is disabled\r\n");
		return XST_NO_FEATURE;
	}
	if (Channel->DbgFeatureFlags & XAXIVDMA_ENABLE_DBG_DLY_CNTR) {
		CrBits |= (DlyCnt << XAXIVDMA_DELAY_SHIFT);
	} else {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Channel Delay counter is disabled\r\n");
		return XST_NO_FEATURE;
	}

	XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET,
	    CrBits);

	return XST_SUCCESS;
}

/*****************************************************************************/
/**
 * Get the frame counter and delay counter for both channels
 *
 * @param Channel is the pointer to the channel to work on
 * @param FrmCnt is the pointer for the returning frame counter value
 * @param DlyCnt is the pointer for the returning delay counter value
 *
 * @return
 *  None
 *
 * @note
 *  If FrmCnt return as 0, then the channel is not initialized
 *****************************************************************************/
void XAxiVdma_ChannelGetFrmCnt(XAxiVdma_Channel *Channel, u8 *FrmCnt,
        u8 *DlyCnt)
{
	u32 CrBits;

	if (!Channel->IsValid) {
		xdbg_printf(XDBG_DEBUG_ERROR, "Channel not initialized\r\n");

		*FrmCnt = 0;
		return;
	}

	CrBits = XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET);

	if (Channel->DbgFeatureFlags & XAXIVDMA_ENABLE_DBG_FRM_CNTR) {
		*FrmCnt = (CrBits & XAXIVDMA_FRMCNT_MASK) >>
				XAXIVDMA_FRMCNT_SHIFT;
	} else {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Channel Frame counter is disabled\r\n");
	}
	if (Channel->DbgFeatureFlags & XAXIVDMA_ENABLE_DBG_DLY_CNTR) {
		*DlyCnt = (CrBits & XAXIVDMA_DELAY_MASK) >>
				XAXIVDMA_DELAY_SHIFT;
	} else {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Channel Delay counter is disabled\r\n");
	}


	return;
}

/*****************************************************************************/
/**
 * Enable interrupts for a channel. Interrupts that are not specified by the
 * interrupt mask are not affected.
 *
 * @param Channel is the pointer to the channel to work on
 * @param IntrType is the interrupt mask for interrupts to be enabled
 *
 * @return
 *  None.
 *
 *****************************************************************************/
void XAxiVdma_ChannelEnableIntr(XAxiVdma_Channel *Channel, u32 IntrType)
{
	u32 CrBits;

	if ((IntrType & XAXIVDMA_IXR_ALL_MASK) == 0) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Enable intr with null intr mask value %x\r\n",
		    (unsigned int)IntrType);

		return;
	}

	CrBits = XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET) &
	          ~XAXIVDMA_IXR_ALL_MASK;

	CrBits |= IntrType & XAXIVDMA_IXR_ALL_MASK;

	XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET,
	    CrBits);

	return;
}

/*****************************************************************************/
/**
 * Disable interrupts for a channel. Interrupts that are not specified by the
 * interrupt mask are not affected.
 *
 * @param Channel is the pointer to the channel to work on
 * @param IntrType is the interrupt mask for interrupts to be disabled
 *
 * @return
 *  None.
 *
 *****************************************************************************/
void XAxiVdma_ChannelDisableIntr(XAxiVdma_Channel *Channel, u32 IntrType)
{
	u32 CrBits;
	u32 IrqBits;

	if ((IntrType & XAXIVDMA_IXR_ALL_MASK) == 0) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Disable intr with null intr mask value %x\r\n",
		    (unsigned int)IntrType);

		return;
	}

	CrBits = XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET);

	IrqBits = (CrBits & XAXIVDMA_IXR_ALL_MASK) &
	           ~(IntrType & XAXIVDMA_IXR_ALL_MASK);

	CrBits &= ~XAXIVDMA_IXR_ALL_MASK;

	XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET,
	    CrBits | IrqBits);

	return;
}

/*****************************************************************************/
/**
 * Get pending interrupts of a channel.
 *
 * @param Channel is the pointer to the channel to work on
 *
 * @return
 *  The interrupts mask represents pending interrupts.
 *
 *****************************************************************************/
u32 XAxiVdma_ChannelGetPendingIntr(XAxiVdma_Channel *Channel)
{
	return (XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_SR_OFFSET) &
	          XAXIVDMA_IXR_ALL_MASK);
}

/*****************************************************************************/
/**
 * Clear interrupts of a channel. Interrupts that are not specified by the
 * interrupt mask are not affected.
 *
 * @param Channel is the pointer to the channel to work on
 * @param IntrType is the interrupt mask for interrupts to be cleared
 *
 * @return
 *  None.
 *
 *****************************************************************************/
void XAxiVdma_ChannelIntrClear(XAxiVdma_Channel *Channel, u32 IntrType)
{

	if ((IntrType & XAXIVDMA_IXR_ALL_MASK) == 0) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Clear intr with null intr mask value %x\r\n",
		    (unsigned int)IntrType);

		return;
	}

	/* Only interrupts bits are writable in status register
	 */
	XAxiVdma_WriteReg(Channel->ChanBase, XAXIVDMA_SR_OFFSET,
	    IntrType & XAXIVDMA_IXR_ALL_MASK);

	return;
}

/*****************************************************************************/
/**
 * Get the enabled interrupts of a channel.
 *
 * @param Channel is the pointer to the channel to work on
 *
 * @return
 *  The interrupts mask represents pending interrupts.
 *
 *****************************************************************************/
u32 XAxiVdma_ChannelGetEnabledIntr(XAxiVdma_Channel *Channel)
{
	return (XAxiVdma_ReadReg(Channel->ChanBase, XAXIVDMA_CR_OFFSET) &
	          XAXIVDMA_IXR_ALL_MASK);
}

/*********************** BD Functions ****************************************/
/*****************************************************************************/
/*
 * Read one word from BD
 *
 * @param BdPtr is the BD to work on
 * @param Offset is the byte offset to read from
 *
 * @return
 *  The word value
 *
 *****************************************************************************/
static u32 XAxiVdma_BdRead(XAxiVdma_Bd *BdPtr, int Offset)
{
	return (*(u32 *)((UINTPTR)(void *)BdPtr + Offset));
}

/*****************************************************************************/
/*
 * Set one word in BD
 *
 * @param BdPtr is the BD to work on
 * @param Offset is the byte offset to write to
 * @param Value is the value to write to the BD
 *
 * @return
 *  None
 *
 *****************************************************************************/
static void XAxiVdma_BdWrite(XAxiVdma_Bd *BdPtr, int Offset, u32 Value)
{
	*(u32 *)((UINTPTR)(void *)BdPtr + Offset) = Value;

	return;
}

/*****************************************************************************/
/*
 * Set the next ptr from BD
 *
 * @param BdPtr is the BD to work on
 * @param NextPtr is the next ptr to set in BD
 *
 * @return
 *  None
 *
 *****************************************************************************/
static void XAxiVdma_BdSetNextPtr(XAxiVdma_Bd *BdPtr, u32 NextPtr)
{
	XAxiVdma_BdWrite(BdPtr, XAXIVDMA_BD_NDESC_OFFSET, NextPtr);
	return;
}

/*****************************************************************************/
/*
 * Set the start address from BD
 *
 * The address is physical address.
 *
 * @param BdPtr is the BD to work on
 * @param Addr is the address to set in BD
 *
 * @return
 *  None
 *
 *****************************************************************************/
static void XAxiVdma_BdSetAddr(XAxiVdma_Bd *BdPtr, u32 Addr)
{
	XAxiVdma_BdWrite(BdPtr, XAXIVDMA_BD_START_ADDR_OFFSET, Addr);

	return;
}

/*****************************************************************************/
/*
 * Set the vertical size for a BD
 *
 * @param BdPtr is the BD to work on
 * @param Vsize is the vertical size to set in BD
 *
 * @return
 *  - XST_SUCCESS if successful
 *  - XST_INVALID_PARAM if argument Vsize is invalid
 *
 *****************************************************************************/
static int XAxiVdma_BdSetVsize(XAxiVdma_Bd *BdPtr, int Vsize)
{
	if ((Vsize <= 0) || (Vsize > XAXIVDMA_VSIZE_MASK)) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Veritcal size %d is not valid\r\n", Vsize);

		return XST_INVALID_PARAM;
	}

	XAxiVdma_BdWrite(BdPtr, XAXIVDMA_BD_VSIZE_OFFSET, Vsize);
	return XST_SUCCESS;
}

/*****************************************************************************/
/*
 * Set the horizontal size for a BD
 *
 * @param BdPtr is the BD to work on
 * @param Hsize is the horizontal size to set in BD
 *
 * @return
 *  - XST_SUCCESS if successful
 *  - XST_INVALID_PARAM if argument Hsize is invalid
 *
 *****************************************************************************/
static int XAxiVdma_BdSetHsize(XAxiVdma_Bd *BdPtr, int Hsize)
{
	if ((Hsize <= 0) || (Hsize > XAXIVDMA_HSIZE_MASK)) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Horizontal size %d is not valid\r\n", Hsize);

		return XST_INVALID_PARAM;
	}

	XAxiVdma_BdWrite(BdPtr, XAXIVDMA_BD_HSIZE_OFFSET, Hsize);
	return XST_SUCCESS;
}

/*****************************************************************************/
/*
 * Set the stride size for a BD
 *
 * @param BdPtr is the BD to work on
 * @param Stride is the stride size to set in BD
 *
 * @return
 *  - XST_SUCCESS if successful
 *  - XST_INVALID_PARAM if argument Stride is invalid
 *
 *****************************************************************************/
static int XAxiVdma_BdSetStride(XAxiVdma_Bd *BdPtr, int Stride)
{
	u32 Bits;

	if ((Stride <= 0) || (Stride > XAXIVDMA_STRIDE_MASK)) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "Stride size %d is not valid\r\n", Stride);

		return XST_INVALID_PARAM;
	}

	Bits = XAxiVdma_BdRead(BdPtr, XAXIVDMA_BD_STRIDE_OFFSET) &
	        ~XAXIVDMA_STRIDE_MASK;

	XAxiVdma_BdWrite(BdPtr, XAXIVDMA_BD_STRIDE_OFFSET, Bits | Stride);

	return XST_SUCCESS;
}

/*****************************************************************************/
/*
 * Set the frame delay for a BD
 *
 * @param BdPtr is the BD to work on
 * @param FrmDly is the frame delay value to set in BD
 *
 * @return
 *  - XST_SUCCESS if successful
 *  - XST_INVALID_PARAM if argument FrmDly is invalid
 *
 *****************************************************************************/
static int XAxiVdma_BdSetFrmDly(XAxiVdma_Bd *BdPtr, int FrmDly)
{
	u32 Bits;

	if ((FrmDly < 0) || (FrmDly > XAXIVDMA_FRMDLY_MAX)) {
		xdbg_printf(XDBG_DEBUG_ERROR,
		    "FrmDly size %d is not valid\r\n", FrmDly);

		return XST_INVALID_PARAM;
	}

	Bits = XAxiVdma_BdRead(BdPtr, XAXIVDMA_BD_STRIDE_OFFSET) &
	        ~XAXIVDMA_FRMDLY_MASK;

	XAxiVdma_BdWrite(BdPtr, XAXIVDMA_BD_STRIDE_OFFSET,
	    Bits | (FrmDly << XAXIVDMA_FRMDLY_SHIFT));

	return XST_SUCCESS;
}

/*
* The configuration table for devices
*/

XAxiVdma_Config XAxiVdma_ConfigTable[XPAR_XAXIVDMA_NUM_INSTANCES] =
{
	{
		XPAR_AXI_VDMA_0_DEVICE_ID,
		XPAR_AXI_VDMA_0_BASEADDR,
		XPAR_AXI_VDMA_0_NUM_FSTORES,
		XPAR_AXI_VDMA_0_INCLUDE_MM2S,
		XPAR_AXI_VDMA_0_INCLUDE_MM2S_DRE,
		XPAR_AXI_VDMA_0_M_AXI_MM2S_DATA_WIDTH,
		XPAR_AXI_VDMA_0_INCLUDE_S2MM,
		XPAR_AXI_VDMA_0_INCLUDE_S2MM_DRE,
		XPAR_AXI_VDMA_0_M_AXI_S2MM_DATA_WIDTH,
		XPAR_AXI_VDMA_0_INCLUDE_SG,
		XPAR_AXI_VDMA_0_ENABLE_VIDPRMTR_READS,
		XPAR_AXI_VDMA_0_USE_FSYNC,
		XPAR_AXI_VDMA_0_FLUSH_ON_FSYNC,
		XPAR_AXI_VDMA_0_MM2S_LINEBUFFER_DEPTH,
		XPAR_AXI_VDMA_0_S2MM_LINEBUFFER_DEPTH,
		XPAR_AXI_VDMA_0_MM2S_GENLOCK_MODE,
		XPAR_AXI_VDMA_0_S2MM_GENLOCK_MODE,
		XPAR_AXI_VDMA_0_INCLUDE_INTERNAL_GENLOCK,
		XPAR_AXI_VDMA_0_S2MM_SOF_ENABLE,
		XPAR_AXI_VDMA_0_M_AXIS_MM2S_TDATA_WIDTH,
		XPAR_AXI_VDMA_0_S_AXIS_S2MM_TDATA_WIDTH,
		XPAR_AXI_VDMA_0_ENABLE_DEBUG_INFO_1,
		XPAR_AXI_VDMA_0_ENABLE_DEBUG_INFO_5,
		XPAR_AXI_VDMA_0_ENABLE_DEBUG_INFO_6,
		XPAR_AXI_VDMA_0_ENABLE_DEBUG_INFO_7,
		XPAR_AXI_VDMA_0_ENABLE_DEBUG_INFO_9,
		XPAR_AXI_VDMA_0_ENABLE_DEBUG_INFO_13,
		XPAR_AXI_VDMA_0_ENABLE_DEBUG_INFO_14,
		XPAR_AXI_VDMA_0_ENABLE_DEBUG_INFO_15,
		XPAR_AXI_VDMA_0_ENABLE_DEBUG_ALL,
		XPAR_AXI_VDMA_0_ADDR_WIDTH,
		XPAR_AXI_VDMA_0_ENABLE_VERT_FLIP
	}
};


/** @} */
