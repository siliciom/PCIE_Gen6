//=========================================================================================
// File         : PCIe_gen6_ltssm_timeout_polling_configuration_test.sv
// Project      : PCIE_Gen6
// Description  : POLLING.CONFIGURATION directed LTSSM timeout testcase.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

`include "../PCIe_tests/PCIe_gen6_ltssm_timeout_test_defs.svh"

// Polling.Configuration : PCIe_LTSSM_T_POLLING_CONFIGURATION (48ms) + 20ms guard.
`PCIE_LTSSM_TIMEOUT_TEST(polling_configuration,
                         POLLING_CONFIGURATION,
                         RC_ltssm_timeout_polling_configuration_sequence,
                         EP_ltssm_timeout_polling_configuration_sequence,
                         68us)   // [SIM-FAST] was 68ms

