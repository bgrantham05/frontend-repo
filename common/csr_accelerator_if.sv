// send a job from the CSR unit to the accelerator and get its result


interface csr_accelerator_if;

    // job settings from the CSR unit
    logic activate; // start the configured job
    logic [31:0] memory_location, length;

    // hold done high until the CSR unit clears activate
    logic done, error; // job finished and whether it failed


    // CSR side
    modport csr (
        output activate,
               memory_location,
               length,

        input done,
              error
    );


    // accelerator side
    modport accelerator(
        input activate,
              memory_location,
              length,

        output done,
               error
    );

endinterface
