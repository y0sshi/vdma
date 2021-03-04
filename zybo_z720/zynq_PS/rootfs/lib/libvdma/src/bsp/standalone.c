/******************************************************************************
*
* Copyright (C) 2009 - 2016 Xilinx, Inc. All rights reserved.
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
* @file xil_assert.c
*
* This file contains basic assert related functions for Xilinx software IP.
*
* <pre>
* MODIFICATION HISTORY:
*
* Ver   Who    Date   Changes
* ----- ---- -------- -------------------------------------------------------
* 1.00a hbm  07/14/09 Initial release
* 6.0   kvn  05/31/16 Make Xil_AsserWait a global variable
* </pre>
*
******************************************************************************/

/***************************** Include Files *********************************/

#include <slab/bsp/xil_types.h>
#include <slab/bsp/xil_assert.h>
#include <slab/bsp/xil_exception.h>
#include <slab/bsp/xpseudo_asm.h>
#include <slab/bsp/xdebug.h>

/************************** Constant Definitions *****************************/

/**************************** Type Definitions *******************************/

typedef struct {
	Xil_ExceptionHandler Handler;
	void *Data;
} XExc_VectorTableEntry;

/***************** Macros (Inline Functions) Definitions *********************/

/************************** Function Prototypes ******************************/
static void Xil_ExceptionNullHandler(void *Data);
/************************** Variable Definitions *****************************/
/*
 * Exception vector table to store handlers for each exception vector.
 */
#if defined (__aarch64__)
XExc_VectorTableEntry XExc_VectorTable[XIL_EXCEPTION_ID_LAST + 1] =
{
        {Xil_ExceptionNullHandler, NULL},
        {Xil_SyncAbortHandler, NULL},
        {Xil_ExceptionNullHandler, NULL},
        {Xil_ExceptionNullHandler, NULL},
        {Xil_SErrorAbortHandler, NULL},

};
#else
XExc_VectorTableEntry XExc_VectorTable[XIL_EXCEPTION_ID_LAST + 1] =
{
	{Xil_ExceptionNullHandler, NULL},
	{Xil_UndefinedExceptionHandler, NULL},
	{Xil_ExceptionNullHandler, NULL},
	{Xil_PrefetchAbortHandler, NULL},
	{Xil_DataAbortHandler, NULL},
	{Xil_ExceptionNullHandler, NULL},
	{Xil_ExceptionNullHandler, NULL},
};
#endif
#if !defined (__aarch64__)
u32 DataAbortAddr;       /* Address of instruction causing data abort */
u32 PrefetchAbortAddr;   /* Address of instruction causing prefetch abort */
u32 UndefinedExceptionAddr;   /* Address of instruction causing Undefined
							     exception */
#endif

/**
 * This variable allows testing to be done easier with asserts. An assert
 * sets this variable such that a driver can evaluate this variable
 * to determine if an assert occurred.
 */
u32 Xil_AssertStatus;

/**
 * This variable allows the assert functionality to be changed for testing
 * such that it does not wait infinitely. Use the debugger to disable the
 * waiting during testing of asserts.
 */
s32 Xil_AssertWait = 1;

/* The callback function to be invoked when an assert is taken */
static Xil_AssertCallback Xil_AssertCallbackRoutine = NULL;

/*****************************************************************************/
/**
*
* @brief    Implement assert. Currently, it calls a user-defined callback
*           function if one has been set.  Then, it potentially enters an
*           infinite loop depending on the value of the Xil_AssertWait
*           variable.
*
* @param    file: filename of the source
* @param    line: linenumber within File
*
* @return   None.
*
* @note     None.
*
******************************************************************************/
void Xil_Assert(const char8 *File, s32 Line)
{
	/* if the callback has been set then invoke it */
	if (Xil_AssertCallbackRoutine != 0) {
		(*Xil_AssertCallbackRoutine)(File, Line);
	}

	/* if specified, wait indefinitely such that the assert will show up
	 * in testing
	 */
	while (Xil_AssertWait != 0) {
	}
}

/*****************************************************************************/
/**
*
* @brief    Set up a callback function to be invoked when an assert occurs.
*           If a callback is already installed, then it will be replaced.
*
* @param    routine: callback to be invoked when an assert is taken
*
* @return   None.
*
* @note     This function has no effect if NDEBUG is set
*
******************************************************************************/
void Xil_AssertSetCallback(Xil_AssertCallback Routine)
{
	Xil_AssertCallbackRoutine = Routine;
}

