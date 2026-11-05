// One-entry, full-throughput ready/valid buffer.
// When the consumer accepts the current item, a new item can replace it on
// the same edge. This registers the payload/valid path without adding a bubble.


module elastic_buffer #(

    parameter int unsigned DATA_WIDTH = 1
) (

    // System and Branch Flush
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic                  flush_i,

    // From the Producer - payload and input handshake
    input  logic                  input_valid_i,
    output logic                  input_ready_o,
    input  logic [DATA_WIDTH-1:0] input_data_i,

    // To the Consumer - saved payload and output handshake
    output logic                  output_valid_o,
    input  logic                  output_ready_i,
    output logic [DATA_WIDTH-1:0] output_data_o
);

    // Saved Item and Its Valid Bit
    logic                  full_q;
    logic [DATA_WIDTH-1:0] data_q;


    // ----- Input and Output Handshakes -----
    // A slot is available when empty or when the consumer accepts the old item.
    // Reset/flush masks both handshakes so no neighbor counts a discarded item.
    assign input_ready_o  = rst_ni && !flush_i &&
                            (!full_q || output_ready_i);
    assign output_valid_o = rst_ni && !flush_i && full_q;
    assign output_data_o  = data_q;


    // ----- Capture or Replace the Item -----
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            full_q <= 1'b0;
            data_q <= '0;
        end else if (flush_i) begin

            // Flush wins over enqueue and dequeue, even when the consumer stalls.
            full_q <= 1'b0;
        end else if (input_ready_o) begin

            // A consumed item with no replacement leaves the buffer empty.
            full_q <= input_valid_i;
            if (input_valid_i) begin
                data_q <= input_data_i;
            end
        end
    end

endmodule
