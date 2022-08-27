/*
 * Copyright lizhirui
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2022-08-27     lizhirui     the first version
 */

module sd_reader #(
        parameter logic[4:0] CLK_DIV = 5'd2,
        parameter SIMULATION = 0
    )(
        input logic rstn,
        input logic clk,

        output logic sdclk,
        input logic sdcmdin,
        output logic sdcmdout,
        output logic sdcmdoe,
        input logic[3:0] sddat,

        output logic[1:0] card_type,
        output logic[3:0] card_stat,

        input logic rstart,
        input logic[31:0] rsector,
        input logic[22:0] rsector_num,
        output logic rsuspend,
        input logic rresume,
        output logic rresume_ack,
        output logic rbusy,
        output logic rdone,

        output logic outen,
        output logic[31:0] outaddr,
        output logic[7:0] outbyte
    );

    typedef enum logic[2:0]
    {
        UNKNOWN,
        SDv1,
        SDv2,
        SDHCv2,
        SDv1Maybe
    }card_type_t;

    typedef enum logic[3:0]
    {
        CMD0,//0-GO_IDLE_STATE
        CMD8,//1-SEND_IF_COND
        CMD55_41,//2-APP_CMD
        ACMD41,//3-SD_SEND_OP_COND
        CMD2,//4-ALL_SEND_CID,
        CMD3,//5-SEND_RELATIVE_ADDR,
        CMD7,//6-SELECT_CARD
        CMD55_6,//7-APP_CMD
        ACMD6,//8-SET_BUS_WIDTH
        CMD6,//9-SWITCH_FUNC
        CMD16,//a-SET_BLOCKLEN,
        CMD18,//b-READ_MULTIPLE_BLOCK
        CMD18_WAITING_RESPONSE,//c
        DATA_READING,//d
        DATA_CMD12,//e-STOP_TRANSMISSION for data
        DATA_WAITING_STOP//f-wait for data transmission stopping
    }card_state_t;

    typedef enum logic[2:0]
    {
        WAITING_BLOCK,//0
        READING_BLOCK_DATA,//1
        READING_BLOCK_TAIL,//2
        READY_TO_SUSPEND,//3
        SUSPEND,//4
        READ_FINISH,//5
        READ_STOP,//6
        READ_TIMEOUT//7
    }sddat_state_t;

    localparam logic[15:0] HIGHCLKDIV = 16'd1 << (CLK_DIV - 1);
    localparam logic[15:0] FASTCLKDIV = 16'd1 << CLK_DIV;
    localparam logic[15:0] SLOWCLKDIV = HIGHCLKDIV * (SIMULATION ? 16'd4 : 16'd125);

    logic sdclken;
    (* mark_debug = "true" *)logic start;
    logic[15:0] precnt;
    logic[5:0] cmd;
    logic[31:0] arg;
    logic[15:0] clkdiv;
    logic[31:0] rsectoraddr;
    (* mark_debug = "true" *)logic busy;
    (* mark_debug = "true" *)logic done;
    (* mark_debug = "true" *)logic timeout;
    (* mark_debug = "true" *)logic syntaxe;
    logic[31:0] resparg;
    (* mark_debug = "true" *)logic[15:0] rca;
    (* mark_debug = "true" *)logic sdclkl;
    logic[31:0] ridx;
    (* mark_debug = "true" *)logic[22:0] cur_relative_sector;
    (* mark_debug = "true" *)logic[22:0] sector_num;

    (* mark_debug = "true" *)card_type_t _card_type;

    (* mark_debug = "true" *)card_state_t cur_card_state, next_card_state;
    (* mark_debug = "true" *)sddat_state_t cur_sddat_state, next_sddat_state;

    assign rbusy = cur_card_state != CMD18;
    assign rdone = (cur_card_state == DATA_WAITING_STOP) && (cur_sddat_state == READ_STOP);

    assign card_type = _card_type[1:0];
    assign card_stat = cur_card_state[3:0];

    sdcmd_ctrl sdcmd_ctrl_inst(
        .rstn(rstn),
        .clk(clk),
        .sdclken(sdclken),
        .sdclk(sdclk),
        .sdcmdin(sdcmdin),
        .sdcmdout(sdcmdout),
        .sdcmdoe(sdcmdoe),
        .clkdiv(clkdiv),
        .start(start),
        .precnt(precnt),
        .cmd(cmd),
        .arg(arg),
        .busy(busy),
        .done(done),
        .timeout(timeout),
        .syntaxe(syntaxe),
        .resparg(resparg)
    );

    task automatic set_cmd(
            input _start,
            input logic[15:0] _precnt = 'b0,
            input logic[5:0] _cmd = 'b0,
            input logic[31:0] _arg = 'b0
        );

        start = _start;
        precnt = _precnt;
        cmd = _cmd;
        arg = _arg;
    endtask

    always_ff @(posedge clk) begin
        if(!rstn) begin
            sdclkl <= 'b0;
        end
        else begin
            sdclkl <= sdclk;
        end
    end

    always_ff @(posedge clk) begin
        if(!rstn) begin
            cur_card_state <= CMD0;
        end
        else begin
            cur_card_state <= next_card_state;
        end
    end

    always_comb begin
        next_card_state = cur_card_state;

        if(((busy && done && (cur_card_state != CMD18))) || ((~busy) && (cur_card_state == CMD18)) || (cur_card_state == DATA_READING) || (cur_card_state == DATA_WAITING_STOP)) begin
            case(cur_card_state)
                CMD0: begin
                    next_card_state = CMD8;
                end

                CMD8: begin
                    if(timeout) begin
                        next_card_state = CMD55_41;
                    end
                    else if((~syntaxe) && (resparg[7:0] == 8'haa)) begin
                        next_card_state = CMD55_41;
                    end
                end

                CMD55_41: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = ACMD41;
                    end
                end

                ACMD41: begin
                    if((~timeout) && (~syntaxe) && (resparg[31])) begin
                        next_card_state = CMD2;
                    end
                    else begin
                        next_card_state = CMD55_41;
                    end
                end

                CMD2: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = CMD3;
                    end
                end

                CMD3: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = CMD7;
                    end
                end

                CMD7: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = CMD55_6;
                    end
                end

                CMD55_6: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = ACMD6;
                    end
                end

                ACMD6: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = CMD6;
                    end
                    else begin
                        next_card_state = CMD55_6;
                    end
                end

                CMD6: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = CMD16;
                    end
                end

                CMD16: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = CMD18;
                    end
                end

                CMD18: begin
                    if(rstart) begin
                        next_card_state = CMD18_WAITING_RESPONSE;
                    end
                end

                CMD18_WAITING_RESPONSE: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = DATA_READING;
                    end
                end

                DATA_READING: begin
                    if(cur_sddat_state == READ_TIMEOUT) begin
                        next_card_state = CMD18_WAITING_RESPONSE;
                    end
                    else if(cur_sddat_state == READ_FINISH) begin
                        next_card_state = DATA_CMD12;
                    end
                end

                DATA_CMD12: begin
                    if((~timeout) && (~syntaxe)) begin
                        next_card_state = DATA_WAITING_STOP;
                    end
                end

                DATA_WAITING_STOP: begin
                    if(cur_sddat_state == READ_STOP) begin
                        next_card_state = CMD18;
                    end
                end
            endcase
        end
    end

    always_comb begin
        set_cmd(0);

        if((~busy) || (cur_card_state == DATA_READING)) begin
            case(cur_card_state)
                CMD0: begin
                    set_cmd(1, (SIMULATION ? 128 : 64000), 0, 'h00000000);
                end

                CMD8: begin
                    set_cmd(1, 24, 8, 'h000001aa);
                end

                CMD55_41: begin
                    set_cmd(1, 24, 55, 'h00000000);
                end

                ACMD41: begin
                    set_cmd(1, 24, 41, 'hc0100000);
                end

                CMD2: begin
                    set_cmd(1, 24, 2, 'h00000000);
                end

                CMD3: begin
                    set_cmd(1, 24, 3, 'h00000000);
                end

                CMD7: begin
                    set_cmd(1, 24, 7, {rca, 16'h0});
                end

                CMD55_6: begin
                    set_cmd(1, (SIMULATION ? 128 : 64000), 55, {rca, 16'h0});
                end

                ACMD6: begin
                    set_cmd(1, 24, 6, 'h00000002);
                end

                CMD6: begin
                    set_cmd(1, 24, 6, 'h8000fff1);
                end

                CMD16: begin
                    set_cmd(1, 200, 16, 'h00000200);
                end

                CMD18: begin
                    if(rstart) begin
                        set_cmd(1, 32, 18, rsector);
                    end
                end

                CMD18_WAITING_RESPONSE: begin
                    if(timeout || syntaxe || (~busy)) begin
                        set_cmd(1, 32, 18, rsectoraddr + cur_relative_sector);
                    end
                end

                DATA_CMD12: begin
                    set_cmd(1, 24, 12, 'h00000000);
                end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if(!rstn) begin
            rca <= 'b0;
        end
        else if((cur_card_state == CMD3) && (next_card_state == CMD7)) begin
            rca <= resparg[31:16];
        end
    end

    always_ff @(posedge clk) begin
        if(!rstn) begin
            _card_type <= UNKNOWN;
        end
        else if((cur_card_state == CMD8) && timeout) begin
            _card_type <= SDv1Maybe;
        end
        else if((cur_card_state == ACMD41) && (next_card_state == CMD2)) begin
            _card_type <= (_card_type == SDv1Maybe) ? SDv1 : (resparg[30] ? SDHCv2 : SDv2);
        end
    end

    always_ff @(posedge clk) begin
        if(!rstn) begin
            clkdiv <= SLOWCLKDIV;
        end
        else if((cur_card_state == CMD7) && (next_card_state == CMD55_6)) begin
            clkdiv <= FASTCLKDIV;
        end
        else if((cur_card_state == CMD6) && (next_card_state == CMD16)) begin
            clkdiv <= HIGHCLKDIV;
        end
    end

    always_ff @(posedge clk) begin
        if(!rstn) begin
            rsectoraddr <= 'b0;
            sector_num <= 'b0;
        end
        else if((~busy) && (cur_card_state == CMD18) && rstart) begin
            rsectoraddr <= rsector;
            sector_num <= rsector_num;
        end
    end

    always_ff @(posedge clk) begin
        if(!rstn) begin
            cur_relative_sector <= 'b0;
        end
        else if((~busy) && (cur_card_state == CMD18) && rstart) begin
            cur_relative_sector <= 'b0;
        end
        else if((~sdclkl) && sdclk && (cur_sddat_state == READING_BLOCK_TAIL) && (next_sddat_state == READY_TO_SUSPEND)) begin
            cur_relative_sector <= cur_relative_sector + 'b1;
        end
    end

    always_ff @(posedge clk) begin
        if(!rstn) begin
            cur_sddat_state <= WAITING_BLOCK;
        end
        else if((cur_card_state != CMD18_WAITING_RESPONSE) && (next_card_state == CMD18_WAITING_RESPONSE)) begin
            cur_sddat_state <= WAITING_BLOCK;
        end
        else if((cur_card_state != CMD18_WAITING_RESPONSE) &&
                (cur_card_state != DATA_READING) && (cur_card_state != DATA_CMD12) &&
                (cur_card_state != DATA_WAITING_STOP)) begin
            cur_sddat_state <= WAITING_BLOCK;
        end
        else if(cur_sddat_state == SUSPEND) begin
            cur_sddat_state <= next_sddat_state;
        end
        else if((~sdclkl) && sdclk) begin
            cur_sddat_state <= next_sddat_state;
        end
    end

    always_comb begin
        next_sddat_state = cur_sddat_state;

        case(cur_sddat_state)
            WAITING_BLOCK: begin
                if(!sddat[0]) begin
                    next_sddat_state = READING_BLOCK_DATA;
                end
                else if(ridx > 5000000) begin// according to SD datasheet, 1ms is enough to wait for DAT result, here, we set timeout to 5000000 clock cycles = 100ms (when SDCLK=50MHz)
                    next_sddat_state = READ_TIMEOUT;
                end
            end

            READING_BLOCK_DATA: begin
                if(ridx >= 512 * 2 - 1) begin
                    next_sddat_state = READING_BLOCK_TAIL;
                end
            end

            READING_BLOCK_TAIL: begin
                if(ridx >= 17 - 1) begin//crc16 and a stop bit
                    next_sddat_state = READY_TO_SUSPEND;
                end
            end

            READY_TO_SUSPEND: begin
                if(ridx >= 5 - 1) begin//wait for 5 cycle for safely stopping clock
                    next_sddat_state = SUSPEND;
                end
            end

            SUSPEND: begin//this is 6th cycle
                if(cur_relative_sector == sector_num) begin
                    next_sddat_state = READ_FINISH;
                end
                else if(rresume) begin
                    next_sddat_state = WAITING_BLOCK;
                end
            end

            READ_FINISH: begin
                if(cur_card_state == DATA_WAITING_STOP) begin
                    if(ridx >= 8 * 8 - 1) begin
                        next_sddat_state = READ_STOP;
                    end
                end
            end

            READ_STOP: begin
                next_sddat_state = WAITING_BLOCK;
            end

            READ_TIMEOUT: begin
                //wait cmd resend
            end
        endcase
    end

    assign rsuspend = (cur_sddat_state == SUSPEND);
    assign sdclken = (cur_sddat_state != SUSPEND);

    always_ff @(posedge clk) begin
        if(!rstn) begin
            rresume_ack <= 'b0;
        end
        else if((cur_sddat_state == SUSPEND) && rresume && (next_sddat_state != SUSPEND)) begin
            rresume_ack <= 'b1;
        end
        else begin
            rresume_ack <= 'b0;
        end
    end

    always_ff @(posedge clk) begin
        if(!rstn) begin
            ridx <= 'b0;
        end
        else if((cur_card_state != CMD18_WAITING_RESPONSE) &&
                (cur_card_state != DATA_READING) && (cur_card_state != DATA_CMD12) &&
                (cur_card_state != DATA_WAITING_STOP)) begin
            ridx <= 'b0;
        end
        else if((~sdclkl) && sdclk) begin
            if(cur_sddat_state != next_sddat_state) begin
                ridx <= 'b0;
            end
            else begin
                ridx <= ridx + 'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if(!rstn) begin
            outen <= 'b0;
            outaddr <= 'b0;
            outbyte <= 'b0;
        end
        else begin
            outen <= 'b0;
            outaddr <='b0;

            if((~sdclkl) && sdclk && (cur_sddat_state == READING_BLOCK_DATA)) begin
                if(ridx[0] == 'b0) begin
                    outbyte[7:4] <= sddat;
                end
                else begin
                    outen <= 'b1;
                    outaddr <= {cur_relative_sector, ridx[9:1]};
                    outbyte[3:0] <= sddat;
                end
            end
        end
    end
endmodule