/*****************************************************************************/
/**
*
* @brief    Null handler function. This follows the XInterruptHandler
*           signature for interrupt handlers. It can be used to assign a null
*           handler (a stub) to an interrupt controller vector table.
*
* @param    NullParameter: arbitrary void pointer and not used.
*
* @return   None.
*
* @note     None.
*
******************************************************************************/
void XNullHandler(void *NullParameter)
{
	(void) NullParameter;
}

/****************************************************************************/
/**
*
* This function is a stub Handler that is the default Handler that gets called
* if the application has not setup a Handler for a specific  exception. The
* function interface has to match the interface specified for a Handler even
* though none of the arguments are used.
*
* @param	Data is unused by this function.
*
* @return	None.
*
* @note		None.
*
*****************************************************************************/
static void Xil_ExceptionNullHandler(void *Data)
{
	(void) Data;
DieLoop: goto DieLoop;
}

/****************************************************************************/
/**
* @brief	The function is a common API used to initialize exception handlers
*			across all supported arm processors. For ARM Cortex-A53, Cortex-R5,
*			and Cortex-A9, the exception handlers are being initialized
*			statically and this function does not do anything.
* 			However, it is still present to take care of backward compatibility
*			issues (in earlier versions of BSPs, this API was being used to
*			initialize exception handlers).
*
* @param	None.
*
* @return	None.
*
* @note		None.
*
*****************************************************************************/
void Xil_ExceptionInit(void)
{
	return;
}

/*****************************************************************************/
/**
* @brief	Register a handler for a specific exception. This handler is being
*			called when the processor encounters the specified exception.
*
* @param	exception_id contains the ID of the exception source and should
*			be in the range of 0 to XIL_EXCEPTION_ID_LAST.
*			See xil_exception.h for further information.
* @param	Handler to the Handler for that exception.
* @param	Data is a reference to Data that will be passed to the
*			Handler when it gets called.
*
* @return	None.
*
* @note		None.
*
****************************************************************************/
void Xil_ExceptionRegisterHandler(u32 Exception_id,
				    Xil_ExceptionHandler Handler,
				    void *Data)
{
#if defined (versal) && !defined(ARMR5) && EL3
/*
 * Cortexa72 processor in versal is coupled with GIC-500, and GIC-500 supports
 * only FIQ at EL3. Hence, tweaking this API to always act on FIQ,
 * ignoring argument passed by user.
 */
	Exception_id = XIL_EXCEPTION_ID_FIQ_INT;
#endif
	XExc_VectorTable[Exception_id].Handler = Handler;
	XExc_VectorTable[Exception_id].Data = Data;
}

/*****************************************************************************/
/**
* @brief	Get a handler for a specific exception. This handler is being
*			called when the processor encounters the specified exception.
*
* @param	exception_id contains the ID of the exception source and should
*			be in the range of 0 to XIL_EXCEPTION_ID_LAST.
*			See xil_exception.h for further information.
* @param	Handler to the Handler for that exception.
* @param	Data is a reference to Data that will be passed to the
*			Handler when it gets called.
*
* @return	None.
*
* @note		None.
*
****************************************************************************/
void Xil_GetExceptionRegisterHandler(u32 Exception_id,
					Xil_ExceptionHandler *Handler,
					void **Data)
{
#if defined (versal) && !defined(ARMR5) && EL3
/*
 * Cortexa72 processor in versal is coupled with GIC-500, and GIC-500 supports
 * only FIQ at EL3. Hence, tweaking this API to always act on FIQ,
 * ignoring argument passed by user.
 */
	Exception_id = XIL_EXCEPTION_ID_FIQ_INT;
#endif

	*Handler = XExc_VectorTable[Exception_id].Handler;
	*Data = XExc_VectorTable[Exception_id].Data;
}

