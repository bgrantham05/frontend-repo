module frontend_memory_dispatch_tb;
    import rv32_ooo_pkg::*;

    logic rst_n, branch_resolve;
    lane_count_t offered, backend_capacity, accepted;
    renamed_bundle_t bundle;
    backend_memory_if memory();

    frontend_memory_dispatch dut (
        .rst_ni(rst_n),
        .branch_resolve_valid_i(branch_resolve),
        .dispatch_count_i(offered),
        .dispatch_bundle_i(bundle),
        .backend_accept_count_i(backend_capacity),
        .dispatch_accept_count_o(accepted),
        .memory(memory)
    );

    task automatic check(input lane_count_t count, input logic valid,
                         input renamed_uop_t expected_uop);
        #1;
        if (accepted !== count || memory.disp_valid !== valid ||
            (valid && memory.disp_inst !== expected_uop))
            $fatal(1, "Expected accepted=%0d valid=%b, got accepted=%0d valid=%b",
                   count, valid, accepted, memory.disp_valid);
    endtask

    initial begin
        rst_n = 0;
        branch_resolve = 0;
        offered = 2;
        backend_capacity = 2;
        bundle = '0;
        bundle.lane0.decoded.mem_cmd = MEM_LOAD;
        bundle.lane1.decoded.mem_cmd = MEM_STORE;
        bundle.lane1.rob_tag.index = 1;
        memory.disp_ready = 0;
        check(0, 0, '0);

        rst_n = 1;
        check(0, 1, bundle.lane0);
        memory.disp_ready = 1;
        check(1, 1, bundle.lane0);
        bundle.lane0.decoded.mem_cmd = MEM_NONE;
        check(2, 1, bundle.lane1);
        memory.disp_ready = 0;
        check(1, 1, bundle.lane1);
        bundle.lane1.decoded.illegal = 1;
        check(2, 0, '0);
        bundle.lane1.decoded.illegal = 0;
        backend_capacity = 1;
        check(1, 0, '0);
        backend_capacity = 0;
        check(0, 0, '0);
        backend_capacity = 2;
        memory.disp_ready = 1;
        branch_resolve = 1;
        check(0, 0, '0);

        $display("frontend_memory_dispatch_tb passed");
        $finish;
    end
endmodule
