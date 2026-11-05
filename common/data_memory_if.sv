// One outstanding word transaction. Addresses are BYTE addresses, aligned to four bytes.
// Write data and byte enables use little-endian byte lanes.
// Every accepted request receives one response, including stores.


interface data_memory_if;

    // Request Handshake and Operation - write=1 means store, write=0 means load
    logic request_valid, request_ready, write;

    // Request Payload - one byte-enable bit per store byte; ignored for reads
    logic [31:0] address, write_data;
    logic [3:0] byte_enable;

    // Response Handshake and Payload
    logic response_valid, response_ready, error;
    logic [31:0] read_data;


    // ----- Client Side - LSU, Accelerator, or Arbiter -----
    // Notice: hold valid and the request payload until request_ready accepts them.
    modport client(
        output request_valid,
               write,
               address,
               write_data,
               byte_enable,
               response_ready,

        input request_ready,
              response_valid,
              read_data,
              error
    );


    // ----- Server Side - Arbiter or RAM Controller -----
    // The response also holds until valid && ready at a rising edge.
    modport server(
        input request_valid,
              write,
              address,
              write_data,
              byte_enable,
              response_ready,

        output request_ready,
               response_valid,
               read_data,
               error
    );

endinterface
