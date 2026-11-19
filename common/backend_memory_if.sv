

interface backend_memory_if;

    import rv32_ooo_pkg::*;

    // Reserve one LQ/SQ entry on the edge where both signals are high.
    // disp_inst carries the full ROB tag used to match the later issue.
    logic disp_valid, disp_ready;
    renamed_uop_t disp_inst;

    modport dispatch(
        output disp_valid, disp_inst,
        input disp_ready
    );

    // send memory operations and get completions back
    // transfer on the clock edge when both valid and ready are high
    logic issue_valid, issue_ready, busy, result_valid, result_ready;

    // the backend sends the instruction, its operands, and the ROB head tag
    renamed_uop_t issue_uop; // load or store to send
    logic [XLEN-1:0] source_1, source_2;
    rob_tag_t rob_head_tag;

    // the LSU sends the completion tag and load data if there is a writeback
    execution_result_t result; // finished memory operation


    // backend side
    modport backend(
        output issue_valid,
               issue_uop,
               source_1,
               source_2,
               rob_head_tag,
               result_ready,

        input issue_ready,
              busy,
              result_valid,
              result
    );


    // load/store unit side
    modport memory(
        input disp_valid,
              disp_inst,
              issue_valid,
              issue_uop,
              source_1,
              source_2,
              rob_head_tag,
              result_ready,

        output disp_ready,
               issue_ready,
               busy,
               result_valid,
               result
    );

endinterface
