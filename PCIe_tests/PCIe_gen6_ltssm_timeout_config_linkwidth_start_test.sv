//=========================================================================================
// File         : PCIe_gen6_ltssm_timeout_config_linkwidth_start_test.sv
// Project      : PCIE_Gen6
// Description  : CONFIG.LINKWIDTH_START directed LTSSM timeout testcase.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

`include "../PCIe_tests/PCIe_gen6_ltssm_timeout_test_defs.svh"

// Linkwidth.Start : PCIe_LTSSM_T_CFG_LINKWIDTH_START (24ms) + 20ms guard.
`PCIE_LTSSM_TIMEOUT_TEST(config_linkwidth_start,
                         CFG_LINKWIDTH_START,
                         RC_ltssm_timeout_config_linkwidth_start_sequence,
                         EP_ltssm_timeout_config_linkwidth_start_sequence,
                         44us)   // [SIM-FAST] was 44ms

