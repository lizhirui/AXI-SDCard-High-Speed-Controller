/*
 * Copyright lizhirui
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2022-08-27     lizhirui     the first version
 */

module sd_controller_regfile(
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

        output logic[31:0] reg_ctrl,
        input logic[31:0] reg_status,
        output logic[31:0] reg_dstaddr,
        output logic[31:0] reg_startsector,
        output logic[22:0] reg_sectornum,
        input logic[31:0] reg_progress,
        output logic interrupt_clear,
        output logic reg_reset
    );

    typedef enum logic
    {
        IDLE,
        RESPONSE
    }state_t;

    state_t cur_read_state, next_read_state;
    state_t cur_write_state, next_write_state;
    logic[11:0] cur_write_addr;
    logic cur_write_addr_valid;
    logic[31:0] cur_write_data;
    logic cur_write_data_valid;

    //--------------------read channel----------------------------------
    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            cur_read_state <= IDLE;
        end
        else begin
            cur_read_state <= next_read_state;
        end
    end

    always_comb begin
        next_read_state = cur_read_state;

        case(cur_read_state)
            IDLE: begin
                if(axilite_arvalid) begin
                    next_read_state = RESPONSE;
                end
            end

            RESPONSE: begin
                if(axilite_rready) begin
                    next_read_state = IDLE;
                end
            end
        endcase
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            axilite_arready <= 'b0;
        end
        else if(next_read_state == IDLE) begin
            axilite_arready <= 'b1;
        end
        else begin
            axilite_arready <= 'b0;
        end
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            axilite_rvalid <= 'b0;
        end
        else if(next_read_state == RESPONSE) begin
            axilite_rvalid <= 'b1;
        end
        else begin
            axilite_rvalid <= 'b0;
        end
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            axilite_rdata <= 'b0;
            axilite_rresp <= 'b0;
        end
        else if((cur_read_state == IDLE) && (next_read_state == RESPONSE)) begin
            case(axilite_araddr[11:0])
                'h0: begin
                    axilite_rdata <= reg_ctrl;
                    axilite_rresp <= 'b0;
                end

                'h4: begin
                    axilite_rdata <= reg_status;
                    axilite_rresp <= 'b0;
                end

                'h8: begin
                    axilite_rdata <= reg_dstaddr;
                    axilite_rresp <= 'b0;
                end

                'hc: begin
                    axilite_rdata <= reg_startsector;
                    axilite_rresp <= 'b0;
                end

                'h10: begin
                    axilite_rdata <= reg_sectornum;
                    axilite_rresp <= 'b0;
                end

                'h14: begin
                    axilite_rdata <= reg_progress;
                    axilite_rresp <= 'b0;
                end

                default: begin
                    axilite_rdata <= 'b0;
                    axilite_rresp <= 'b10;//SLVERR
                end
            endcase
        end
    end
    //------------------------------------------------------------------

    //-------------------write channel----------------------------------
    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            cur_write_state <= IDLE;
        end
        else begin
            cur_write_state <= next_write_state;
        end
    end

    always_comb begin
        next_write_state = cur_write_state;

        case(cur_write_state)
            IDLE: begin
                if(cur_write_addr_valid && cur_write_data_valid) begin
                    next_write_state = RESPONSE;
                end
            end

            RESPONSE: begin
                if(axilite_bready) begin
                    next_write_state = IDLE;
                end
            end
        endcase
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            cur_write_addr <= 'b0;
            cur_write_addr_valid <= 'b0;
        end
        else if((cur_write_state == IDLE) && axilite_awvalid && axilite_awready) begin
            cur_write_addr <= axilite_awaddr;
            cur_write_addr_valid <= 'b1;
        end
        else if((cur_write_state == RESPONSE) && (next_write_state == IDLE)) begin
            cur_write_addr_valid <= 'b0;
        end
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            cur_write_data <= 'b0;
            cur_write_data_valid <= 'b0;
        end
        else if((cur_write_state == IDLE) && axilite_wvalid && axilite_wready) begin
            cur_write_data <= axilite_wdata;
            cur_write_data_valid <= 'b1;
        end
        else if((cur_write_state == RESPONSE) && (next_write_state == IDLE)) begin
            cur_write_data_valid <= 'b0;
        end
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            axilite_awready <= 'b0;
        end
        else if((next_write_state == IDLE) && (!cur_write_addr_valid)) begin
            axilite_awready <= 'b1;
        end
        else begin
            axilite_awready <= 'b0;
        end
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            axilite_wready <= 'b0;
        end
        else if((next_write_state == IDLE) && (!cur_write_data_valid)) begin
            axilite_wready <= 'b1;
        end
        else begin
            axilite_wready <= 'b0;
        end
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            reg_ctrl <= 'b0;
            reg_dstaddr <= 'b0;
            reg_startsector <= 'b0;
            reg_sectornum <= 'b0;
            interrupt_clear <= 'b0;
            reg_reset <= 'b0;
        end
        else if((cur_write_state == IDLE) && (next_write_state == RESPONSE)) begin
            case(cur_write_addr[11:0])
                'h0: begin
                    reg_ctrl <= cur_write_data[1:0];
                    axilite_bresp <= 'b0;
                end

                'h4: begin
                    interrupt_clear <= cur_write_data[2];
                    axilite_bresp <= 'b0;
                end

                'h8: begin
                    reg_dstaddr <= cur_write_data;
                    axilite_bresp <= 'b0;
                end

                'hc: begin
                    reg_startsector <= cur_write_data;
                    axilite_bresp <= 'b0;
                end

                'h10: begin
                    reg_sectornum <= {cur_write_data[22:1], 1'b0};
                    axilite_bresp <= 'b0;
                end

                'h14: begin
                    axilite_bresp <= 'b10;//SLVERR
                end

                'h18: begin
                    reg_reset <= cur_write_data[0];
                    axilite_bresp <= 'b0;
                end

                default: begin
                    axilite_bresp <= 'b10;//SLVERR
                end
            endcase
        end
        else begin
            reg_ctrl[0] <= 'b0;
            interrupt_clear <= 'b0;
            reg_reset <= 'b0;
        end
    end

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            axilite_bvalid <= 'b0;
        end
        else if(next_write_state == RESPONSE) begin
            axilite_bvalid <= 'b1;
        end
        else begin
            axilite_bvalid <= 'b0;
        end
    end
    //------------------------------------------------------------------
endmodule