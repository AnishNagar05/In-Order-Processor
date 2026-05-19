module cpu
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,
    output  logic   [31:0]  imem_addr,  //output an address and fetch instruction from memory
    output  logic   [3:0]   imem_rmask,
    input   logic   [31:0]  imem_rdata,
    input   logic           imem_resp,
    output  logic   [31:0]  dmem_addr,
    output  logic   [3:0]   dmem_rmask,
    output  logic   [3:0]   dmem_wmask,
    input   logic   [31:0]  dmem_rdata,
    output  logic   [31:0]  dmem_wdata,
    input   logic           dmem_resp
);
    if_id_t if_id_pipeline_reg;     //ALL FOUR PIPELINE REGS
    id_ex_stage_reg_t id_ex_pipeline_reg;
    ex_mem_t ex_mem_pipeline_reg;
    mem_wb_t mem_wb_pipeline_reg;

    logic        wb_we;
    logic [4:0]  wb_rd;
    logic [31:0] wb_wdata;
    logic global_stall;
    logic dmem_stall;

    logic stall_if, stall_id, stall_ex, stall_mem, stall_wb;
    logic load_use_hazard;
    logic bubble_id_ex;
    logic flush_if, kill_id_ex;

    logic ex_branch_taken;
    logic [31:0] ex_branch_target;

    instr_t if_instr;
    logic [4:0] if_rs1, if_rs2;
    logic if_uses_rs1, if_uses_rs2;
    
    assign if_instr.word = if_id_pipeline_reg.inst;
    assign if_rs1 = if_instr.i_type.rs1;
    assign if_rs2 = if_instr.r_type.rs2;

    always_comb begin //determine if we are using source registers
        if_uses_rs1 = 1'b0;
        if_uses_rs2 = 1'b0;
        unique case (if_instr.i_type.opcode)
            op_b_reg   : begin if_uses_rs1 = 1'b1; if_uses_rs2 = 1'b1; end
            op_b_imm   : begin if_uses_rs1 = 1'b1; end
            op_b_load  : begin if_uses_rs1 = 1'b1; end
            op_b_store : begin if_uses_rs1 = 1'b1; if_uses_rs2 = 1'b1; end
            op_b_br    : begin if_uses_rs1 = 1'b1; if_uses_rs2 = 1'b1; end
            op_b_jalr  : begin if_uses_rs1 = 1'b1; end
            default    : begin if_uses_rs1 = 1'b0; if_uses_rs2 = 1'b0; end
        endcase
    end

    assign load_use_hazard = id_ex_pipeline_reg.valid_bit && id_ex_pipeline_reg.is_load &&
    (id_ex_pipeline_reg.rd != 5'd0) &&
    ((if_uses_rs1 && (id_ex_pipeline_reg.rd == if_rs1)) ||(if_uses_rs2 && (id_ex_pipeline_reg.rd == if_rs2)));

    assign global_stall = (~imem_resp) || dmem_stall;

    // load use stalls IF/ID, rest of pipeline can continue
    assign stall_if = global_stall || load_use_hazard;
    assign stall_id = global_stall || load_use_hazard;
    assign stall_ex = global_stall;
    assign stall_mem = global_stall;
    assign stall_wb = global_stall;

    assign bubble_id_ex = load_use_hazard && !global_stall;

    // flush if and ex stages 
    assign flush_if  = ex_branch_taken && !stall_ex;
    assign kill_id_ex = bubble_id_ex || flush_if;   //set ID/EX reg ctrl to 0 if load use


    if_stage u_if (
    .clk(clk),
    .rst(rst),
    .stall_if(stall_if),
    .flush_if(flush_if),
    .branch_taken(ex_branch_taken),
    .branch_target(ex_branch_target),
    .imem_addr(imem_addr),
    .imem_rmask(imem_rmask),
    .imem_rdata(imem_rdata),
    .imem_resp(imem_resp),
    .if_id_r(if_id_pipeline_reg)
);

    id_stage u_id (
    .clk(clk),
    .rst(rst),
    .stall_id(stall_id),
    .kill_id_ex(kill_id_ex),
    .if_id_r(if_id_pipeline_reg),
    .wb_we(wb_we),
    .wb_rd(wb_rd),
    .wb_wdata(wb_wdata),
    .id_ex_r(id_ex_pipeline_reg)
);

    ex_stage u_ex (
    .clk(clk),
    .rst(rst),
    .stall_ex(stall_ex),
    .id_ex_r(id_ex_pipeline_reg),
    .ex_mem_fwd(ex_mem_pipeline_reg),
    .mem_wb_fwd(mem_wb_pipeline_reg),
    .branch_taken_o(ex_branch_taken),
    .branch_target_o(ex_branch_target),
    .dmem_addr(dmem_addr),
    .dmem_rmask(dmem_rmask),
    .dmem_wmask(dmem_wmask),
    .dmem_wdata(dmem_wdata),
    .ex_mem_r(ex_mem_pipeline_reg)
);

    mem_stage u_mem (
        .clk        (clk),
        .rst        (rst),
        .stall_mem  (stall_mem),
        .ex_mem_r   (ex_mem_pipeline_reg),
        .dmem_rdata (dmem_rdata),
        .dmem_resp  (dmem_resp),
        .mem_wb_r   (mem_wb_pipeline_reg),
        .dmem_stall (dmem_stall)
    );

    wb_stage u_wb (
        .mem_wb_r (mem_wb_pipeline_reg),
        .stall_wb   (stall_wb),
        .wb_we    (wb_we),
        .wb_rd    (wb_rd),
        .wb_wdata (wb_wdata)
    );

endmodule : cpu