/*****************************************************************************/
/**
*
* @brief	Removes the Handler for a specific exception Id. The stub Handler
*			is then registered for this exception Id.
*
* @param	exception_id contains the ID of the exception source and should
*			be in the range of 0 to XIL_EXCEPTION_ID_LAST.
*			See xil_exception.h for further information.
*
* @return	None.
*
* @note		None.
*
****************************************************************************/
void Xil_ExceptionRemoveHandler(u32 Exception_id)
{
	Xil_ExceptionRegisterHandler(Exception_id,
				       Xil_ExceptionNullHandler,
				       NULL);
}

#if defined (__aarch64__)
/*****************************************************************************/
/**
*
* Default Synchronous abort handler which prints a debug message on console if
* Debug flag is enabled
*
* @param        None
*
* @return       None.
*
* @note         None.
*
****************************************************************************/

void Xil_SyncAbortHandler(void *CallBackRef){
	(void) CallBackRef;
	xdbg_printf(XDBG_DEBUG_ERROR, "Synchronous abort \n");
	while(1) {
		;
	}
}

/*****************************************************************************/
/**
*
* Default SError abort handler which prints a debug message on console if
* Debug flag is enabled
*
* @param        None
*
* @return       None.
*
* @note         None.
*
****************************************************************************/
void Xil_SErrorAbortHandler(void *CallBackRef){
	(void) CallBackRef;
	xdbg_printf(XDBG_DEBUG_ERROR, "Synchronous abort \n");
	while(1) {
		;
	}
}
#else
/*****************************************************************************/
/*
*
* Default Data abort handler which prints data fault status register through
* which information about data fault can be acquired
*
* @param	None
*
* @return	None.
*
* @note		None.
*
****************************************************************************/

void Xil_DataAbortHandler(void *CallBackRef){
	(void) CallBackRef;
#ifdef DEBUG
	u32 FaultStatus;

        xdbg_printf(XDBG_DEBUG_ERROR, "Data abort \n");
        #ifdef __GNUC__
	FaultStatus = mfcp(XREG_CP15_DATA_FAULT_STATUS);
	    #elif defined (__ICCARM__)
	        mfcp(XREG_CP15_DATA_FAULT_STATUS,FaultStatus);
	    #else
	        { volatile register u32 Reg __asm(XREG_CP15_DATA_FAULT_STATUS);
	        FaultStatus = Reg; }
	    #endif
	xdbg_printf(XDBG_DEBUG_GENERAL, "Data abort with Data Fault Status Register  %lx\n",FaultStatus);
	xdbg_printf(XDBG_DEBUG_GENERAL, "Address of Instruction causing Data abort %lx\n",DataAbortAddr);
#endif
	while(1) {
		;
	}
}

/*****************************************************************************/
/*
*
* Default Prefetch abort handler which prints prefetch fault status register through
* which information about instruction prefetch fault can be acquired
*
* @param	None
*
* @return	None.
*
* @note		None.
*
****************************************************************************/
void Xil_PrefetchAbortHandler(void *CallBackRef){
	(void) CallBackRef;
#ifdef DEBUG
	u32 FaultStatus;

    xdbg_printf(XDBG_DEBUG_ERROR, "Prefetch abort \n");
        #ifdef __GNUC__
	FaultStatus = mfcp(XREG_CP15_INST_FAULT_STATUS);
	    #elif defined (__ICCARM__)
			mfcp(XREG_CP15_INST_FAULT_STATUS,FaultStatus);
	    #else
			{ volatile register u32 Reg __asm(XREG_CP15_INST_FAULT_STATUS);
			FaultStatus = Reg; }
		#endif
	xdbg_printf(XDBG_DEBUG_GENERAL, "Prefetch abort with Instruction Fault Status Register  %lx\n",FaultStatus);
	xdbg_printf(XDBG_DEBUG_GENERAL, "Address of Instruction causing Prefetch abort %lx\n",PrefetchAbortAddr);
#endif
	while(1) {
		;
	}
}
/*****************************************************************************/
/*
*
* Default undefined exception handler which prints address of the undefined
* instruction if debug prints are enabled
*
* @param	None
*
* @return	None.
*
* @note		None.
*
****************************************************************************/
void Xil_UndefinedExceptionHandler(void *CallBackRef){
	(void) CallBackRef;
	xdbg_printf(XDBG_DEBUG_GENERAL, "Address of the undefined instruction %lx\n",UndefinedExceptionAddr);
	while(1) {
		;
	}
}
#endif
