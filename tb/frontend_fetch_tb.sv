`timescale 1ns/1ps
module frontend_fetch_tb;
    logic clk = 0;
    always #5 clk = !clk;
    logic rst_n = 0, redirect = 0, ready = 0;
    logic [31:0] target = 0;
    logic v0, v1, e0, e1;
    logic [31:0] pc0, pc1, inst0, inst1;
    instruction_memory_if imem();
    frontend_fetch dut (
        .clk_i(clk), .rst_ni(rst_n), .redirect_req_i(redirect),
        .redirect_pc_i(target), .downstream_ready_i(ready), .imem(imem),
        .fetch_valid0_o(v0), .fetch_pc0_o(pc0), .fetch_inst0_o(inst0),
        .fetch_valid1_o(v1), .fetch_pc1_o(pc1), .fetch_inst1_o(inst1),
        .fetch_error0_o(e0), .fetch_error1_o(e1)
    );
    // Synchronous ROM; address-valued words expose response/PC mismatches.
    always @(posedge clk) if (imem.read_enable) begin
        imem.data <= {imem.address + 32'd4, imem.address};
        imem.error <= (imem.address == 32'h40) ? 2'b10 : 2'b00;
    end
    task automatic tick;
        @(posedge clk);
        #1;
    endtask
    task automatic check_bundle(input logic [31:0] expected_pc);
        if (!(v0 && v1)) $fatal(1, "Missing bundle");
        if (pc0 !== expected_pc || pc1 !== expected_pc + 32'd4)
            $fatal(1, "Wrong PCs");
        if (inst0 !== expected_pc || inst1 !== expected_pc + 32'd4)
            $fatal(1, "ROM/PC mismatch");
    endtask
    initial begin
        tick();
        if (v0 || v1 || imem.read_enable) $fatal(1, "Fetch during reset");
        @(negedge clk); rst_n = 1;
        tick(); check_bundle(0);
        repeat (3) begin
            tick(); check_bundle(0);
            if (imem.read_enable) $fatal(1, "Overwrite during stall");
        end
        @(negedge clk); ready = 1;
        tick(); check_bundle(8);
        tick(); check_bundle(16);
        @(negedge clk); ready = 0; redirect = 1; target = 4;
        #1;
        if (v0 || v1 || imem.read_enable) $fatal(1, "Redirect not masked");
        tick();
        @(negedge clk); redirect = 0;
        tick(); check_bundle(4);
        tick(); check_bundle(4);
        @(negedge clk); ready = 1;
        tick(); check_bundle(12);
        @(negedge clk); redirect = 1; target = 32'h40;
        tick();
        @(negedge clk); redirect = 0;
        tick(); check_bundle(32'h40);
        if (e0 !== 0 || e1 !== 1) $fatal(1, "Errors lost");
        @(negedge clk); rst_n = 0;
        tick();
        if (v0 || v1) $fatal(1, "Reset retained response");
        @(negedge clk); rst_n = 1;
        tick(); check_bundle(0);
        $display("PASS: frontend_fetch_tb");
        $finish;
    end
    initial begin
        #2000;
        $fatal(1, "Timeout");
    end
endmodule
