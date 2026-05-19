module mem_stage
import rv32i_types::*;
(
    input  logic   clk,
    input  logic   rst,
    input  logic   stall_mem,

    input  ex_mem_t ex_mem_r,
    
    input  logic [31:0] dmem_rdata,
    input  logic        dmem_resp,

    output mem_wb_t mem_wb_r,
    output logic dmem_stall
    
);

    mem_wb_t mem_wb_n;
    logic [31:0] final_rdata_shifted;
    logic [1:0] byte_offset;
    logic [31:0] dmem_rdata_latch;
    logic flag; 
    logic [3:0] dmem_rmask_temp;
    logic [31:0] rdata_val_shifted;
    
    assign byte_offset = ex_mem_r.result[1:0];  //get the offset for type of load/store
    assign dmem_rmask_temp = ex_mem_r.dmem_rmask;

    always_comb begin
    dmem_stall = ex_mem_r.valid_bit &&  //data memory stall signal
        (ex_mem_r.is_load || ex_mem_r.is_store) && !dmem_resp && !flag;
    end

    always_comb begin
        rdata_val_shifted = (flag) ? dmem_rdata_latch : dmem_rdata;
        final_rdata_shifted = rdata_val_shifted;

        if (ex_mem_r.is_load && (dmem_resp || flag)) begin  //shift the data we get appropriately
            unique case (ex_mem_r.mem_funct3)
                        load_f3_lb : final_rdata_shifted = {{24{rdata_val_shifted[7 +8 *byte_offset]}}, rdata_val_shifted[8 *byte_offset +: 8 ]};
                        load_f3_lbu: final_rdata_shifted = {{24{1'b0}}, rdata_val_shifted[8 *byte_offset +: 8 ]};
                        load_f3_lh : final_rdata_shifted = {{16{rdata_val_shifted[15+16*byte_offset[1]  ]}}, rdata_val_shifted[16*byte_offset[1]   +: 16]};
                        load_f3_lhu: final_rdata_shifted = {{16{1'b0}}, rdata_val_shifted[16*byte_offset[1]   +: 16]};
                        load_f3_lw : final_rdata_shifted = rdata_val_shifted;
                        default    : final_rdata_shifted = rdata_val_shifted;   
            endcase
        end
    end

    always_comb begin
        mem_wb_n = '0;
        mem_wb_n.valid     = ex_mem_r.valid;
        mem_wb_n.valid_bit = ex_mem_r.valid_bit;
        mem_wb_n.inst      = ex_mem_r.inst;
        mem_wb_n.order     = ex_mem_r.order;

        mem_wb_n.rs1_addr  = ex_mem_r.rs1_addr;
        mem_wb_n.rs2_addr  = ex_mem_r.rs2_addr;
        mem_wb_n.rs1_rdata = ex_mem_r.rs1_rdata;
        mem_wb_n.rs2_rdata = ex_mem_r.rs2_rdata;
        mem_wb_n.pc_rdata  = ex_mem_r.pc;
        //setup pc depending on if branch happened or not
        mem_wb_n.pc_wdata  = (ex_mem_r.branch_taken) ? ex_mem_r.branch_target : (ex_mem_r.pc + 32'd4);

        mem_wb_n.reg_write = ex_mem_r.reg_write;
        mem_wb_n.rd_addr   = ex_mem_r.rd_addr;

        mem_wb_n.rd_wdata = (ex_mem_r.is_load) ? final_rdata_shifted : ex_mem_r.result; //deciding alu output
        
        if (ex_mem_r.is_load || ex_mem_r.is_store) begin
            mem_wb_n.mem_addr = {ex_mem_r.result[31:2], 2'b00};
            mem_wb_n.mem_rmask = ex_mem_r.dmem_rmask;
            mem_wb_n.mem_wmask = ex_mem_r.dmem_wmask;
            mem_wb_n.mem_rdata = (flag) ? dmem_rdata_latch : dmem_rdata;
            mem_wb_n.mem_wdata = ex_mem_r.dmem_wdata;
        end else begin
            mem_wb_n.mem_addr  = 32'd0;
            mem_wb_n.mem_rmask = 4'd0;
            mem_wb_n.mem_wmask = 4'd0;
            mem_wb_n.mem_rdata = 32'd0;
            mem_wb_n.mem_wdata = 32'd0;
        end
    end

    always_ff @(posedge clk) begin  //setting up pipeline reg logic
        if (rst) begin
            mem_wb_r <= '0;
            mem_wb_r.valid_bit <= 1'b0;
        end else if (!stall_mem) begin
            mem_wb_r <= mem_wb_n;
        end else begin
            mem_wb_r <= mem_wb_r;
        end
    end

    always_ff @(posedge clk) begin  //latch dmem value edge case so we don't lose it
        if (rst) begin
            flag <= '0;
            dmem_rdata_latch <= '0;
        end else if (dmem_resp && stall_mem && !flag) begin //adding !flag HERE
            dmem_rdata_latch <= dmem_rdata;
            flag <= '1;
        end else if (flag && !stall_mem) begin
            dmem_rdata_latch <= '0;
            flag <= '0;
        end
    end

endmodule
