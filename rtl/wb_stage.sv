module wb_stage

    import rv32i_types::*;
(
    input  mem_wb_t          mem_wb_r,
    input   logic           stall_wb,

    output logic             wb_we,
    output logic    [4:0]    wb_rd,
    output logic    [31:0]   wb_wdata

);
    logic monitor_valid;

    always_comb begin
        wb_we    = 1'b0;    //set values to default first
        wb_rd    = 5'd0;
        wb_wdata = 32'd0;

        monitor_valid = (!stall_wb) ? mem_wb_r.valid : '0;

        if (mem_wb_r.valid_bit && mem_wb_r.reg_write && (mem_wb_r.rd_addr != 5'd0))     //make sure we aren't writing to reg 0
            begin           
                wb_we    = 1'b1;
                wb_rd    = mem_wb_r.rd_addr;    //dest reg
                wb_wdata = mem_wb_r.rd_wdata;   //value to write in dest reg
            end
    end

endmodule