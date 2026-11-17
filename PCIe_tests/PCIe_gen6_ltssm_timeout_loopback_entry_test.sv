//=========================================================================================
// File         : PCIe_gen6_ltssm_timeout_loopback_entry_test.sv
// Project      : PCIE_Gen6
// Description  : LOOPBACK.ENTRY directed LTSSM timeout testcase.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

`include "../PCIe_tests/PCIe_gen6_ltssm_timeout_test_defs.svh"

// Loopback.Entry : PCIe_LTSSM_T_LOOPBACK_ENTRY (5ms) + 20ms guard.
`PCIE_LTSSM_TIMEOUT_TEST(loopback_entry,
                         LOOPBACK_ENTRY,
                         RC_ltssm_timeout_loopback_entry_sequence,
                         EP_ltssm_timeout_loopback_entry_sequence,
                         25ms)
