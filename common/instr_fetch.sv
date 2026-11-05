// Whole-bundle ready/valid fetch for a synchronous two-word ROM.
// Both valid lanes are consumed together on an edge with downstream_ready_i.
module frontend_fetch (
    input logic clk_i,
    input logic rst_ni,
    input logic redirect_req_i,
    input logic [31:0] redirect_pc_i,
    input logic downstream_ready_i,
    instruction_memory_if.frontend imem,
    output logic fetch_valid0_o,
    output logic [31:0] fetch_pc0_o,
    output logic [31:0] fetch_inst0_o,
    output logic fetch_valid1_o,
    output logic [31:0] fetch_pc1_o,
    output logic [31:0] fetch_inst1_o,
    output logic fetch_error0_o,
    output logic fetch_error1_o
);
    import rv32_ooo_pkg::*;
    logic [31:0] request_pc_q, response_pc_q;
    logic response_valid_q;

    // A read replaces the ROM's held output, so reserve its response slot.
    assign imem.address = request_pc_q;
    assign imem.read_enable = rst_ni && !redirect_req_i &&
                              (!response_valid_q || downstream_ready_i);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            request_pc_q <= RESET_PC;
            response_pc_q <= RESET_PC;
            response_valid_q <= 1'b0;
        end else if (redirect_req_i) begin
            // Suppress the old request; read the exact target on the next edge.
            request_pc_q <= redirect_pc_i;
            response_valid_q <= 1'b0;
        end else if (imem.read_enable) begin
            response_pc_q <= request_pc_q;
            response_valid_q <= 1'b1;
            request_pc_q <= request_pc_q + 32'd8;
        end
    end

    assign fetch_valid0_o = rst_ni && !redirect_req_i && response_valid_q;
    assign fetch_valid1_o = fetch_valid0_o;
    assign fetch_pc0_o = response_pc_q;
    assign fetch_pc1_o = response_pc_q + 32'd4;
    assign fetch_inst0_o = imem.data[31:0];
    assign fetch_inst1_o = imem.data[63:32];
    // Faulting slots remain valid: later stages must carry their error metadata.
    assign fetch_error0_o = imem.error[0];
    assign fetch_error1_o = imem.error[1];
endmodule
