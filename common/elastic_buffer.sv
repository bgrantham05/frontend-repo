// hold one item between clock edges
// take a new item on the same edge the old one leaves


module elastic_buffer #(

    parameter int unsigned DATA_WIDTH = 1
) (

    // clock, reset, and flush
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic                  flush_i,

    // input from the producer
    input  logic                  input_valid_i,
    output logic                  input_ready_o,
    input  logic [DATA_WIDTH-1:0] input_data_i,

    // output to the consumer
    output logic                  output_valid_o,
    input  logic                  output_ready_i,
    output logic [DATA_WIDTH-1:0] output_data_o
);

    // saved item and its valid bit
    logic                  full_q; // one item is waiting
    logic [DATA_WIDTH-1:0] data_q;


    // accept an item if the slot is empty or the current item is leaving
    // only send items already in the slot
    // block both transfers during reset or flush
    assign input_ready_o  = rst_ni && !flush_i &&
                            (!full_q || output_ready_i);
    assign output_valid_o = rst_ni && !flush_i && full_q;
    assign output_data_o  = data_q; // send the saved item


    // save the next item at the clock edge
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            full_q <= 1'b0;
            data_q <= '0;
        end else if (flush_i) begin

            // clear the slot on a flush, even during a stall
            full_q <= 1'b0;
        end else if (input_ready_o) begin

            // if nothing replaces the old item, the slot becomes empty
            full_q <= input_valid_i;
            if (input_valid_i) begin
                data_q <= input_data_i; // save the new item
            end
        end
    end

endmodule
