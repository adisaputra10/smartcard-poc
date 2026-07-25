// ============================================
// ISO 7816 Smart Card Interface Controller
// with EEPROM Storage and RAM Buffer
// ============================================

module smartcard_interface (
  input  wire        clk,          // 50 MHz clock
  input  wire        reset,        // Active high reset
  input  wire        card_present, // Card detection signal
  input  wire        rx_data,      // Serial data from card
  input  wire [7:0]  tx_byte,      // Data to send to card
  input  wire        tx_start,     // Start transmission
  input  wire [7:0]  mem_addr,     // Memory address
  input  wire [7:0]  mem_wdata,    // Memory write data
  input  wire        mem_write,    // Memory write enable
  input  wire        mem_read,     // Memory read enable
  output reg  [7:0]  rx_byte,      // Received data
  output reg         rx_valid,     // Data received
  output reg         tx_ready,     // Ready to send
  output reg         tx_out,       // Serial data to card
  output reg  [15:0] crc_out,      // CRC-16 output
  output reg         error_flag,   // Protocol error
  output reg  [7:0]  mem_rdata,    // Memory read data
  output reg         mem_ready     // Memory operation complete
);

  // Memory size parameters
  localparam EEPROM_SIZE = 256;  // 256 bytes EEPROM
  localparam RAM_SIZE = 64;      // 64 bytes RAM buffer
  
  // UART parameters (9600 baud at 50 MHz)
  localparam BAUD_COUNT = 5208;  // 50MHz / 9600
  
  // State machine states
  localparam IDLE       = 4'd0;
  localparam TX_START_BIT = 4'd1;
  localparam TX_DATA     = 4'd2;
  localparam TX_STOP     = 4'd3;
  localparam RX_START    = 4'd4;
  localparam RX_DATA     = 4'd5;
  localparam RX_STOP     = 4'd6;
  localparam CRC_CALC    = 4'd7;
  localparam MEM_READ_ST = 4'd8;
  localparam MEM_WRITE_ST = 4'd9;

  // Internal registers
  reg [3:0]  state;
  reg [12:0] baud_counter;
  reg [3:0]  bit_index;
  reg [7:0]  tx_shift;
  reg [7:0]  rx_shift;
  reg [15:0] crc_reg;
  reg        rx_sync1, rx_sync2;

  // ============================================
  // EEPROM Memory Array (256 bytes)
  // Stores persistent card data (PIN, balance, etc.)
  // ============================================
  reg [7:0] eeprom_mem [0:EEPROM_SIZE-1];
  
  // ============================================
  // RAM Buffer (64 bytes)
  // Temporary storage for data processing
  // ============================================
  reg [7:0] ram_buffer [0:RAM_SIZE-1];
  
  // ============================================
  // Memory Controller
  // Handles read/write operations to EEPROM and RAM
  // ============================================
  reg [7:0] mem_addr_reg;
  reg [7:0] mem_wdata_reg;
  reg       mem_write_reg;
  reg       mem_read_reg;
  reg [1:0] mem_select;  // 00=EEPROM, 01=RAM, 10=Reserved, 11=Reserved
  
  // Address decoder - determine which memory to access
  always @(*) begin
    if (mem_addr < 8'hC0)  // 0x00 - 0xBF: EEPROM (192 bytes)
      mem_select = 2'b00;
    else if (mem_addr < 8'h100)  // 0xC0 - 0xFF: RAM (64 bytes)
      mem_select = 2'b01;
    else
      mem_select = 2'b10;  // Reserved
  end
  
  // ============================================
  // Register File (8 x 8-bit registers)
  // Fast access temporary storage
  // ============================================
  reg [7:0] reg_file [0:7];
  
  // Register access control
  reg [2:0] reg_addr;
  reg [7:0] reg_wdata;
  reg       reg_write;

  // ============================================
  // Data Bus Multiplexer
  // Selects data source for memory operations
  // ============================================
  reg [7:0] data_bus;
  reg [7:0] eeprom_rdata;
  reg [7:0] ram_rdata;
  
  always @(*) begin
    case (mem_select)
      2'b00: data_bus = eeprom_rdata;
      2'b01: data_bus = ram_rdata;
      default: data_bus = 8'hFF;
    endcase
  end

  // EEPROM read logic
  always @(*) begin
    if (mem_addr < 8'hC0)
      eeprom_rdata = eeprom_mem[mem_addr];
    else
      eeprom_rdata = 8'hFF;
  end
  
  // RAM read logic
  always @(*) begin
    if (mem_addr >= 8'hC0 && mem_addr < 8'h100)
      ram_rdata = ram_buffer[mem_addr - 8'hC0];
    else
      ram_rdata = 8'hFF;
  end

  // Synchronize RX input
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      rx_sync1 <= 1'b1;
      rx_sync2 <= 1'b1;
    end else begin
      rx_sync1 <= rx_data;
      rx_sync2 <= rx_sync1;
    end
  end

  // Memory write operations
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      mem_ready <= 1'b0;
      mem_rdata <= 8'h00;
    end else begin
      mem_ready <= 1'b0;
      
      // EEPROM write
      if (mem_write && mem_addr < 8'hC0) begin
        eeprom_mem[mem_addr] <= mem_wdata;
        mem_ready <= 1'b1;
      end
      // RAM write
      else if (mem_write && mem_addr >= 8'hC0 && mem_addr < 8'h100) begin
        ram_buffer[mem_addr - 8'hC0] <= mem_wdata;
        mem_ready <= 1'b1;
      end
      // Memory read
      else if (mem_read) begin
        mem_rdata <= data_bus;
        mem_ready <= 1'b1;
      end
    end
  end
  
  // Register file write operations
  integer i;
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      for (i = 0; i < 8; i = i + 1)
        reg_file[i] <= 8'h00;
    end else if (reg_write) begin
      reg_file[reg_addr] <= reg_wdata;
    end
  end

  // Main state machine
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state         <= IDLE;
      baud_counter  <= 0;
      bit_index     <= 0;
      tx_out        <= 1'b1;
      tx_ready      <= 1'b1;
      rx_valid      <= 1'b0;
      error_flag    <= 1'b0;
      crc_reg       <= 16'hFFFF;
    end else if (!card_present) begin
      state <= IDLE;
      tx_out <= 1'b1;
    end else begin
      case (state)
        IDLE: begin
          tx_ready <= 1'b1;
          rx_valid <= 1'b0;
          
          // Check for transmission request
          if (tx_start && tx_ready) begin
            tx_shift     <= tx_byte;
            tx_ready     <= 1'b0;
            baud_counter <= 0;
            state        <= TX_START_BIT;
          end
          // Check for start bit on RX
          else if (!rx_sync2) begin
            baud_counter <= 0;
            bit_index    <= 0;
            state        <= RX_START;
          end
        end

        TX_START_BIT: begin
          tx_out <= 1'b0;  // Start bit
          if (baud_counter == BAUD_COUNT - 1) begin
            baud_counter <= 0;
            bit_index    <= 0;
            state        <= TX_DATA;
          end else begin
            baud_counter <= baud_counter + 1;
          end
        end

        TX_DATA: begin
          tx_out <= tx_shift[0];  // LSB first
          if (baud_counter == BAUD_COUNT - 1) begin
            baud_counter <= 0;
            tx_shift     <= {1'b0, tx_shift[7:1]};
            if (bit_index == 7) begin
              state <= TX_STOP;
            end else begin
              bit_index <= bit_index + 1;
            end
          end else begin
            baud_counter <= baud_counter + 1;
          end
        end

        TX_STOP: begin
          tx_out <= 1'b1;  // Stop bit
          if (baud_counter == BAUD_COUNT - 1) begin
            baud_counter <= 0;
            state        <= CRC_CALC;
          end else begin
            baud_counter <= baud_counter + 1;
          end
        end

        RX_START: begin
          // Sample at middle of start bit
          if (baud_counter == (BAUD_COUNT / 2) - 1) begin
            if (!rx_sync2) begin  // Valid start bit
              baud_counter <= 0;
              bit_index    <= 0;
              state        <= RX_DATA;
            end else begin  // False start
              state <= IDLE;
            end
          end else begin
            baud_counter <= baud_counter + 1;
          end
        end

        RX_DATA: begin
          // Sample at middle of each data bit
          if (baud_counter == (BAUD_COUNT / 2) - 1) begin
            rx_shift <= {rx_sync2, rx_shift[7:1]};
            baud_counter <= 0;
            if (bit_index == 7) begin
              state <= RX_STOP;
            end else begin
              bit_index <= bit_index + 1;
            end
          end else begin
            baud_counter <= baud_counter + 1;
          end
        end

        RX_STOP: begin
          if (baud_counter == BAUD_COUNT - 1) begin
            if (rx_sync2) begin  // Valid stop bit
              rx_byte  <= rx_shift;
              rx_valid <= 1'b1;
            end else begin
              error_flag <= 1'b1;  // Framing error
            end
            state <= IDLE;
          end else begin
            baud_counter <= baud_counter + 1;
          end
        end

        CRC_CALC: begin
          // CRC-16/IBM calculation
          crc_reg <= {crc_reg[14:0], 1'b0} ^ 
                     ((tx_byte[bit_index] ^ crc_reg[15]) ? 16'hA001 : 16'h0000);
          
          if (bit_index == 7) begin
            crc_out <= crc_reg;
            state   <= IDLE;
          end else begin
            bit_index <= bit_index + 1;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule


// ============================================
// TinyTapeout Wrapper Module
// Wraps smartcard_interface with TT-compatible interface
// ============================================
module tt_um_fpga_can_lehmann (
    input  wire [7:0] ui_in,      // Dedicated inputs
    output wire [7:0] uo_out,     // Dedicated outputs
    input  wire [7:0] uio_in,     // IOs: Input path
    output wire [7:0] uio_out,    // IOs: Output path
    output wire [7:0] uio_oe,     // IOs: Enable path
    input  wire       ena,        // Enable
    input  wire       clk,        // Clock
    input  wire       rst_n       // Active low reset
);

    // Map TT inputs to smartcard_interface
    wire card_present = ui_in[0];
    wire rx_data      = ui_in[1];
    
    // Smartcard interface outputs
    wire [7:0]  rx_byte;
    wire        rx_valid;
    wire        tx_ready;
    wire        tx_out;
    wire [15:0] crc_out;
    wire        error_flag;
    wire [7:0]  mem_rdata;
    wire        mem_ready;
    
    // Instantiate smartcard_interface
    smartcard_interface u_smartcard (
        .clk         (clk),
        .reset       (~rst_n),        // Active high reset
        .card_present(card_present),
        .rx_data     (rx_data),
        .tx_byte     (8'h00),         // Tie off for now
        .tx_start    (1'b0),
        .mem_addr    (8'h00),
        .mem_wdata   (8'h00),
        .mem_write   (1'b0),
        .mem_read    (1'b0),
        .rx_byte     (rx_byte),
        .rx_valid    (rx_valid),
        .tx_ready    (tx_ready),
        .tx_out      (tx_out),
        .crc_out     (crc_out),
        .error_flag  (error_flag),
        .mem_rdata   (mem_rdata),
        .mem_ready   (mem_ready)
    );
    
    // Map outputs to TT interface
    assign uo_out[0] = rx_valid;
    assign uo_out[1] = tx_ready;
    assign uo_out[2] = tx_out;
    assign uo_out[3] = error_flag;
    assign uo_out[4] = mem_ready;
    assign uo_out[5] = crc_out[0];
    assign uo_out[6] = crc_out[8];
    assign uo_out[7] = 1'b0;
    
    assign uio_out = rx_byte;
    assign uio_oe  = 8'hFF;  // All outputs

endmodule
