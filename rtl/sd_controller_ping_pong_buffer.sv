/*
 * Copyright lizhirui
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2022-08-27     lizhirui     the first version
 */

module sd_controller_ping_pong_buffer #(
        parameter ADDR_WIDTH = 8,
        parameter DATA_WIDTH = 32,
        parameter PROP_WIDTH = 32
    )(
        input logic aclk,
        input logic aresetn,

        input logic[ADDR_WIDTH - 1:0] waddr,
        input logic[DATA_WIDTH - 1:0] wdata,
        input logic we,
        input logic[PROP_WIDTH - 1:0] wprop,
        input logic wupdate,
        output logic wvalid,//write side is valid buffer

        input logic[ADDR_WIDTH - 1:0] raddr,
        output logic[DATA_WIDTH - 1:0] rdata,
        output logic[PROP_WIDTH - 1:0] rprop,
        input logic rupdate,
        output logic rvalid//read side is valid buffer
    );

    logic[DATA_WIDTH - 1:0] data_buffer[0:1][0:2**ADDR_WIDTH - 1];
    logic[PROP_WIDTH - 1:0] prop_buffer[0:1];
    logic cur_ptr;
    logic read_ptr;
    logic write_ptr;
    logic switch_condition;

    assign switch_condition = ((!rvalid) || rupdate) && ((!wvalid) || wupdate);
    assign read_ptr = cur_ptr;
    assign write_ptr = !cur_ptr;

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            cur_ptr <= 'b0;
        end
        else if(switch_condition) begin
            cur_ptr <= !cur_ptr;
        end
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            wvalid <= 'b1;
        end
        else if(switch_condition) begin
            wvalid <= 'b1;
        end
        else if(wupdate) begin
            wvalid <= 'b0;
        end
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            rvalid <= 'b0;
        end
        else if(switch_condition) begin
            rvalid <= 'b1;
        end
        else if(rupdate) begin
            rvalid <= 'b0;
        end
    end

    always_ff @(posedge aclk) begin
        if(wupdate && wvalid) begin
            prop_buffer[write_ptr] <= wprop;
        end
    end

    always_ff @(posedge aclk) begin
        if(we && wvalid) begin
            data_buffer[write_ptr][waddr] <= wdata;
        end
    end

    assign rdata = data_buffer[read_ptr][raddr];
    assign rprop = prop_buffer[read_ptr];
endmodule