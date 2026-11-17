//=========================================================================================
// File         : PCIe_gen6_ltssm_timeout_recovery_rcvrlock_test.sv
// Project      : PCIE_Gen6
// Description  : RECOVERY.RCVRLOCK directed LTSSM timeout testcase.
//=========================================================================================

/**********************************************************************************************************************
 * Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
 * By using, accessing or downloading any part of this file/document,  including by copying, saving,
 * distributing, displaying or preparing derivatives of,
 * you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
 * All other rights reserved.
 ***********************************************************************************************************************/

`include "../PCIe_tests/PCIe_gen6_ltssm_timeout_test_defs.svh"

// Recovery.RcvrLock : PCIe_LTSSM_T_RCVRY_RCVRLOCK (24ms) + 20ms guard.
`PCIE_LTSSM_TIMEOUT_TEST(recovery_rcvrlock,
                         RECOVERY_RCVRLOCK,
                         RC_ltssm_timeout_recovery_rcvrlock_sequence,
                         EP_ltssm_timeout_recovery_rcvrlock_sequence,
                         44ms)
