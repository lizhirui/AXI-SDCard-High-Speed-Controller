/*
 * Copyright lizhirui
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2022-08-27     lizhirui     the first version
 */

module sd_controller_wrapper #(
        parameter SIMULATION = 0
    )(
        input wire aclk,
        input wire aresetn,

        //axi-lite configuration interface(4KB)
        input wire axilite_awvalid,
        output wire axilite_awready,
        input wire[31:0] axilite_awaddr,
        input wire[2:0] axilite_awprot,
        input wire axilite_wvalid,
        output wire axilite_wready,
        input wire[31:0] axilite_wdata,
        input wire[3:0] axilite_wstrb,
        output wire axilite_bvalid,
        input wire axilite_bready,
        output wire[1:0] axilite_bresp,
        input wire axilite_arvalid,
        output wire axilite_arready,
        input wire[31:0] axilite_araddr,
        input wire[2:0] axilite_arprot,
        output wire axilite_rvalid,
        input wire axilite_rready,
        output wire[31:0] axilite_rdata,
        output wire[1:0] axilite_rresp,

        //axi master write-only interface
        output wire axi_awvalid,
        input wire axi_awready,
        output wire[31:0] axi_awaddr,
        output wire[2:0] axi_awprot,
        output wire[1:0] axi_awburst,
        output wire[7:0] axi_awlen,
        output wire[2:0] axi_awsize,

        output wire axi_wvalid,
        input wire axi_wready,
        output wire[31:0] axi_wdata,
        output wire[3:0] axi_wstrb,
        output wire axi_wlast,

        input wire axi_bvalid,
        output wire axi_bready,
        input wire[1:0] axi_bresp,

        output wire sdclk,
        inout wire sdcmd,
        input wire[3:0] sddat,
        output wire[1:0] card_type,
        output wire[3:0] card_stat,

        output wire interrupt,

        output wire test_sdclk,
        output wire test_sdcmd,
        output wire[3:0] test_sddat
    );

    wire sdclk_bufg;
    wire sdclkout;
    wire sdcmdout;
    wire sdcmdoe;
    reg sdcmdoe_reg;
    reg sdcmdoe_reg2;
    reg sdcmdoe_reg_sdcmdin_iob;
    reg sdcmdoe_reg_sdcmdin_iob_sync;
    reg sdcmdout_sdclk;
    wire sdcmdout_ddr;
    wire sdcmdin_noreg;
    (* iob = "true" *)reg sdcmdin_iob;
    reg sdcmdin_iob_sync;
    wire[3:0] sddat_noreg;
    (* iob = "true" *)reg[3:0] sddat_iob;
    reg[3:0] sddat_iob_sync;

    genvar i;

    BUFG BUFG_sdclk_inst(
        .I(sdclkout),
        .O(sdclk_bufg)
    );

    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"), // "OPPOSITE_EDGE" or "SAME_EDGE" 
        .INIT(1'b0),    // Initial value of Q: 1'b0 or 1'b1
        .SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC" 
    )ODDR_sdclk_inst (
        .Q(sdclk),   // 1-bit DDR output
        .C(sdclk_bufg),   // 1-bit clock input
        .CE(1'b1), // 1-bit clock enable input
        .D1(1'b0), // 1-bit data input (positive edge)
        .D2(1'b1), // 1-bit data input (negative edge)
        .R(1'b0),   // 1-bit reset
        .S(1'b0)    // 1-bit set
    );

    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"), // "OPPOSITE_EDGE" or "SAME_EDGE" 
        .INIT(1'b0),    // Initial value of Q: 1'b0 or 1'b1
        .SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC" 
    )ODDR_sdcmdout_inst (
        .Q(sdcmdout_ddr),   // 1-bit DDR output
        .C(sdclk_bufg),   // 1-bit clock input
        .CE(1'b1), // 1-bit clock enable input
        .D1(sdcmdout_sdclk), // 1-bit data input (positive edge)
        .D2(sdcmdout_sdclk), // 1-bit data input (negative edge)
        .R(1'b0),   // 1-bit reset
        .S(1'b0)    // 1-bit set
    );

    always @(posedge sdclk_bufg) begin
        sdcmdout_sdclk <= sdcmdout;
    end

    always @(posedge sdclk_bufg) begin
        sdcmdoe_reg <= ~sdcmdoe;
        sdcmdoe_reg2 <= sdcmdoe_reg;
    end

    IOBUF #(
        .DRIVE(12),
        .IBUF_LOW_PWR("FALSE"),
        .IOSTANDARD("DEFAULT"),
        .SLEW("FAST")
    )iobuf_sdcmd_inst(
        .O(sdcmdin_noreg),
        .IO(sdcmd),
        .I(sdcmdout_ddr),
        .T(sdcmdoe_reg2)
    );

    always @(posedge sdclk_bufg) begin
        sdcmdin_iob <= sdcmdin_noreg;
        sdcmdoe_reg_sdcmdin_iob <= sdcmdoe_reg2;
    end

    always @(posedge aclk) begin
        sdcmdin_iob_sync <= sdcmdin_iob;
        sdcmdoe_reg_sdcmdin_iob_sync <= sdcmdoe_reg_sdcmdin_iob;
    end

    generate
        for(i = 0;i < 4;i = i + 1) begin: sddat_ibuf_generate
            IBUF IBUF_inst(
                .I(sddat[i]),
                .O(sddat_noreg[i])
            );
        end
    endgenerate

    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"), // "OPPOSITE_EDGE" or "SAME_EDGE" 
        .INIT(1'b0),    // Initial value of Q: 1'b0 or 1'b1
        .SRTYPE("SYNC") // Set/Reset type: "SYNC" or "ASYNC" 
    )ODDR_test_sdclk_inst (
        .Q(test_sdclk),   // 1-bit DDR output
        .C(sdclk_bufg),   // 1-bit clock input
        .CE(1'b1), // 1-bit clock enable input
        .D1(1'b0), // 1-bit data input (positive edge)
        .D2(1'b1), // 1-bit data input (negative edge)
        .R(1'b0),   // 1-bit reset
        .S(1'b0)    // 1-bit set
    );

    //assign test_sdclk = sdclkout;
    assign test_sdcmd = !sdcmdoe_reg_sdcmdin_iob_sync ? sdcmdout_sdclk : sdcmdin_iob_sync;
    //assign test_sddat = sddat_iob_sync;
    assign test_sddat = card_stat;

    always @(posedge sdclk_bufg) begin
        sddat_iob <= sddat_noreg;
    end

    always @(posedge aclk) begin
        sddat_iob_sync <= sddat_iob;
    end

    sd_controller #(
        .CLK_DIV(5'd2),
        .SIMULATION(SIMULATION)
    )sd_controller_inst(
        .aclk(aclk),
        .aresetn(aresetn),
        
        .axilite_awvalid(axilite_awvalid),
        .axilite_awready(axilite_awready),
        .axilite_awaddr(axilite_awaddr),
        .axilite_awprot(axilite_awprot),
        .axilite_wvalid(axilite_wvalid),
        .axilite_wready(axilite_wready),
        .axilite_wdata(axilite_wdata),
        .axilite_wstrb(axilite_wstrb),
        .axilite_bvalid(axilite_bvalid),
        .axilite_bready(axilite_bready),
        .axilite_bresp(axilite_bresp),
        .axilite_arvalid(axilite_arvalid),
        .axilite_arready(axilite_arready),
        .axilite_araddr(axilite_araddr),
        .axilite_arprot(axilite_arprot),
        .axilite_rvalid(axilite_rvalid),
        .axilite_rready(axilite_rready),
        .axilite_rdata(axilite_rdata),
        .axilite_rresp(axilite_rresp),

        .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),
        .axi_awaddr(axi_awaddr),
        .axi_awprot(axi_awprot),
        .axi_awburst(axi_awburst),
        .axi_awlen(axi_awlen),
        .axi_awsize(axi_awsize),

        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready),
        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wlast(axi_wlast),

        .axi_bvalid(axi_bvalid),
        .axi_bready(axi_bready),
        .axi_bresp(axi_bresp),

        .sdclk(sdclkout),
        .sdcmdin(sdcmdoe_reg_sdcmdin_iob_sync ? sdcmdin_iob_sync : 1'b1),
        .sdcmdout(sdcmdout),
        .sdcmdoe(sdcmdoe),
        .sddat(sddat_iob_sync),
        .card_type(card_type),
        .card_stat(card_stat),

        .interrupt(interrupt)
    );
endmodule