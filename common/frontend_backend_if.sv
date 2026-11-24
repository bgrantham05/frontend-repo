// connect frontend dispatch and retirement with backend completions
// both sides get the same branch resolution event


interface frontend_backend_if(

    // clock and reset for the interface checks
    input logic clk_i,
    input logic rst_ni
);

    import rv32_ooo_pkg::*;

    // accept 1 for the older instruction only, 2 for both
    lane_count_t dispatch_count, dispatch_accept_count;
    lane_count_t dispatch_capacity; // backend capacity before LSU admission
    renamed_bundle_t dispatch_bundle; // instructions offered to the backend

    // two completion lanes, each can also carry a register writeback
    logic completion_valid_0, completion_valid_1;
    execution_result_t completion_0, completion_1;

    // stop dispatch when a branch resolves, even if the prediction was right
    logic branch_resolve_valid, branch_mispredict; // branch result arrived, prediction was wrong
    rob_tag_t branch_result_tag; // which branch finished
    logic [XLEN-1:0] branch_result_pc; // where execution should go

    // ROB head tag for head-only issue, retirement tag for committed CSR updates
    rob_tag_t rob_head_tag;
    logic retire_valid;
    rob_tag_t retire_tag;


    // frontend side
    modport frontend(
        input clk_i,
              rst_ni,
              dispatch_capacity,
              completion_valid_0,
              completion_valid_1,
              completion_0,
              completion_1,
              branch_resolve_valid,
              branch_mispredict,
              branch_result_tag,
              branch_result_pc,

        output dispatch_count,
               dispatch_accept_count,
               dispatch_bundle,
               rob_head_tag,
               retire_valid,
               retire_tag
    );


    // backend side
    modport backend(
        input clk_i,
              rst_ni,
              dispatch_count,
              dispatch_accept_count,
              dispatch_bundle,
              rob_head_tag,
              retire_valid,
              retire_tag,

        output dispatch_capacity,
               completion_valid_0,
               completion_valid_1,
               completion_0,
               completion_1,
               branch_resolve_valid,
               branch_mispredict,
               branch_result_tag,
               branch_result_pc
    );


    // monitor side, read signals only
    modport monitor(
        input clk_i,
              rst_ni,
              dispatch_count,
              dispatch_capacity,
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
    // check dispatch counts and branch resolution
    always_ff @(posedge clk_i) if (rst_ni) begin
        assert (dispatch_count <= 2 && dispatch_accept_count <= dispatch_count);
        assert (dispatch_capacity <= 2 && dispatch_accept_count <= dispatch_capacity);
        assert (!branch_mispredict || branch_resolve_valid);
        if (branch_resolve_valid)
            assert (dispatch_accept_count == 0);
    end
`endif

endinterface
