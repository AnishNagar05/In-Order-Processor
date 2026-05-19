module regfile
(
    input   logic           clk,
    input   logic           rst,
    input   logic           regf_we,    //if 1, we write to reg file
    input   logic   [31:0]  rd_v,   //value to write if writing
    input   logic   [4:0]   rs1_s, rs2_s, rd_s, //source registers, and dest register if writing back

    output  logic   [31:0]  rs1_v, rs2_v    //
);

    logic   [31:0]  data [32];  //32 regs

    always_ff @(posedge clk) begin  //WRITE logic
        if (rst) begin
            for (integer i = 0; i < 32; i++) begin
                data[i] <= '0;
            end
        end else if (regf_we && (rd_s != 5'd0)) begin   //if write enable and not reg 0
            data[rd_s] <= rd_v;                     //destination reg gets value passed in
        end
    end

    always_comb begin      //read logic
        if (rst) begin                  //if reset, set values of source regs to 0
            rs1_v = 'x;
            rs2_v = 'x;
        end else begin
            rs1_v = (rs1_s != 5'd0) ? data[rs1_s] : '0;    //get value for source regs as long as not 0
            rs2_v = (rs2_s != 5'd0) ? data[rs2_s] : '0;

            if (regf_we && (rd_s != 5'd0) && (rd_s == rs1_s))
                rs1_v = rd_v;
            if (regf_we && (rd_s != 5'd0) && (rd_s == rs2_s))
                rs2_v = rd_v;
        end
    end

endmodule : regfile