//=========================================================================================
// File         : PCIe_gen6_ltssm_timeout_loopback_exit_test.sv
// Project      : PCIE_Gen6
// Description  : LOOPBACK.EXIT directed LTSSM timeout testcase.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

`include "../PCIe_tests/PCIe_gen6_ltssm_timeout_test_defs.svh"

// Loopback.Exit : PCIe_LTSSM_T_LOOPBACK_EXIT_IDLE (10us) + 20ms guard.
`PCIE_LTSSM_TIMEOUT_TEST(loopback_exit,
                         LOOPBACK_EXIT,
                         RC_ltssm_timeout_loopback_exit_sequence,
                         EP_ltssm_timeout_loopback_exit_sequence,
                         25ms)
