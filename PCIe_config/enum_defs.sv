//=========================================================================================
// File         : enum_defs.sv
// Project      : PCIE_Gen6
// Description  : PCIe_config\enum_defs.sv
// Author       : 
// Date         : 2026-08-14
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the SILICIOM TECHNOLOGIES PVT LTD,
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the SILICIOM TECHNOLOGIES PVT LTD license agreement.
* All other rights reserved.
***********************************************************************************************************************/
package typedef_enums;
	
typedef enum bit {
                  STANDARD_REPLAY  = 1'b0, // Replays ALL unacknowledged flits in the buffer
                  SELECTIVE_REPLAY = 1'b1  // Replays ONLY the single flit requested
                 } replay_scheduled_type_e;


typedef enum bit {
                  NON_FLIT_MODE,
                  FLIT_MODE
                 } pcie_mode_e;
                 
endpackage

