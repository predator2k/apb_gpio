// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

`define REG_PADDIR_00_31    5'b00000 //BASEADDR+0x00
`define REG_GPIOEN_00_31    5'b00001 //BASEADDR+0x04
`define REG_PADIN_00_31     5'b00010 //BASEADDR+0x08
`define REG_PADOUT_00_31    5'b00011 //BASEADDR+0x0C
`define REG_PADOUTSET_00_31 5'b00100 //BASEADDR+0x10
`define REG_PADOUTCLR_00_31 5'b00101 //BASEADDR+0x14
`define REG_INTEN_00_31     5'b00110 //BASEADDR+0x18
`define REG_INTTYPE_00_15   5'b00111 //BASEADDR+0x1C
`define REG_INTTYPE_16_31   5'b01000 //BASEADDR+0x20
`define REG_INTSTATUS_00_31 5'b01001 //BASEADDR+0x24
`define REG_PADCFG_00_07    5'b01010 //BASEADDR+0x28
`define REG_PADCFG_08_15    5'b01011 //BASEADDR+0x2C
`define REG_PADCFG_16_23    5'b01100 //BASEADDR+0x30
`define REG_PADCFG_24_31    5'b01101 //BASEADDR+0x34

`define REG_PADDIR_32_63    5'b01110 //BASEADDR+0x38
`define REG_GPIOEN_32_63    5'b01111 //BASEADDR+0x3C
`define REG_PADIN_32_63     5'b10000 //BASEADDR+0x40
`define REG_PADOUT_32_63    5'b10001 //BASEADDR+0x44
`define REG_PADOUTSET_32_63 5'b10010 //BASEADDR+0x48
`define REG_PADOUTCLR_32_63 5'b10011 //BASEADDR+0x4C
`define REG_INTEN_32_63     5'b10100 //BASEADDR+0x50
`define REG_INTTYPE_32_47   5'b10101 //BASEADDR+0x54
`define REG_INTTYPE_48_63   5'b10110 //BASEADDR+0x58
`define REG_INTSTATUS_32_63 5'b10111 //BASEADDR+0x5C
`define REG_PADCFG_32_39    5'b11000 //BASEADDR+0x60
`define REG_PADCFG_40_47    5'b11001 //BASEADDR+0x64
`define REG_PADCFG_48_55    5'b11010 //BASEADDR+0x68
`define REG_PADCFG_56_63    5'b11011 //BASEADDR+0x6C

