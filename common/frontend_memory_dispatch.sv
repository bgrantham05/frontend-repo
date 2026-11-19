// Admit the oldest prefix that can dispatch to both the backend and memory.
module frontend_memory_dispatch (
    input logic rst_ni,
    input logic branch_resolve_valid_i,
    input rv32_ooo_pkg::lane_count_t dispatch_count_i,
    input rv32_ooo_pkg::renamed_bundle_t dispatch_bundle_i,
    // Include backend capacity here, before applying LQ/SQ backpressure.
    input rv32_ooo_pkg::lane_count_t backend_accept_count_i,
    output rv32_ooo_pkg::lane_count_t dispatch_accept_count_o,
    backend_memory_if.dispatch memory
);
    import rv32_ooo_pkg::*;

    lane_count_t candidate_count;
    logic lane0_needs_entry, lane1_needs_entry;

    function automatic logic needs_entry(input decoded_uop_t uop);
        return !uop.illegal && !uop.fetch_error &&
               (uop.mem_cmd == MEM_LOAD || uop.mem_cmd == MEM_STORE);
    endfunction

    assign candidate_count = backend_accept_count_i < dispatch_count_i
                           ? backend_accept_count_i : dispatch_count_i;
    assign lane0_needs_entry = needs_entry(dispatch_bundle_i.lane0.decoded);
    assign lane1_needs_entry = needs_entry(dispatch_bundle_i.lane1.decoded);

    // The offer is independent of disp_ready. It is recomputed with the
    // dispatch candidates each cycle, like the frontend's dispatch bundle.
    always_comb begin
        memory.disp_valid = 1'b0;
        memory.disp_inst = '0;
        if (rst_ni && !branch_resolve_valid_i) begin
            if (candidate_count >= 1 && lane0_needs_entry) begin
                memory.disp_valid = 1'b1;
                memory.disp_inst = dispatch_bundle_i.lane0;
            end else if (candidate_count >= 2 && lane1_needs_entry) begin
                memory.disp_valid = 1'b1;
                memory.disp_inst = dispatch_bundle_i.lane1;
            end
        end
    end

    always_comb begin
        dispatch_accept_count_o = 0;
        if (rst_ni && !branch_resolve_valid_i) begin
            if (candidate_count >= 1 && (!lane0_needs_entry || memory.disp_ready)) begin
                dispatch_accept_count_o = 1;
                // The scalar memory port can reserve only one entry per cycle.
                if (candidate_count >= 2 &&
                    (!lane1_needs_entry || (!lane0_needs_entry && memory.disp_ready)))
                    dispatch_accept_count_o = 2;
            end
        end
    end
endmodule
