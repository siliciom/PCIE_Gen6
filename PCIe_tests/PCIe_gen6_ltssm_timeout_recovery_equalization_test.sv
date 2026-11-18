//=========================================================================================
// File         : PCIe_gen6_ltssm_timeout_recovery_equalization_test.sv
// Project      : PCIE_Gen6
// Description  : RECOVERY.EQUALIZATION directed LTSSM timeout testcase.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

`include "../PCIe_tests/PCIe_gen6_ltssm_timeout_test_defs.svh"

// Recovery.Equalization : phase 1 timeout PCIe_LTSSM_T_RCVRY_EQ_PH1 (12ms) + 20ms guard.
`PCIE_LTSSM_TIMEOUT_TEST(recovery_equalization,
                         RECOVERY_EQUALIZATION,
                         RC_ltssm_timeout_recovery_equalization_sequence,
                         EP_ltssm_timeout_recovery_equalization_sequence,
                         32us)   // [SIM-FAST] was 32ms

