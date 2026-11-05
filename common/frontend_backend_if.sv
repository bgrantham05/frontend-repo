// Frontend <-> backend: dispatch, completion, branch recovery, and retirement.
// Backend broadcasts one resolution event; both sides recover on the same edge.


interface frontend_backend_if(

    // System - also used by the interface assertions
    input logic clk_i,
    input logic rst_ni
);

    // Import Packages
    import rv32_ooo_pkg::*;

    // Ordered Dispatch - up to two instructions, accepted as a prefix
    lane_count_t dispatch_count, dispatch_accept_count;
    renamed_bundle_t dispatch_bundle;

    // Two Completion Channels - ROB completion and optional PRF writeback
    logic completion_valid_0, completion_valid_1;
    execution_result_t completion_0, completion_1;

    // Branch Recovery - emitted once, independently of completion acceptance
    logic branch_resolve_valid, branch_mispredict;
    rob_tag_t branch_result_tag;
    logic [XLEN-1:0] branch_result_pc;

    // From the ROB / Frontend - head-only issue and committed CSR updates
    rob_tag_t rob_head_tag;
    logic retire_valid;
    rob_tag_t retire_tag;


    // ----- Frontend Side -----
    modport frontend(
        input clk_i,
              rst_ni,
              dispatch_accept_count,
              completion_valid_0,
              completion_valid_1,
              completion_0,
              completion_1,
              branch_resolve_valid,
              branch_mispredict,
              branch_result_tag,
              branch_result_pc,

        output dispatch_count,
               dispatch_bundle,
               rob_head_tag,
               retire_valid,
               retire_tag
    );


    // ----- Backend Side -----
    modport backend(
        input clk_i,
              rst_ni,
              dispatch_count,
              dispatch_bundle,
              rob_head_tag,
              retire_valid,
              retire_tag,

        output dispatch_accept_count,
               completion_valid_0,
               completion_valid_1,
               completion_0,
               completion_1,
               branch_resolve_valid,
               branch_mispredict,
               branch_result_tag,
               branch_result_pc
    );


    // ----- Monitor Side - Observe Without Driving Signals -----
    modport monitor(
        input clk_i,
              rst_ni,
              dispatch_count,
              dispatch_accept_count,
              dispatch_bundle,
              completion_valid_0,
              completion_valid_1,
              completion_0,
              completion_1,
              branch_resolve_valid,
              branch_mispredict,
              branch_result_tag,
              branch_result_pc,
              rob_head_tag,
              retire_valid,
              retire_tag
    );


`ifdef ENABLE_PROTOCOL_ASSERTIONS
    // ----- Check the Dispatch and Recovery Contract -----
    always_ff @(posedge clk_i) if (rst_ni) begin
        assert (dispatch_count <= 2 && dispatch_accept_count <= dispatch_count);
        assert (!branch_mispredict || branch_resolve_valid);
        if (branch_resolve_valid)
            assert (dispatch_accept_count == 0);
    end
`endif

endinterface
