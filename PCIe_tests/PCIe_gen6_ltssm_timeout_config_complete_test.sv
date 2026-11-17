//=========================================================================================
// File         : PCIe_gen6_ltssm_timeout_config_complete_test.sv
// Project      : PCIE_Gen6
// Description  : CONFIG.COMPLETE directed LTSSM timeout testcase.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

`include "../PCIe_tests/PCIe_gen6_ltssm_timeout_test_defs.svh"

// Configuration.Complete : PCIe_LTSSM_T_CFG_COMPLETE (2ms) + 20ms guard.
`PCIE_LTSSM_TIMEOUT_TEST(config_complete,
                         CFG_COMPLETE,
                         RC_ltssm_timeout_config_complete_sequence,
                         EP_ltssm_timeout_config_complete_sequence,
                         22ms)
