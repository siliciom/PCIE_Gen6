//=========================================================================================
// File         : PCIe_gen6_ltssm_timeout_hot_reset_test.sv
// Project      : PCIE_Gen6
// Description  : HOT_RESET directed LTSSM timeout testcase.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

`include "../PCIe_tests/PCIe_gen6_ltssm_timeout_test_defs.svh"

// Hot Reset : PCIe_LTSSM_T_HOT_RESET (2ms) + 20ms guard.
`PCIE_LTSSM_TIMEOUT_TEST(hot_reset,
                         HOT_RESET,
                         RC_ltssm_timeout_hot_reset_sequence,
                         EP_ltssm_timeout_hot_reset_sequence,
                         22ms)
