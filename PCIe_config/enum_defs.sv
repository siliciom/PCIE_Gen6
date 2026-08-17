//=========================================================================================
// File         : enum_defs.sv
// Project      : PCIE_Gen6
// Description  : PCIe_config\enum_defs.sv
// Author       : 
// Date         : 2026-08-17
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
                  NON_FLIT_MODE,
                  FLIT_MODE
                 } pcie_mode_e;

typedef enum int {
                  PIPE_WIDTH_32 = 32,
                  PIPE_WIDTH_64 = 64
                 } pcie_pipe_width_e;

endpackage
