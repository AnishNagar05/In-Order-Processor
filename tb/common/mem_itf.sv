interface mem_itf #(
    parameter               CHANNELS = 1,
    parameter               DWIDTH = 32,
    parameter               MWIDTH = DWIDTH / 8
)(
    input   bit             clk,
    input   bit             rst
);

    logic   [31:0]          addr    [CHANNELS];
    logic   [MWIDTH-1:0]    rmask   [CHANNELS];
    logic   [MWIDTH-1:0]    wmask   [CHANNELS];
    logic   [DWIDTH-1:0]    rdata   [CHANNELS];
    logic   [DWIDTH-1:0]    wdata   [CHANNELS];
    logic                   resp    [CHANNELS];

    bit                     error = 1'b0;

    modport dut (
        input               clk,
        input               rst,
        output              addr,
        output              rmask,
        output              wmask,
        input               rdata,
        output              wdata,
        input               resp
    );

    modport mem (
        input               clk,
        input               rst,
        input               addr,
        input               rmask,
        input               wmask,
        output              rdata,
        input               wdata,
        output              resp,
        output              error
    );

endinterface