module apb_gpio #(
    parameter APB_ADDR_WIDTH = 12, //APB slaves are 4KB by default
    parameter PAD_NUM        = 32,
    parameter NBIT_PADCFG    = 4
) (
    input  logic                      HCLK,
    input  logic                      HRESETn,

    input  logic                      dft_cg_enable_i,

    input  logic [APB_ADDR_WIDTH-1:0] PADDR,
    input  logic               [31:0] PWDATA,
    input  logic                      PWRITE,
    input  logic                      PSEL,
    input  logic                      PENABLE,
    output logic               [31:0] PRDATA,
    output logic                      PREADY,
    output logic                      PSLVERR,

    input  logic   [PAD_NUM-1:0]      gpio_in,
    output logic   [PAD_NUM-1:0]      gpio_in_sync,
    output logic   [PAD_NUM-1:0]      gpio_out,
    output logic   [PAD_NUM-1:0]      gpio_dir,
    output logic   [PAD_NUM-1:0][NBIT_PADCFG-1:0] gpio_padcfg,
    output logic   [PAD_NUM-1:0]      interrupt_o
);

    logic [PAD_NUM-1:0]       r_gpio_inten;
    logic        [63:0]       s_gpio_inten;

    logic [PAD_NUM-1:0] [1:0] r_gpio_inttype;
    logic        [63:0] [1:0] s_gpio_inttype;

    logic [PAD_NUM-1:0]       r_gpio_out;
    logic        [63:0]       s_gpio_out;

    logic [PAD_NUM-1:0]       r_gpio_dir;
    logic        [63:0]       s_gpio_dir;

    logic [PAD_NUM-1:0] [NBIT_PADCFG-1:0] r_gpio_padcfg;
    logic        [63:0] [NBIT_PADCFG-1:0] s_gpio_padcfg;

    logic [PAD_NUM-1:0]       r_gpio_sync0;
    logic [PAD_NUM-1:0]       r_gpio_sync1;

    logic [PAD_NUM-1:0]       r_gpio_in;

    logic [PAD_NUM-1:0]       r_gpio_en;
    logic        [63:0]       s_gpio_en;
    logic        [63:0]       s_cg_en;

    logic [PAD_NUM-1:0] s_gpio_rise;
    logic [PAD_NUM-1:0] s_gpio_fall;
    logic [PAD_NUM-1:0] s_is_int_rise;
    logic [PAD_NUM-1:0] s_is_int_rifa;
    logic [PAD_NUM-1:0] s_is_int_fall;
    logic [PAD_NUM-1:0] s_is_int_all;

    logic  [4:0] s_apb_addr;

    logic [PAD_NUM-1:0] r_status;

    logic [15:0] s_clk_en;

    logic [63:0] s_write_cfg;
    logic [63:0] s_write_inttype;
    logic [63:0] s_write_dir;
    logic [63:0] s_write_out;
    logic [63:0] s_write_inten;
    logic [63:0] s_write_gpen;
    logic        s_write;

    genvar i;

    // Synchronization registers for interrupt signals
    logic [PAD_NUM-1:0] interrupt, interrupt_sync;

    generate
        for(i=0;i<PAD_NUM;i++)
            assign gpio_padcfg[i] = r_gpio_padcfg[i];
    endgenerate

    assign s_apb_addr = PADDR[6:2];

    assign gpio_in_sync = r_gpio_sync1;

    assign s_gpio_rise =  r_gpio_sync1 & ~r_gpio_in; //foreach input check if rising edge
    assign s_gpio_fall = ~r_gpio_sync1 &  r_gpio_in; //foreach input check if falling edge

    always_comb begin
        for(int i=0;i<PAD_NUM;i++)
        begin
            s_is_int_fall[i] =  ~r_gpio_inttype[i][1] & ~r_gpio_inttype[i][0] & s_gpio_fall[i];                    // inttype 00 fall
            s_is_int_rise[i] =  ~r_gpio_inttype[i][1] &  r_gpio_inttype[i][0] & s_gpio_rise[i];                    // inttype 01 rise
            s_is_int_rifa[i] =   r_gpio_inttype[i][1] & ~r_gpio_inttype[i][0] & (s_gpio_rise[i] | s_gpio_fall[i]); // inttype 10 rise
        end
    end

    // check if bit if interrupt is enable and if interrupt specified by inttype occurred
    assign s_is_int_all  = r_gpio_inten & ~r_gpio_dir & r_gpio_en & (s_is_int_rise | s_is_int_fall | s_is_int_rifa);

    always_ff @(posedge HCLK or negedge HRESETn)
    begin
        if (~HRESETn)
        begin
            interrupt <= '0;
            interrupt_sync <= '0;
        end
        else
        begin
            interrupt <= s_is_int_all;
            interrupt_sync <= interrupt;
        end
    end

    // Assign synchronized interrupt signals to the output
    assign interrupt_o = interrupt_sync;

    always_ff @(posedge HCLK, negedge HRESETn)
    begin
        if(~HRESETn)
        begin
            r_status  <=  'h0;
        end else begin
            for(int i=0;i<PAD_NUM;i++)
            begin
                if (s_is_int_all[i]) // if interrupt occurs, update status
                    r_status[i]  <= 1'b1;
            end
            // Clear interrupt status bits when the status register is read
            if (PSEL && PENABLE && !PWRITE )
            begin
                if (s_apb_addr == `REG_INTSTATUS_00_31) //clears int if status is read
                begin
                    for(int i=0;i<32;i++)
                    begin
                        if(i<PAD_NUM && PRDATA[i])
                            r_status[i]  <= 1'b0;
                    end
                end
                else if (s_apb_addr == `REG_INTSTATUS_32_63)
                begin
                    for(int i=32;i<64;i++)
                    begin
                        if(i<PAD_NUM && PRDATA[i - 32])
                            r_status[i]  <= 1'b0;
                    end
                end
            end
        end
    end

    always_comb begin : proc_cg_en
        for (int i=0;i<64;i++)
        begin
            if(i<PAD_NUM)
                s_cg_en[i] = r_gpio_en[i] && dft_cg_enable_i;
            else
                s_cg_en[i] = 1'b0;
        end
    end

    always_comb begin : proc_clk_en
        for (int i=0;i<16;i++)
            s_clk_en[i] = s_cg_en[i*4] | s_cg_en[i*4+1] | s_cg_en[i*4+2] | s_cg_en[i*4+3];
    end

    // GPIO Input Synchronization
    always_ff @(posedge HCLK or negedge HRESETn)
    begin
        if(~HRESETn)
        begin
            for(int j=0;j<PAD_NUM;j++)
            begin
                r_gpio_in[j]    <= 1'b0;
                r_gpio_sync1[j] <= 1'b0;
                r_gpio_sync0[j] <= 1'b0;
            end
        end
        else
        begin
            for(int j=0;j<PAD_NUM;j++)
            begin
                if(s_clk_en[j/4])
                begin
                    r_gpio_sync0[j] <= gpio_in[j];
                    r_gpio_sync1[j] <= r_gpio_sync0[j];
                    r_gpio_in[j]    <= r_gpio_sync1[j];
                end
            end
        end
    end

    // GPIO Configuration Registers Update
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if(~HRESETn) begin
            for(int i=0;i<PAD_NUM;i++)
            begin
                r_gpio_padcfg[i]  <= '0;
                r_gpio_inttype[i] <= 2'b00;
                r_gpio_dir[i]     <= 1'b0;
                r_gpio_out[i]     <= 1'b0;
                r_gpio_inten[i]   <= 1'b0;
                r_gpio_en[i]      <= 1'b0;
            end
        end else begin
            for(int i=0;i<PAD_NUM;i++)
            begin
                if(s_write)
                begin
                    if(s_write_cfg[i])
                        r_gpio_padcfg[i]  <= s_gpio_padcfg[i] ;
                    if(s_write_inttype[i])
                        r_gpio_inttype[i] <= s_gpio_inttype[i];
                    if(s_write_dir[i]) begin
                        r_gpio_dir[i] <= s_gpio_dir[i];
                        if(s_gpio_dir[i] == 1'b1) // 1 = output
                            r_gpio_inten[i] <= 1'b0; // Automatically disable interrupt for output
                    end
                    if(s_write_out[i])
                        r_gpio_out[i]     <= s_gpio_out[i]    ;
                    if(s_write_inten[i])
                        r_gpio_inten[i]   <= s_gpio_inten[i]  ;
                    if(s_write_gpen[i])
                        r_gpio_en[i]      <= s_gpio_en[i]     ;
                end
            end
        end
    end

    // APB Write Logic
    always_comb
    begin
        s_write       = 1'b0;
        s_write_dir   = 64'h0;
        s_write_out   = 64'h0;
        s_write_cfg   = 64'h0;
        s_write_inten = 64'h0;
        s_write_gpen  = 64'h0;
        s_write_inttype = 64'h0;

        for (int i=0;i<64;i++)
        begin
            if(i<PAD_NUM)
            begin
                s_gpio_padcfg[i]  = r_gpio_padcfg[i];
                s_gpio_inttype[i] = r_gpio_inttype[i];
                s_gpio_dir[i]     = r_gpio_dir[i];
                s_gpio_out[i]     = r_gpio_out[i];
                s_gpio_inten[i]   = r_gpio_inten[i];
                s_gpio_en[i]      = r_gpio_en[i];
            end
            else
            begin
                s_gpio_padcfg[i]  = '0;
                s_gpio_inttype[i] = 2'b00;
                s_gpio_dir[i]     = 1'b0;
                s_gpio_out[i]     = 1'b0;
                s_gpio_inten[i]   = 1'b0;
                s_gpio_en[i]      = 1'b0;
            end
        end
        if (PSEL && PENABLE && PWRITE)
        begin
            s_write = 1'b1;
            case (s_apb_addr)
                `REG_PADDIR_00_31:
                begin
                    s_write_dir[31:0]  = 32'hFFFFFFFF;
                    s_gpio_dir[31:0]   = PWDATA;
                end
                `REG_PADDIR_32_63:
                begin
                    s_write_dir[63:32] = 32'hFFFFFFFF;
                    s_gpio_dir[63:32]  = PWDATA;
                end
                `REG_PADOUT_00_31:
                begin
                    s_write_out[31:0]  = 32'hFFFFFFFF;
                    s_gpio_out[31:0]   = PWDATA;
                end
                `REG_PADOUT_32_63:
                begin
                    s_write_out[63:32] = 32'hFFFFFFFF;
                    s_gpio_out[63:32]  = PWDATA;
                end
                `REG_PADOUTSET_00_31:
                begin
                    s_write_out[31:0]  = 32'hFFFFFFFF;
                    for(int i=0;i<32;i++)
                        if(i<PAD_NUM)
                            s_gpio_out[i]  = r_gpio_out[i] | PWDATA[i];
                end
                `REG_PADOUTSET_32_63:
                begin
                    s_write_out[63:32] = 32'hFFFFFFFF;
                    for(int i=32;i<64;i++)
                        if(i<PAD_NUM)
                            s_gpio_out[i]  = r_gpio_out[i] | PWDATA[i-32];
                end
                `REG_PADOUTCLR_00_31:
                begin
                    s_write_out[31:0]  = 32'hFFFFFFFF;
                    for(int i=0;i<32;i++)
                        if(i<PAD_NUM)
                            s_gpio_out[i]  = r_gpio_out[i] & ~PWDATA[i];
                end
                `REG_PADOUTCLR_32_63:
                begin
                    s_write_out[63:32] = 32'hFFFFFFFF;
                    for(int i=32;i<64;i++)
                        if(i<PAD_NUM)
                            s_gpio_out[i]  = r_gpio_out[i] & ~PWDATA[i-32];
                end
                `REG_INTEN_00_31:
                begin
                    s_write_inten[31:0] = 32'hFFFFFFFF;
                    for(int i = 0; i < 32; i++) begin
                        if(i < PAD_NUM && ~r_gpio_dir[i])
                            s_gpio_inten[i] = PWDATA[i];
                        else
                            s_gpio_inten[i] = r_gpio_inten[i]; // Keep existing value
                    end
                end
                `REG_INTEN_32_63:
                begin
                    s_write_inten[63:32] = 32'hFFFFFFFF;
                    for(int i = 32; i < 64; i++) begin
                        if(i < PAD_NUM && ~r_gpio_dir[i])
                            s_gpio_inten[i] = PWDATA[i];
                        else
                            s_gpio_inten[i] = r_gpio_inten[i]; // Keep existing value
                    end
                end
                `REG_INTTYPE_00_15:
                begin
                    s_write_inttype[15:0] = 16'hFFFF;
                    for(int i=0; i<16; i++) begin
                        if(i < PAD_NUM)
                            s_gpio_inttype[i] = PWDATA[2*i +: 2];
                    end
                end
                `REG_INTTYPE_16_31:
                begin
                    s_write_inttype[31:16] = 16'hFFFF;
                    for(int i=16; i<32; i++) begin
                        if(i < PAD_NUM)
                            s_gpio_inttype[i] = PWDATA[2*(i-16) +: 2];
                    end
                end
                `REG_INTTYPE_32_47:
                begin
                    s_write_inttype[47:32] = 16'hFFFF;
                    for(int i=32; i<48; i++) begin
                        if(i < PAD_NUM)
                            s_gpio_inttype[i] = PWDATA[2*(i-32) +: 2];
                    end
                end
                `REG_INTTYPE_48_63:
                begin
                    s_write_inttype[63:48] = 16'hFFFF;
                    for(int i=48; i<64; i++) begin
                        if(i < PAD_NUM)
                            s_gpio_inttype[i] = PWDATA[2*(i-48) +: 2];
                    end
                end
                `REG_GPIOEN_00_31:
                begin
                    s_write_gpen[31:0] = 32'hFFFFFFFF;
                    for(int i=0; i<32; i++)
                        if(i < PAD_NUM)
                            s_gpio_en[i] = PWDATA[i];
                end
                `REG_GPIOEN_32_63:
                begin
                    s_write_gpen[63:32] = 32'hFFFFFFFF;
                    for(int i=32; i<64; i++)
                        if(i < PAD_NUM)
                            s_gpio_en[i] = PWDATA[i-32];
                end
                `REG_PADCFG_00_07:
                begin
                    s_write_cfg[7:0]  = 8'hFF;
                    for(int i=0; i<8; i++)
                        if(i < PAD_NUM)
                            s_gpio_padcfg[i]  = PWDATA[4*i +: 4];
                end
                `REG_PADCFG_08_15:
                begin
                    s_write_cfg[15:8] = 8'hFF;
                    for(int i=8; i<16; i++)
                        if(i < PAD_NUM)
                            s_gpio_padcfg[i]  = PWDATA[4*(i-8) +: 4];
                end
                `REG_PADCFG_16_23:
                begin
                    s_write_cfg[23:16] = 8'hFF;
                    for(int i=16; i<24; i++)
                        if(i < PAD_NUM)
                            s_gpio_padcfg[i]  = PWDATA[4*(i-16) +: 4];
                end
                `REG_PADCFG_24_31:
                begin
                    s_write_cfg[31:24] = 8'hFF;
                    for(int i=24; i<32; i++)
                        if(i < PAD_NUM)
                            s_gpio_padcfg[i]  = PWDATA[4*(i-24) +: 4];
                end
                `REG_PADCFG_32_39:
                begin
                    s_write_cfg[39:32] = 8'hFF;
                    for(int i=32; i<40; i++)
                        if(i < PAD_NUM)
                            s_gpio_padcfg[i]  = PWDATA[4*(i-32) +: 4];
                end
                `REG_PADCFG_40_47:
                begin
                    s_write_cfg[47:40] = 8'hFF;
                    for(int i=40; i<48; i++)
                        if(i < PAD_NUM)
                            s_gpio_padcfg[i]  = PWDATA[4*(i-40) +: 4];
                end
                `REG_PADCFG_48_55:
                begin
                    s_write_cfg[55:48] = 8'hFF;
                    for(int i=48; i<56; i++)
                        if(i < PAD_NUM)
                            s_gpio_padcfg[i]  = PWDATA[4*(i-48) +: 4];
                end
                `REG_PADCFG_56_63:
                begin
                    s_write_cfg[63:56] = 8'hFF;
                    for(int i=56; i<64; i++)
                        if(i < PAD_NUM)
                            s_gpio_padcfg[i]  = PWDATA[4*(i-56) +: 4];
                end
            endcase
        end
    end

    // APB Read Logic
    always_comb
    begin
        if (PSEL && PENABLE && !PWRITE)
        begin
            case (s_apb_addr)
            `REG_PADDIR_00_31:
            begin
                for(int i=0;i<32;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[i] = r_gpio_dir[i];
                    else
                        PRDATA[i] = 1'b0;
                end
            end
            `REG_PADDIR_32_63:
            begin
                for(int i=32;i<64;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[i-32] = r_gpio_dir[i];
                    else
                        PRDATA[i-32] = 1'b0;
                end
            end
            `REG_PADIN_00_31:
            begin
                for(int i=0;i<32;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[i] = r_gpio_in[i];
                    else
                        PRDATA[i] = 1'b0;
                end
            end
            `REG_PADIN_32_63:
            begin
                for(int i=32;i<64;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[i-32] = r_gpio_in[i];
                    else
                        PRDATA[i-32] = 1'b0;
                end
            end
            `REG_PADOUT_00_31:
            begin
                for(int i=0;i<32;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[i] = r_gpio_out[i];
                    else
                        PRDATA[i] = 1'b0;
                end
            end
            `REG_PADOUT_32_63:
            begin
                for(int i=32;i<64;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[i-32] = r_gpio_out[i];
                    else
                        PRDATA[i-32] = 1'b0;
                end
            end
            `REG_INTEN_00_31:
            begin
                for(int i=0;i<32;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[i] = r_gpio_inten[i];
                    else
                        PRDATA[i] = 1'b0;
                end
            end
            `REG_INTEN_32_63:
            begin
                for(int i=32;i<64;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[i-32] = r_gpio_inten[i];
                    else
                        PRDATA[i-32] = 1'b0;
                end
            end
            `REG_INTTYPE_00_15:
            begin
                for(int i=0;i<16;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[2*i +: 2] = r_gpio_inttype[i];
                    else
                        PRDATA[2*i +: 2] = 2'b00;
                end
            end
            `REG_INTTYPE_16_31:
            begin
                for(int i=16;i<32;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[2*(i-16) +: 2] = r_gpio_inttype[i];
                    else
                        PRDATA[2*(i-16) +: 2] = 2'b00;
                end
            end
            `REG_INTTYPE_32_47:
            begin
                for(int i=32;i<48;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[2*(i-32) +: 2] = r_gpio_inttype[i];
                    else
                        PRDATA[2*(i-32) +: 2] = 2'b00;
                end
            end
            `REG_INTTYPE_48_63:
            begin
                for(int i=48;i<64;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[2*(i-48) +: 2] = r_gpio_inttype[i];
                    else
                        PRDATA[2*(i-48) +: 2] = 2'b00;
                end
            end
            `REG_INTSTATUS_00_31:
            begin
                for(int i=0;i<32;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[i] = r_status[i];
                    else
                        PRDATA[i] = 1'b0;
                end
            end
            `REG_INTSTATUS_32_63:
            begin
                for(int i=32;i<64;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[i-32] = r_status[i];
                    else
                        PRDATA[i-32] = 1'b0;
                end
            end
            `REG_GPIOEN_00_31:
            begin
                for(int i=0;i<32;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[i] = r_gpio_en[i];
                    else
                        PRDATA[i] = 1'b0;
                end
            end
            `REG_GPIOEN_32_63:
            begin
                for(int i=32;i<64;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[i-32] = r_gpio_en[i];
                    else
                        PRDATA[i-32] = 1'b0;
                end
            end
            `REG_PADCFG_00_07:
            begin
                for(int i=0;i<8;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[4*i +: 4] = r_gpio_padcfg[i];
                    else
                        PRDATA[4*i +: 4] = 4'h0;
                end
            end
            `REG_PADCFG_08_15:
            begin
                for(int i=8;i<16;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[4*(i-8) +: 4] = r_gpio_padcfg[i];
                    else
                        PRDATA[4*(i-8) +: 4] = 4'h0;
                end
            end
            `REG_PADCFG_16_23:
            begin
                for(int i=16;i<24;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[4*(i-16) +: 4] = r_gpio_padcfg[i];
                    else
                        PRDATA[4*(i-16) +: 4] = 4'h0;
                end
            end
            `REG_PADCFG_24_31:
            begin
                for(int i=24;i<32;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[4*(i-24) +: 4] = r_gpio_padcfg[i];
                    else
                        PRDATA[4*(i-24) +: 4] = 4'h0;
                end
            end
            `REG_PADCFG_32_39:
            begin
                for(int i=32;i<40;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[4*(i-32) +: 4] = r_gpio_padcfg[i];
                    else
                        PRDATA[4*(i-32) +: 4] = 4'h0;
                end
            end
            `REG_PADCFG_40_47:
            begin
                for(int i=40;i<48;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[4*(i-40) +: 4] = r_gpio_padcfg[i];
                    else
                        PRDATA[4*(i-40) +: 4] = 4'h0;
                end
            end
            `REG_PADCFG_48_55:
            begin
                for(int i=48;i<56;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[4*(i-48) +: 4] = r_gpio_padcfg[i];
                    else
                        PRDATA[4*(i-48) +: 4] = 4'h0;
                end
            end
            `REG_PADCFG_56_63:
            begin
                for(int i=56;i<64;i++)
                begin
                    if(i<PAD_NUM)
                        PRDATA[4*(i-56) +: 4] = r_gpio_padcfg[i];
                    else
                        PRDATA[4*(i-56) +: 4] = 4'h0;
                end
            end
            default:
                PRDATA = 'h0;
            endcase
        end
        else
        begin
            PRDATA = 'h0;
        end
    end

    assign gpio_out = r_gpio_out;
    assign gpio_dir = r_gpio_dir;

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

endmodule
