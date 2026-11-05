// CSR unit <-> accelerator: one configured job and its completion.


interface csr_accelerator_if;

    // From the CSR Unit - committed job configuration
    logic activate;
    logic [31:0] memory_location, length;

    // From the Accelerator - done stays high until activate clears
    logic done, error;


    // ----- CSR Side -----
    modport csr (
        output activate,
               memory_location,
               length,

        input done,
              error
    );


    // ----- Accelerator Side -----
    modport accelerator(
        input activate,
              memory_location,
              length,

        output done,
               error
    );

endinterface
