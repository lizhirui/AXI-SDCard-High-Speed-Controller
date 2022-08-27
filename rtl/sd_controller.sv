/*
 * Copyright lizhirui
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2022-08-27     lizhirui     the first version
 */

module sd_controller #(
        parameter logic[2:0] CLK_DIV = 3'd2,//100MHz - 2, 200MHz - 3, 400MHz - 4
        parameter SIMULATION = 0
    )(
        input logic aclk,
        input logic aresetn,

        //axi-lite configuration interface(4KB)
        input logic axilite_awvalid,
        output logic axilite_awready,
        input logic[31:0] axilite_awaddr,
        input logic[2:0] axilite_awprot,
        input logic axilite_wvalid,
        output logic axilite_wready,
        input logic[31:0] axilite_wdata,
        input logic[3:0] axilite_wstrb,
        output logic axilite_bvalid,
        input logic axilite_bready,
        output logic[1:0] axilite_bresp,
        input logic axilite_arvalid,
        output logic axilite_arready,
        input logic[31:0] axilite_araddr,
        input logic[2:0] axilite_arprot,
        output logic axilite_rvalid,
        input logic axilite_rready,
        output logic[31:0] axilite_rdata,
        output logic[1:0] axilite_rresp,

        //axi master write-only interface
        output logic axi_awvalid,
        input logic axi_awready,
        output logic[31:0] axi_awaddr,
        output logic[2:0] axi_awprot,
        output logic[1:0] axi_awburst,
        output logic[7:0] axi_awlen,
        output logic[2:0] axi_awsize,

        output logic axi_wvalid,
        input logic axi_wready,
        output logic[31:0] axi_wdata,
        output logic[3:0] axi_wstrb,
        output logic axi_wlast,

        input logic axi_bvalid,
        output logic axi_bready,
        input logic[1:0] axi_bresp,

        output logic sdclk,
        input logic sdcmdin,
        output logic sdcmdout,
        output logic sdcmdoe,
        input logic[3:0] sddat,
        output logic[1:0] card_type,
        output logic[3:0] card_stat,

        output logic interrupt
    );

    localparam PP_ADDR_WIDTH = 8;
    localparam PP_DATA_WIDTH = 32;
    localparam PP_PROP_WIDTH = 32;//memory addr

    (* mark_debug = "true" *)logic[31:0] reg_ctrl;
    (* mark_debug = "true" *)logic[31:0] reg_status;
    (* mark_debug = "true" *)logic[31:0] reg_dstaddr;
    (* mark_debug = "true" *)logic[31:0] reg_startsector;
    (* mark_debug = "true" *)logic[22:0] reg_sectornum;
    (* mark_debug = "true" *)logic[31:0] reg_progress;

    logic interrupt_clear;
    logic reg_reset;

    logic[PP_ADDR_WIDTH - 1:0] waddr;
    logic[PP_DATA_WIDTH - 1:0] wdata;
    logic we;
    logic[PP_PROP_WIDTH - 1:0] wprop;
    logic wupdate;
    logic wvalid;

    logic[PP_ADDR_WIDTH - 1:0] raddr;
    logic[PP_DATA_WIDTH - 1:0] rdata;
    logic[PP_PROP_WIDTH - 1:0] rprop;
    logic rupdate;
    logic rvalid;

    logic rstart;
    logic rsuspend;
    logic rresume;
    logic rresume_ack;
    logic rbusy;
    logic rdone;

    logic outen;
    logic[31:0] outaddr;
    logic[7:0] outbyte;

    logic axi_writer_busy;
    logic axi_writer_done;
    logic axi_writer_err;

    logic[31:0] cur_dstaddr;

    logic running;
    logic last_running;
    logic ready_to_run;

    logic[31:0] last_reg_ctrl;
    logic axi_writer_done_found;
    logic[31:0] sdc_data_buffer;
    logic[31:0] sdc_data_buffer_next;

    logic sys_rstn;

    assign sys_rstn = aresetn & (~reg_reset);

    sd_controller_regfile sd_controller_regfile_inst(
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

        .reg_ctrl(reg_ctrl),
        .reg_status(reg_status),
        .reg_dstaddr(reg_dstaddr),
        .reg_startsector(reg_startsector),
        .reg_sectornum(reg_sectornum),
        .reg_progress(reg_progress),
        .interrupt_clear(interrupt_clear),
        .reg_reset(reg_reset)
    );

    sd_controller_ping_pong_buffer #(
        .ADDR_WIDTH(PP_ADDR_WIDTH),
        .DATA_WIDTH(PP_DATA_WIDTH),
        .PROP_WIDTH(PP_PROP_WIDTH)
    )sd_controller_ping_pong_buffer_inst(
        .aclk(aclk),
        .aresetn(sys_rstn),

        .waddr(waddr),
        .wdata(wdata),
        .we(we),
        .wprop(wprop),
        .wupdate(wupdate),
        .wvalid(wvalid),

        .raddr(raddr),
        .rdata(rdata),
        .rprop(rprop),
        .rupdate(rupdate),
        .rvalid(rvalid)
    );

    sd_reader #(
        .CLK_DIV(CLK_DIV),
        .SIMULATION(SIMULATION)
    )sd_reader_inst(
        .rstn(sys_rstn),
        .clk(aclk),

        .sdclk(sdclk),
        .sdcmdin(sdcmdin),
        .sdcmdout(sdcmdout),
        .sdcmdoe(sdcmdoe),
        .sddat(sddat),

        .card_type(card_type),
        .card_stat(card_stat),

        .rstart(rstart),
        .rsector(reg_startsector),
        .rsector_num(reg_sectornum),
        .rsuspend(rsuspend),
        .rresume(rresume),
        .rresume_ack(rresume_ack),
        .rbusy(rbusy),
        .rdone(rdone),

        .outen(outen),
        .outaddr(outaddr),
        .outbyte(outbyte)
    );

    sd_controller_axi_writer sd_controller_axi_writer_inst(
        .aclk(aclk),
        .aresetn(sys_rstn),

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

        .buffer_addr(raddr),
        .buffer_data(rdata),

        .initial_addr(rprop),
        .start(rvalid),
        .busy(axi_writer_busy),
        .done(axi_writer_done),
        .err(axi_writer_err)
    );

    always_ff @(posedge aclk) begin
        if(!sys_rstn) begin
            sdc_data_buffer <= 'b0;
        end
        else if(outen) begin
            sdc_data_buffer <= sdc_data_buffer_next;
        end
    end

    assign sdc_data_buffer_next = {outbyte, sdc_data_buffer[31:8]};

    assign rresume = wvalid;
    assign waddr = outaddr[31:2];
    assign wdata = sdc_data_buffer_next;
    assign we = outen && (outaddr[1:0] == 'b11);
    assign wprop = cur_dstaddr + {outaddr[31:10], 10'b0};
    assign wupdate = outen && (outaddr[9:0] == '1);
    assign rupdate = axi_writer_done;
    assign ready_to_run = reg_ctrl[0] && (reg_sectornum != 'b0);

    always_ff @(posedge aclk) begin
        if(!sys_rstn) begin
            axi_writer_done_found <= 'b0;
        end
        else if(axi_writer_done) begin
            axi_writer_done_found <= 'b1;
        end
        else if(ready_to_run) begin
            axi_writer_done_found <= 'b0;
        end
    end

    always_ff @(posedge aclk) begin
        if(!sys_rstn) begin
            running <= 'b0;
        end
        else if(ready_to_run) begin
            running <= 'b1;
        end
        else if((!rbusy) && axi_writer_done_found) begin
            running <= 'b0;
        end
    end

    always_ff @(posedge aclk) begin
        if(!sys_rstn) begin
            cur_dstaddr <= 'b0;
        end
        else if(ready_to_run) begin
            cur_dstaddr <= reg_dstaddr;
        end
    end

    always_ff @(posedge aclk) begin
        if(!sys_rstn) begin
            last_running <= 'b0;
        end
        else begin
            last_running <= running;
        end
    end

    always_ff @(posedge aclk) begin
        if(!sys_rstn) begin
            interrupt <= 'b0;
        end
        else if(last_running && (!running) && reg_ctrl[1]) begin
            interrupt <= 'b1;
        end
        else if(interrupt_clear) begin
            interrupt <= 'b0;
        end
    end

    assign reg_status = {card_stat, card_type, interrupt, axi_writer_err, (running | rstart)};

    always_ff @(posedge aclk) begin
        if(!sys_rstn) begin
            reg_progress <= 'b0;
        end
        else if((!last_running) && running) begin
            reg_progress <= 'b0;
        end
        else if(running && axi_writer_done) begin
            reg_progress <= (rprop - cur_dstaddr) + unsigned'('d1024);
        end
    end

    always_ff @(posedge aclk) begin
        if(!sys_rstn) begin
            last_reg_ctrl <= 'b0;
        end
        else begin
            last_reg_ctrl <= reg_ctrl;
        end
    end

    always_ff @(posedge aclk) begin
        if(!sys_rstn) begin
            rstart <= 'b0;
        end
        else if((~last_running) && running) begin
            rstart <= 'b1;
        end
        else if(rdone) begin
            rstart <= 'b0;
        end
    end
endmodule