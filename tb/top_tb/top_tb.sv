    
    //----------------------------------------------------------------------
    // DUT instance.
    //----------------------------------------------------------------------

    mem_itf #(.CHANNELS(2)) mem_itf(.*);
    memory_model #(.CHANNELS(2), .MAGIC(0)) mem(.itf(mem_itf));

    mon_itf  mon_itf(.clk(clk), .rst(rst));
    monitor  #(.SPIKE_DPI(1)) monitor(.mon_itf(mon_itf)); // Set SPIKE_DPI to 0 if using random_tb.

    cpu dut(
        .clk            (clk),
        .rst            (rst),

        .imem_addr      (mem_itf.addr [0]),
        .imem_rmask     (mem_itf.rmask[0]),
        .imem_rdata     (mem_itf.rdata[0]),
        .imem_resp      (mem_itf.resp [0]),

        .dmem_addr      (mem_itf.addr [1]),
        .dmem_rmask     (mem_itf.rmask[1]),
        .dmem_wmask     (mem_itf.wmask[1]),
        .dmem_rdata     (mem_itf.rdata[1]),
        .dmem_wdata     (mem_itf.wdata[1]),
        .dmem_resp      (mem_itf.resp [1])
    );

    assign mem_itf.wmask[0] = '0;
    assign mem_itf.wdata[0] = 'x;

    always @(posedge clk) begin
        if (mon_itf.halt) begin
            $finish;
        end
        if (mon_itf.error != 0) begin
            $fatal;
        end
    end

    `include `RVFI_REFERENCE_FILE
