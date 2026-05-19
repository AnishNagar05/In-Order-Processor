module if_stage
import rv32i_types::*; 
(
  input  logic        clk,
  input  logic        rst,

  input  logic        stall_if,    
  input  logic        flush_if, 

  input  logic [31:0] imem_rdata,
  input  logic        imem_resp,

  input  logic        branch_taken, //branch logic
  input  logic [31:0] branch_target,
  
  output logic [31:0] imem_addr,
  output logic [3:0]  imem_rmask,
  
  output if_id_t      if_id_r
);

  logic [31:0] pc_reg, pc_next;  
  logic [63:0] order_reg, order_next;
  if_id_t      if_id_n; 

  assign imem_rmask = rst ? 4'b0000 : 4'b1111;

  always_comb begin   
    pc_next = pc_reg + 32'd4; 
    if (branch_taken) begin //we receive branch taken signal from ex stage
        pc_next = branch_target;
    end
  end

  always_comb begin //if response, increment address we got from imem 
    if (imem_resp && !stall_if) begin  
      imem_addr = pc_next;
    end else begin 
      imem_addr = pc_reg;
    end
  end
 
  always_comb begin //setup pipeline reg
    if_id_n = '0; 
    if_id_n.valid = 1'b0;
    if_id_n.valid_bit = 1'b0;

    if (imem_resp) begin  
      if_id_n.valid = 1'b1;
      if_id_n.valid_bit = 1'b1; 
      if_id_n.pc    = pc_reg; 
      if_id_n.inst  = imem_rdata;
      if_id_n.order = order_reg;  
    end 
  end

  always_comb begin
    order_next = order_reg;
    if (imem_resp && !stall_if) order_next = order_reg + 64'd1; //increment order if we aren't stalled
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      pc_reg    <= 32'haaaaa000;  
      if_id_r <= '0;  
      if_id_r.valid_bit <= 1'b0;  
      order_reg <= 64'd0;
    end else if (flush_if) begin
      if_id_r <= '0;
      if_id_r.valid_bit <= 1'b0;
      pc_reg <= branch_target;
      order_reg <= if_id_r.valid_bit ? if_id_r.order : order_reg; //reclaim flushed instr order 
    end else if (!stall_if) begin 
      if_id_r <= if_id_n; 
      pc_reg    <= pc_next; 
      order_reg <= order_next;
    end else begin
      pc_reg    <= pc_reg;
      if_id_r <= if_id_r; 
      order_reg <= order_reg;
    end
  end

endmodule