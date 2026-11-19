// handle one word request at a time, using byte addresses aligned to four bytes
// store data and byte enables use little-endian lane order
// send one response for every accepted load or store


interface data_memory_if;

    // write is 1 for a store and 0 for a load
    logic request_valid, request_ready, write;

    // use one enable bit for each store byte
    logic [31:0] address, write_data;
    logic [3:0] byte_enable; // which bytes to write

    // return the data and error status
    logic response_valid, response_ready, error;
    logic [31:0] read_data; // value returned for a load


    // client side: LSU, accelerator, or arbiter
    // hold the request until valid and ready are both high at the clock edge
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


    // server side: arbiter or RAM controller
    // hold the response until valid and ready are both high at the clock edge
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
