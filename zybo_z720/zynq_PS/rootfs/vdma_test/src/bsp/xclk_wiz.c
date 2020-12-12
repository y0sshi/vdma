/******************************************************************************
*
* Copyright (C) 2016 Xilinx, Inc.  All rights reserved.
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
* @file xclk_wiz.c
* @addtogroup clk_wiz_v1_2
* @{
*
* This file implements the functions to get the CLK_WIZ GUI information and
* Clock Monitor Interrupt status
*
* <pre>
* MODIFICATION HISTORY:
*
* Ver Who Date    Changes
* ----- ---- -------- -------------------------------------------------------
* 1.0 ram 2/12/16 Initial version for Clock Wizard
* 1.1 siv 8/17/16 Used UINTPTR instead of u32 for Baseaddress
* 	Changed the prototype of XClk_Wiz_CfgInitialize
* 1.2 ms  3/02/17 Fixed compilation warnings. Fix for CR-970507.
* </pre>
******************************************************************************/

/***************************** Include Files *********************************/

#include <slab/bsp/xparameters.h>
#include <slab/bsp/xstatus.h>
#include <slab/bsp/xclk_wiz.h>

/************************** Constant Definitions *****************************/


/**************************** Type Definitions *******************************/


/*************************** Macros Definitions ******************************/


/************************** Function Prototypes ******************************/

/*
* Each of callback functions to be called on different types of interrupts.
* These stub functions are set during XClk_Wiz_CfgInitialize as default
* callback functions. If application is not registered any of the callback
* function, these functions will be called for doing nothing.
*/
static void StubErrCallBack(void *CallBackRef, u32 ErrorMask);

/************************** Variable Definitions *****************************/


/****************************************************************************/
/**
* Initialize the XClk_Wiz instance provided by the caller based on the
* given Config structure.
*
* @param	InstancePtr is the XClk_Wiz instance to operate on.
* @param	CfgPtr is the device configuration structure containing
*			information about a specific CLK_WIZ.
* @param	EffectiveAddr is the base address of the device. If address
*		translation is being used, then this parameter must reflect the
*		virtual base address. Otherwise, the physical address should be
*		used.
*
* @return
*		- XST_SUCCESS Initialization was successful.
*		- XST_FAILURE Initialization was failure.
*
* @note		None
*****************************************************************************/
u32 XClk_Wiz_CfgInitialize(XClk_Wiz *InstancePtr, XClk_Wiz_Config *CfgPtr,
			   UINTPTR EffectiveAddr)
{
	/* Verify arguments */
	Xil_AssertNonvoid(InstancePtr != NULL);
	Xil_AssertNonvoid(CfgPtr != NULL);
	Xil_AssertNonvoid((UINTPTR *)EffectiveAddr != NULL);

	/* Setup the instance */
	InstancePtr->Config = *CfgPtr;

	InstancePtr->Config.BaseAddr = EffectiveAddr;

	/* Set all handlers to stub values, let user configure this data later
	 */
	InstancePtr->ClkOutOfRangeCallBack  = StubErrCallBack;
	InstancePtr->ClkGlitchCallBack      = StubErrCallBack;
	InstancePtr->ClkStopCallBack        = StubErrCallBack;

	InstancePtr->ErrorCallBack = StubErrCallBack;

	InstancePtr->IsReady = (u32)(XIL_COMPONENT_IS_READY);

	return XST_SUCCESS;

}

