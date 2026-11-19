// testbench model for the accelerator's read-only image, weight, and parameter memories
// cnn_mem_if and accelerator_cnn_pkg come from the accelerator project
// call load with a vector directory to fill all three memories
// example: xmem.load("vectors/v0_box");
// REGISTERED_READ = 0 returns data in the same cycle
// REGISTERED_READ = 1 returns data after the clock edge
module cnn_ext_mem #(
    parameter bit REGISTERED_READ = 1'b0
) (
    input logic      clk_i,
    cnn_mem_if.memory bus
);

    import accelerator_cnn_pkg::*;

    logic [7:0]  img [IMG_MEM_BYTES];
    logic [7:0]  wgt [WGT_MEM_BYTES];
    logic [31:0] par [PARAM_WORDS];

    // load the three hex files and check the parameter header
    task automatic load(input string dir);
        clear(); // start with empty memories
        $readmemh({dir, "/img_mem.hex"},   img);
        $readmemh({dir, "/wgt_mem.hex"},   wgt);
        $readmemh({dir, "/param_mem.hex"}, par);
        if (par[PAR_MAGIC] !== MAGIC) // warn if the parameter file has the wrong header
            $display("  WARNING %s/param_mem.hex magic is %08h, expected %08h",
                     dir, par[PAR_MAGIC], MAGIC);
    endtask

    // zero the memories before loading another test vector
    task automatic clear();
        for (int i = 0; i < IMG_MEM_BYTES; i++) img[i] = '0;
        for (int i = 0; i < WGT_MEM_BYTES; i++) wgt[i] = '0;
        for (int i = 0; i < PARAM_WORDS;   i++) par[i] = '0;
    endtask

    // choose clocked or same-cycle reads
    generate
        if (REGISTERED_READ) begin : g_sync
            always_ff @(posedge clk_i) begin
                bus.img_rdata <= img[bus.img_addr];
                bus.wgt_rdata <= wgt[bus.wgt_addr];
                bus.par_rdata <= par[bus.par_addr];
            end
        end else begin : g_async
            assign bus.img_rdata = img[bus.img_addr];
            assign bus.wgt_rdata = wgt[bus.wgt_addr];
            assign bus.par_rdata = par[bus.par_addr];
        end
    endgenerate

endmodule
