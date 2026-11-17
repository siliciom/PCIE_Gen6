//=========================================================================================
// File         : PCIe_gen6_ltssm_timeout_loopback_active_test.sv
// Project      : PCIE_Gen6
// Description  : LOOPBACK.ACTIVE directed LTSSM timeout testcase.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

`include "../PCIe_tests/PCIe_gen6_ltssm_timeout_test_defs.svh"

// Loopback.Active : PCIe_LTSSM_T_LOOPBACK_ACTIVE (5ms) + 20ms guard.
`PCIE_LTSSM_TIMEOUT_TEST(loopback_active,
                         LOOPBACK_ACTIVE,
                         RC_ltssm_timeout_loopback_active_sequence,
                         EP_ltssm_timeout_loopback_active_sequence,
                         25ms)
