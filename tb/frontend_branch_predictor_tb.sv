`timescale 1ns/1ps
module frontend_branch_predictor_tb;
    logic clk = 0;
    always #5 clk = !clk;

    logic rst_n = 0;
    logic [1:0][31:0] pc;
    logic [1:0] taken, hit, local_index, global_index, local_taken, global_taken;
    logic [1:0][31:0] next_pc;
    logic resolve_valid = 0;
    logic [31:0] resolve_pc, target;
    logic outcome, saved_local, saved_global, saved_local_taken, saved_global_taken;

    frontend_branch_predictor #(
        .LOCAL_PC_BITS(1), .LOCAL_HISTORY_BITS(1), .GLOBAL_HISTORY_BITS(1),
        .CHOOSER_BITS(1), .BTB_BITS(1)
    ) dut (
        .clk_i(clk), .rst_ni(rst_n), .lookup_pc_i(pc),
        .predicted_taken_o(taken), .predicted_next_pc_o(next_pc), .btb_hit_o(hit),
        .local_index_o(local_index), .global_index_o(global_index),
        .local_taken_o(local_taken), .global_taken_o(global_taken),
        .resolve_valid_i(resolve_valid), .resolve_pc_i(resolve_pc),
        .resolve_taken_i(outcome), .resolve_target_i(target),
        .resolve_local_index_i(saved_local), .resolve_global_index_i(saved_global),
        .resolve_local_taken_i(saved_local_taken), .resolve_global_taken_i(saved_global_taken)
    );

    task automatic train(
        input logic [31:0] branch_pc, branch_target,
        input logic actual_taken, old_local, old_global, old_local_taken, old_global_taken
    );
        @(negedge clk);
        resolve_pc = branch_pc;
        target = branch_target;
        outcome = actual_taken;
        saved_local = old_local;
        saved_global = old_global;
        saved_local_taken = old_local_taken;
        saved_global_taken = old_global_taken;
        resolve_valid = 1;
        @(posedge clk);
        #1;
        resolve_valid = 0;
    endtask

    initial begin
        pc = {32'h4, 32'h0};
        @(negedge clk);
        rst_n = 1;
        #1;
        if (hit !== 0 || taken !== 0 || next_pc !== {32'h8, 32'h4})
            $fatal(1, "Cold lookup must fall through on each lane");

        train(0, 'h40, 1, 0, 0, 0, 0);
        if (hit !== 2'b01 || local_index !== 2'b01 || global_index !== 2'b01)
            $fatal(1, "Incorrect BTB allocation or history indexing");
        if (global_taken[1] !== 1 || taken !== 0)
            $fatal(1, "A taken component without a BTB hit must fall through");

        train(0, 'h44, 1, 1, 1, 0, 0);
        if (taken !== 2'b01 || next_pc[0] !== 'h44)
            $fatal(1, "Taken prediction must use the updated BTB target");

        // Train an older lookup's indices while the current lookup uses index 1.
        repeat (4) train(0, 'h44, 1, 0, 0, 0, 0);
        if (dut.local_counter_q[0] !== 2'b11 || dut.global_counter_q[0] !== 2'b11 ||
            dut.local_counter_q[1] !== 2'b10 || dut.global_counter_q[1] !== 2'b10)
            $fatal(1, "Saved-index training or counter saturation failed");
        repeat (4) train(0, '0, 0, 1, 1, 1, 1);
        if (dut.local_counter_q[1] !== 2'b00 || dut.global_counter_q[1] !== 2'b00)
            $fatal(1, "Counters must saturate at zero");

        // Arrange a taken local prediction and a not-taken global prediction.
        repeat (3) train(0, 'h44, 1, 1, 0, 0, 0);
        train(4, '0, 0, 0, 0, 0, 0);
        train(4, '0, 0, 1, 0, 0, 0);
        if (local_taken[0] !== 1 || global_taken[0] !== 0 || taken[0] !== 1)
            $fatal(1, "Chooser should initially favor local");
        train(0, '0, 0, 1, 0, 1, 0);
        if (dut.chooser_q[0] !== 2'b10)
            $fatal(1, "Chooser should switch to global after a local miss");
        if (local_taken[0] !== 1 || global_taken[0] !== 0 || taken[0] !== 0)
            $fatal(1, "Chooser should select the global prediction");
        train(0, 'h44, 1, 0, 0, 1, 0);
        if (dut.chooser_q[0] !== 2'b01)
            $fatal(1, "Chooser should switch back after a global miss");

        train(8, 'h80, 1, 0, 0, 0, 0);
        if (hit[0] !== 0 || next_pc[0] !== 4)
            $fatal(1, "A conflicting PC must not hit the replaced entry");
        pc = {32'h8, 32'h0};
        #1;
        if (hit !== 2'b10)
            $fatal(1, "Second lookup lane must see the replacement entry");
        $display("frontend_branch_predictor_tb passed");
        $finish;
    end
endmodule