/*****************************************************************************/
/**
* XClk_Wiz_GetInterruptSettings will get the information from  clock wizard
* IER  and ISR Registers.
*
* @param	InstancePtr is the XClk_Wiz instance to operate on.
*
* @return 	None
*
****************************************************************************/
void XClk_Wiz_GetInterruptSettings(XClk_Wiz  *InstancePtr)
{
	Xil_AssertVoid(InstancePtr != NULL);

	InstancePtr->ClkWizIntrStatus = XCLK_WIZ_GET_BITFIELD_VALUE
	((InstancePtr)->Config.BaseAddr, XCLK_WIZ_ISR_OFFSET,
	XCLK_WIZ_ISR_ALLINTR_MASK, XCLK_WIZ_ISR_ALLINTR_SHIFT);
	InstancePtr->ClkIntrEnable = XCLK_WIZ_GET_BITFIELD_VALUE
	((InstancePtr)->Config.BaseAddr, XCLK_WIZ_IER_OFFSET,
	XCLK_WIZ_IER_ALLINTR_MASK, XCLK_WIZ_IER_ALLINTR_SHIFT);
}

/*****************************************************************************/
/**
* This routine is a stub for the asynchronous error interrupt callback. The
* stub is here in case the upper layer forgot to set the handler. On
* initialization, Error interrupt handler is set to this callback. It is
* considered an error for this handler to be invoked.
*
* @param	CallBackRef is a callback reference passed in by the upper
*		layer when setting the callback functions, and passed back to
*		the upper layer when the callback is invoked.
* @param 	ErrorMask is a bit mask indicating the cause of the error. Its
*		value equals 'OR'ing one or more XCLK_WIZ_ISR_*_MASK values
*		defined in xclk_wiz_hw.h.
*
* @return	None
*
* @note		None
*
******************************************************************************/
static void StubErrCallBack(void *CallBackRef, u32 ErrorMask)
{
	(void) ((void *)CallBackRef);
	(void) ErrorMask;
	Xil_AssertVoidAlways();
}

/**
 * Look up the hardware configuration for a device instance
 *
 * @param	DeviceId is the unique device ID of the device to lookup for
 *
 * @return	The reference to the configuration record in the configuration
 * 		table (in xclk_wiz_g.c) corresponding to the Device ID or if
 *		not found, a NULL pointer is returned.
 *
 * @note	None
 *
 *****************************************************************************/
XClk_Wiz_Config *XClk_Wiz_LookupConfig(u32 DeviceId)
{
	extern XClk_Wiz_Config XClk_Wiz_ConfigTable[];
	XClk_Wiz_Config *CfgPtr = NULL;
	u32 Index;

	for (Index = 0; Index < XPAR_XCLK_WIZ_NUM_INSTANCES; Index++) {
		if (XClk_Wiz_ConfigTable[Index].DeviceId == DeviceId) {
			CfgPtr = &XClk_Wiz_ConfigTable[Index];
			break;
		}
	}

	return CfgPtr;
}

/*
* The configuration table for devices
*/

XClk_Wiz_Config XClk_Wiz_ConfigTable[XPAR_XCLK_WIZ_NUM_INSTANCES] =
{
	{
		XPAR_VIDEO_DYNCLK_DEVICE_ID,
		XPAR_VIDEO_DYNCLK_BASEADDR,
		XPAR_VIDEO_DYNCLK_ENABLE_CLOCK_MONITOR,
		XPAR_VIDEO_DYNCLK_ENABLE_USER_CLOCK0,
		XPAR_VIDEO_DYNCLK_ENABLE_USER_CLOCK1,
		XPAR_VIDEO_DYNCLK_ENABLE_USER_CLOCK2,
		XPAR_VIDEO_DYNCLK_ENABLE_USER_CLOCK3,
		XPAR_VIDEO_DYNCLK_REF_CLK_FREQ,
		XPAR_VIDEO_DYNCLK_USER_CLK_FREQ0,
		XPAR_VIDEO_DYNCLK_USER_CLK_FREQ1,
		XPAR_VIDEO_DYNCLK_USER_CLK_FREQ2,
		XPAR_VIDEO_DYNCLK_USER_CLK_FREQ3,
		XPAR_VIDEO_DYNCLK_PRECISION,
		XPAR_VIDEO_DYNCLK_ENABLE_PLL0,
		XPAR_VIDEO_DYNCLK_ENABLE_PLL1
	}
};

/** @} */
