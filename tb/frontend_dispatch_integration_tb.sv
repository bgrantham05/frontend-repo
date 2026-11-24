module frontend_dispatch_integration_tb;
    import rv32_ooo_pkg::*;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    instruction_memory_if imem();
    frontend_backend_if backend(clk, rst_n);
    backend_memory_if memory();
    lane_count_t allocated;
    renamed_bundle_t allocation;
    rob_tag_t tail;

    frontend dut (
        .clk_i(clk), .rst_ni(rst_n), .imem(imem), .backend(backend), .memory(memory),
        .rob_admission_count_i(2'd2), .rob_tail_tag_i(tail), .rob_head_tag_i('0),
        .older_branch_pending_i(1'b0), .retire_valid_i(1'b0), .retire_tag_i('0),
        .reclaim_valid_i(1'b0), .reclaim_pdst_i('0),
        .rob_allocate_count_o(allocated), .rob_allocate_bundle_o(allocation),
        .old_pdst_lane0_o(), .old_pdst_lane1_o()
    );

    assign imem.error = '0;
    always_ff @(posedge clk) begin
        if (imem.read_enable) begin
            case (imem.address)
                0: imem.data <= {32'h00102023, 32'h00002083}; // sw x1, lw x1
                default: imem.data <= {32'h00000013, 32'h00000013};
            endcase
        end
        if (!rst_n)
            tail <= '0;
        else
            tail <= increment_rob_tag(tail, allocated);
    end

    task automatic check(input lane_count_t count, input logic valid,
                         input mem_cmd_e command, input int pc);
        if (allocated !== count || backend.dispatch_accept_count !== count ||
            memory.disp_valid !== valid)
            $fatal(1, "Unexpected dispatch at PC %0d, count=%0d valid=%b",
                   pc, allocated, memory.disp_valid);
        if (valid && (memory.disp_inst.decoded.mem_cmd !== command ||
                      memory.disp_inst.decoded.pc !== pc ||
                      memory.disp_inst.rob_tag !== tail))
            $fatal(1, "Unexpected LSU offer at PC %0d", pc);
        if (count != 0 && (allocation !== backend.dispatch_bundle ||
                           allocation.lane0.decoded.pc !== pc ||
                           allocation.lane0.rob_tag !== tail))
            $fatal(1, "Unexpected ROB allocation at PC %0d", pc);
    endtask

    initial begin
        backend.dispatch_capacity = 2;
        backend.branch_resolve_valid = 0;
        backend.branch_mispredict = 0;
        backend.branch_result_pc = '0;
        memory.disp_ready = 0;
        @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);
        repeat (5) begin
            check(0, 1, MEM_LOAD, 0);
            @(negedge clk);
        end
        if (imem.read_enable) $fatal(1, "Fetch kept reading after the queue filled");
        memory.disp_ready = 1;
        #1;
        check(1, 1, MEM_LOAD, 0);
        @(negedge clk);
        check(2, 1, MEM_STORE, 4);
        if (memory.disp_inst.psrc2 !== phys_reg_t'(32))
            $fatal(1, "Store did not see the accepted load's rename mapping");
        @(negedge clk);
        check(2, 0, MEM_NONE, 12);
        $display("frontend_dispatch_integration_tb passed");
        $finish;
    end
endmodule
