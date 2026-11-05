module frontend_decode (
    input logic [31:0] instruction_i,
    input logic [31:0] pc_i,
    input logic [31:0] predicted_next_pc_i,
    input logic fetch_error_i,
    output rv32_ooo_pkg::decoded_uop_t decoded_o
);
    import rv32_ooo_pkg::*;
    logic [6:0] opcode, funct7;
    logic [2:0] funct3;
    logic legal;
    //these are the operation selectors
    assign opcode = instruction_i[6:0];
    assign funct3 = instruction_i[14:12];
    assign funct7 = instruction_i[31:25];

    // decode instruction, does NOT retain state
    always_comb begin
        decoded_o = '0;
        decoded_o.pc = pc_i;
        decoded_o.instruction = instruction_i;
        decoded_o.predicted_next_pc = predicted_next_pc_i;
        decoded_o.fetch_error = fetch_error_i;
        decoded_o.rs1 = instruction_i[19:15];
        decoded_o.rs2 = instruction_i[24:20];
        decoded_o.rd = instruction_i[11:7];
        decoded_o.uop_class = UOP_INVALID;
        decoded_o.alu_op = ALU_ADD;
        decoded_o.operand_a_sel = OPA_ZERO;
        decoded_o.operand_b_sel = OPB_ZERO;
        decoded_o.branch_op = BR_NONE;
        decoded_o.mem_cmd = MEM_NONE;
        decoded_o.mem_size = MEM_BYTE;
        decoded_o.csr_cmd = CSR_NONE;
        legal = 1'b1;

        // figure out the instrction, set control signals
        case (opcode)
            // Register and immediate ALU operations
            7'b0110011, 7'b0010011: begin
                decoded_o.uop_class = UOP_ALU;
                decoded_o.uses_rs1 = 1'b1;
                decoded_o.uses_rs2 = (opcode == 7'b0110011);
                decoded_o.writes_rd = 1'b1;
                decoded_o.operand_a_sel = OPA_RS1;
                decoded_o.operand_b_sel = decoded_o.uses_rs2 ? OPB_RS2 : OPB_IMM;
                // sign extension
                if (!decoded_o.uses_rs2)
                    decoded_o.immediate = {{20{instruction_i[31]}}, instruction_i[31:20]};
                // ALU op selection
                case (funct3)
                    3'b000: begin
                        if (decoded_o.uses_rs2 && funct7 == 7'b0100000)
                            decoded_o.alu_op = ALU_SUB;
                        else decoded_o.alu_op = ALU_ADD;
                        if (decoded_o.uses_rs2 && funct7 != 0 && funct7 != 7'b0100000)
                            legal = 1'b0;
                    end
                    3'b001: begin
                        decoded_o.alu_op = ALU_SLL;
                        if (funct7 != 0) legal = 1'b0;
                    end
                    3'b010: decoded_o.alu_op = ALU_SLT;
                    3'b011: decoded_o.alu_op = ALU_SLTU;
                    3'b100: decoded_o.alu_op = ALU_XOR;
                    3'b101: begin
                        decoded_o.alu_op = (funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL;
                        if (funct7 != 0 && funct7 != 7'b0100000) legal = 1'b0;
                    end
                    3'b110: decoded_o.alu_op = ALU_OR;
                    3'b111: decoded_o.alu_op = ALU_AND;
                    default: legal = 1'b0;
                endcase
                if (decoded_o.uses_rs2 && funct3 != 0 && funct3 != 3'b101 && funct7 != 0)
                    legal = 1'b0;
                if (!decoded_o.uses_rs2 && (funct3 == 3'b001 || funct3 == 3'b101))
                    decoded_o.immediate = {27'b0, instruction_i[24:20]};
            end
            // load, store
            7'b0000011, 7'b0100011: begin
                decoded_o.uses_rs1 = 1'b1;
                decoded_o.operand_a_sel = OPA_RS1;
                decoded_o.operand_b_sel = OPB_IMM;
                if (opcode == 7'b0000011) begin
                    decoded_o.uop_class = UOP_LOAD;
                    decoded_o.mem_cmd = MEM_LOAD;
                    decoded_o.writes_rd = 1'b1;
                    decoded_o.immediate = {{20{instruction_i[31]}}, instruction_i[31:20]};
                    decoded_o.load_unsigned = funct3[2];
                    // width, extension and alignment checks
                    case (funct3)
                        3'b000, 3'b100: decoded_o.mem_size = MEM_BYTE;
                        3'b001, 3'b101: decoded_o.mem_size = MEM_HALF;
                        3'b010: decoded_o.mem_size = MEM_WORD;
                        default: legal = 1'b0;
                    endcase
                end else begin
                    // source, addr offset
                    decoded_o.uop_class = UOP_STORE;
                    decoded_o.mem_cmd = MEM_STORE;
                    decoded_o.uses_rs2 = 1'b1;
                    decoded_o.immediate = {{20{instruction_i[31]}}, instruction_i[31:25], instruction_i[11:7]};
                    case (funct3)
                        3'b000: decoded_o.mem_size = MEM_BYTE;
                        3'b001: decoded_o.mem_size = MEM_HALF;
                        3'b010: decoded_o.mem_size = MEM_WORD;
                        default: legal = 1'b0;
                    endcase
                end
            end
            // branches: compare rs1 and rs2, add immediate to PC if taken
            7'b1100011: begin
                decoded_o.uop_class = UOP_BRANCH;
                decoded_o.uses_rs1 = 1'b1;
                decoded_o.uses_rs2 = 1'b1;
                decoded_o.operand_a_sel = OPA_PC;
                decoded_o.operand_b_sel = OPB_IMM;
                decoded_o.immediate = {{19{instruction_i[31]}}, instruction_i[31],
                    instruction_i[7], instruction_i[30:25], instruction_i[11:8], 1'b0};
                case (funct3)
                    3'b000: decoded_o.branch_op = BR_BEQ;
                    3'b001: decoded_o.branch_op = BR_BNE;
                    3'b100: decoded_o.branch_op = BR_BLT;
                    3'b101: decoded_o.branch_op = BR_BGE;
                    3'b110: decoded_o.branch_op = BR_BLTU;
                    3'b111: decoded_o.branch_op = BR_BGEU;
                    default: legal = 1'b0;
                endcase
            end
            //jump controls
            7'b1101111, 7'b1100111: begin
                decoded_o.uop_class = UOP_JUMP;
                decoded_o.writes_rd = 1'b1;
                decoded_o.operand_a_sel = OPA_PC;
                decoded_o.operand_b_sel = OPB_FOUR;
                // direct jump offset
                if (opcode == 7'b1101111) begin
                    decoded_o.branch_op = BR_JAL;
                    decoded_o.immediate = {{11{instruction_i[31]}}, instruction_i[31],
                        instruction_i[19:12], instruction_i[20], instruction_i[30:21], 1'b0};
                end else begin
                    // indirect jump base and offset
                    decoded_o.branch_op = BR_JALR;
                    decoded_o.uses_rs1 = 1'b1;
                    decoded_o.immediate = {{20{instruction_i[31]}}, instruction_i[31:20]};
                    if (funct3 != 0) legal = 1'b0;
                end
            end
            7'b0110111, 7'b0010111: begin
                decoded_o.uop_class = UOP_ALU;
                decoded_o.writes_rd = 1'b1;
                decoded_o.operand_a_sel = (opcode == 7'b0010111) ? OPA_PC : OPA_ZERO;
                decoded_o.operand_b_sel = OPB_IMM;
                decoded_o.immediate = {instruction_i[31:12], 12'b0};
            end
            // read/write set clear for CSR instructions
            7'b1110011: begin
                decoded_o.uop_class = UOP_CSR;
                decoded_o.writes_rd = 1'b1;
                decoded_o.csr_address = instruction_i[31:20];
                decoded_o.csr_uses_immediate = funct3[2];
                decoded_o.csr_immediate = instruction_i[19:15];
                decoded_o.uses_rs1 = !funct3[2];
                case (funct3)
                    3'b001, 3'b101: decoded_o.csr_cmd = CSR_RW;
                    3'b010, 3'b110: decoded_o.csr_cmd = CSR_RS;
                    3'b011, 3'b111: decoded_o.csr_cmd = CSR_RC;
                    default: legal = 1'b0; 
                endcase
            end
            default: legal = 1'b0;
        endcase

        // illegal instructions
        decoded_o.illegal = !legal;
        decoded_o.writes_rd = decoded_o.writes_rd && (decoded_o.rd != 0);
        if (!legal || fetch_error_i) begin
            decoded_o.uop_class = UOP_INVALID;
            decoded_o.uses_rs1 = 1'b0;
            decoded_o.uses_rs2 = 1'b0;
            decoded_o.writes_rd = 1'b0;
            decoded_o.branch_op = BR_NONE;
            decoded_o.mem_cmd = MEM_NONE;
            decoded_o.csr_cmd = CSR_NONE;
        end
    end
endmodule

//upstream buffering retains both instructions until accepted
module frontend_decode_pair (
    input logic [31:0] instruction0_i, instruction1_i,
    input logic [31:0] pc0_i, pc1_i,
    input logic [31:0] predicted_next_pc0_i, predicted_next_pc1_i,
    input logic fetch_error0_i, fetch_error1_i,
    output rv32_ooo_pkg::decoded_uop_t decoded0_o, decoded1_o
);
    //decode older instruction first so next PC prediction for younger instruction
    frontend_decode lane0 (
        .instruction_i(instruction0_i), .pc_i(pc0_i),
        .predicted_next_pc_i(predicted_next_pc0_i),
        .fetch_error_i(fetch_error0_i), .decoded_o(decoded0_o)
    );
    // decode the younger instruction
    frontend_decode lane1 (
        .instruction_i(instruction1_i), .pc_i(pc1_i),
        .predicted_next_pc_i(predicted_next_pc1_i),
        .fetch_error_i(fetch_error1_i), .decoded_o(decoded1_o)
    );
endmodule
