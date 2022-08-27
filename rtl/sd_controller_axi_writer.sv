/*
 * Copyright lizhirui
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2022-08-27     lizhirui     the first version
 */

//this module will write 1KB data every time with 256-beat burst transaction
module sd_controller_axi_writer #(
        localparam BUFFER_ADDR_WIDTH = 8,
        localparam BUFFER_DATA_WIDTH = 32,
        localparam ADDR_WIDTH = 32
    )(
        input logic aclk,
        input logic aresetn,

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

        //buffer interface
        output logic[BUFFER_ADDR_WIDTH - 1:0] buffer_addr,
        input logic[BUFFER_DATA_WIDTH - 1:0] buffer_data,

        //control interface
        input logic[ADDR_WIDTH - 1:0] initial_addr,
        input logic start,
        output logic busy,
        output logic done,
        output logic err
    );

    typedef enum logic[1:0]
    {
        IDLE,
        SETUP,
        WRITING,
        WAITING_DONE
    }state_t;

    state_t cur_addr_state, next_addr_state;
    state_t cur_data_state, next_data_state;
    logic[ADDR_WIDTH - 1:0] cur_addr;

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            cur_addr_state <= IDLE;
        end
        else begin
            cur_addr_state <= next_addr_state;
        end
    end

    always_comb begin
        next_addr_state = cur_addr_state;

        case(cur_addr_state)
            IDLE: begin
                if(start && (!busy)) begin
                    next_addr_state = SETUP;
                end
            end

            SETUP: begin
                if(axi_awready) begin
                    next_addr_state = WAITING_DONE;
                end
            end

            WAITING_DONE: begin
                if(axi_bvalid) begin
                    next_addr_state = IDLE;
                end
            end
        endcase
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            cur_data_state <= IDLE;
        end
        else begin
            cur_data_state <= next_data_state;
        end
    end

    always_comb begin
        next_data_state = cur_data_state;

        case(cur_data_state)
            IDLE: begin
                if(start && (!busy)) begin
                    next_data_state = WRITING;
                end
            end

            WRITING: begin
                if((buffer_addr == '1) && axi_wready) begin
                    next_data_state = WAITING_DONE;
                end
            end

            WAITING_DONE: begin
                if(axi_bvalid) begin
                    next_data_state = IDLE;
                end
            end
        endcase
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            buffer_addr <= 'b0;
        end
        else if(cur_data_state == IDLE) begin
            buffer_addr <= 'b0;
        end
        else if(((cur_data_state == SETUP) || (cur_data_state == WRITING)) && axi_wready) begin
            buffer_addr <= buffer_addr + 'b1;
        end
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            cur_addr <= 'b0;
        end
        else if((cur_addr_state == IDLE) && (next_addr_state == SETUP)) begin
            cur_addr <= initial_addr;
        end
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            err <= 'b0;
        end
        else if((cur_addr_state == WAITING_DONE) && (next_addr_state == IDLE)) begin
            err <= |axi_bresp;
        end
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            axi_awvalid <= 'b0;
        end
        else if(next_addr_state == SETUP) begin
            axi_awvalid <= 'b1;
        end
        else begin
            axi_awvalid <= 'b0;
        end
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            axi_wvalid <= 'b0;
        end
        else if(next_data_state == WRITING) begin
            axi_wvalid <= 'b1;
        end
        else begin
            axi_wvalid <= 'b0;
        end
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            axi_bready <= 'b0;
        end
        else if(next_data_state == WAITING_DONE) begin
            axi_bready <= 'b1;
        end
        else begin
            axi_bready <= 'b0;
        end
    end

    assign axi_awaddr = cur_addr;
    assign axi_awprot = 'b0;
    assign axi_awburst = 'b01;
    assign axi_awlen = '1;
    assign axi_awsize = 'b10;

    assign axi_wdata = buffer_data;
    assign axi_wstrb = '1;
    assign axi_wlast = (buffer_addr == '1);

    assign busy = (cur_addr_state != IDLE) || (cur_data_state != IDLE);
    assign done = (cur_addr_state == WAITING_DONE) && (next_addr_state == IDLE);
endmodule