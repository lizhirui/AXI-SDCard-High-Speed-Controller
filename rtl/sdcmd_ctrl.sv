/*
 * Copyright lizhirui
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2022-08-27     lizhirui     the first version
 */

module sdcmd_ctrl(
        input logic rstn,
        input logic clk,

        input logic sdclken,
        output logic sdclk,

        input logic sdcmdin,
        output logic sdcmdout,
        output logic sdcmdoe,

        input logic[15:0] clkdiv,
        input logic start,
        input logic[15:0] precnt,
        input logic[5:0] cmd,
        input logic[31:0] arg,

        output logic busy,
        output logic done,
        output logic timeout,
        output logic syntaxe,
        output logic[31:0] resparg
    );

    function automatic logic[6:0] crc7(
            input logic[6:0] crc,
            input logic inbit
        );

        return {crc[5:0], crc[6] ^ inbit} ^ {3'b0, crc[6] ^ inbit, 3'b0};
    endfunction

    logic[5:0] req_cmd;
    logic[31:0] req_arg;
    logic[6:0] req_crc;
    logic[51:0] request;

    logic[17:0] clkdivr;
    logic[17:0] clkcnt;
    logic[15:0] cnt1;
    logic[5:0] cnt2;
    logic[1:0] cnt3;
    logic[31:0] cnt4;
    logic[7:0] cnt5;

    logic sdclk_to_0;
    logic sdclk_to_1;

    struct packed{
        logic st;
        logic[5:0] cmd;
        logic[31:0] arg;
    }response;

    assign request = {6'b111101, req_cmd, req_arg, req_crc, 1'b1};
    assign resparg = response.arg;

    always_ff @(posedge clk) begin
        if(!rstn) begin
            clkdivr <= 'b0;
        end
        else if(clkcnt == 'b0) begin
            clkdivr <= {3'h0, clkdiv[15:1]};
        end
    end

    always_ff @(posedge clk) begin
        if(!rstn) begin
            clkcnt <= 'b0;
        end
        else if((!sdclken) && (clkcnt == 'b0)) begin
            clkcnt <= 'b0;
        end
        else if(clkcnt < ({clkdivr[16:0], 1'b0} - 'b1)) begin
            clkcnt <= clkcnt + 'b1;
        end
        else begin
            clkcnt <= 'b0;
        end
    end

    always_comb begin
        if(!rstn) begin
            sdclk_to_0 = 'b0;
            sdclk_to_1 = 'b0;
        end
        else if(sdclken || (clkcnt != 'b0)) begin
            if(clkcnt == 'b0) begin
                sdclk_to_0 = 'b1;
                sdclk_to_1 = 'b0;
            end
            else if(clkcnt == clkdivr[16:0]) begin
                sdclk_to_0 = 'b0;
                sdclk_to_1 = 'b1;
            end
            else begin
                sdclk_to_0 = 'b0;
                sdclk_to_1 = 'b0;
            end
        end
        else begin
            sdclk_to_0 = 'b0;
            sdclk_to_1 = 'b0;
        end
    end

    always_ff @(posedge clk) begin
        if(!rstn) begin
            sdclk <= 'b0;
        end
        else if(sdclken || (clkcnt != 'b0)) begin
            if(sdclk_to_0) begin
                sdclk <= 'b0;
            end
            else if(sdclk_to_1) begin
                sdclk <= 'b1;
            end
        end
        else begin
            sdclk <= 'b0;
        end
    end

    always_ff @(posedge clk) begin
        if(~rstn) begin
            {busy, done, timeout, syntaxe} <= 'b0;
            {sdcmdoe, sdcmdout} <= 2'b01;
            {req_cmd, req_arg, req_crc} <= 'b0;
            response <= 'b0;
            cnt1 <= 'b0;
            cnt2 <= '1;
            cnt3 <= 'b0;
            cnt4 <= 'b0;
            cnt5 <= '1;
        end
        else begin
            {done, timeout, syntaxe} <= 'b0;

            if(busy && done) begin
                busy <= 'b0;
            end
            else if((~busy) && start) begin
                busy <= 'b1;
                req_cmd <= cmd;
                req_arg <= arg;
                req_crc <= 'b0;
                cnt1 <= precnt;
                cnt2 <= 6'd51;
                cnt3 <= 2'd2;
                cnt4 <= 'd250;
                cnt5 <= 8'd134;
            end
            else begin
                if(sdclk_to_0) begin
                    {sdcmdoe, sdcmdout} <= 2'b01;

                    if(cnt1 != 'b0) begin
                        cnt1 <= cnt1 - 'b1;
                    end
                    else if(cnt2 != '1) begin
                        cnt2 <= cnt2 - 'b1;
                        {sdcmdoe, sdcmdout} <= {1'b1, request[cnt2]};

                        if((cnt2 >= 8) && (cnt2 < 48)) begin
                            req_crc <= crc7(req_crc, request[cnt2]);
                        end
                    end
                end
                else if(sdclk_to_1) begin
                    if((cnt1 == 'b0) && (cnt2 == '1)) begin
                        if(cnt3 != 'b0) begin
                            cnt3 <= cnt3 - 'b1;
                        end
                        else if(cnt4 != 'b0) begin
                            cnt4 <= cnt4 - 'b1;

                            if(~sdcmdin) begin//found start bit
                                cnt4 <= 'b0;
                            end
                            else if(cnt4 == 'b1) begin//timeout
                                done <= 'b1;
                                timeout <= 'b1;
                                syntaxe <= 'b0;
                            end
                        end
                        else if(cnt5 != '1) begin
                            cnt5 <= cnt5 - 'b1;

                            if(cnt5 >= 'd96) begin
                                response <= {response[37:0], sdcmdin};
                            end
                            else if(cnt5 == '0) begin
                                done <= 'b1;
                                timeout <= 'b0;
                                syntaxe <= response.st || ((response.cmd != req_cmd) && (response.cmd != '1) && (response.cmd != 'b0));
                            end
                        end
                    end
                end
            end
        end
    end

endmodule
