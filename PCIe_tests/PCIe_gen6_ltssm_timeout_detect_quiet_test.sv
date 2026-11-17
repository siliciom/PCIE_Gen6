//=========================================================================================
// File         : PCIe_gen6_ltssm_timeout_detect_quiet_test.sv
// Project      : PCIE_Gen6
// Description  : DETECT.QUIET directed LTSSM timeout testcase.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

`include "../PCIe_tests/PCIe_gen6_ltssm_timeout_test_defs.svh"

// Detect.Quiet : PCIe_LTSSM_T_DETECT_QUIET (12ms) + 20ms guard.
`PCIE_LTSSM_TIMEOUT_TEST(detect_quiet,
                         DETECT_QUIET,
                         RC_ltssm_timeout_detect_quiet_sequence,
                         EP_ltssm_timeout_detect_quiet_sequence,
                         32ms)
