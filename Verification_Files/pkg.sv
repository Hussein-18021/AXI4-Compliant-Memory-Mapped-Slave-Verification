package enuming;
    typedef enum { VALID_BEFORE_READY, READY_BEFORE_VALID } handshake_t;
    
    typedef enum logic [1:0] {
        OKAY   = 2'b00,
        EXOKAY = 2'b01,
        SLVERR = 2'b10, 
        DECERR = 2'b11
    } axi_resp_t;
    
    typedef enum logic [1:0] {
        FIXED = 2'b00,
        INCR  = 2'b01,
        WRAP  = 2'b10,
        RSVD  = 2'b11
    } axi_burst_t;
    
    typedef enum logic [2:0] {
        SIZE_1B   = 3'b000,
        SIZE_2B   = 3'b001,
        SIZE_4B   = 3'b010,
        SIZE_8B   = 3'b011,
        SIZE_16B  = 3'b100,
        SIZE_32B  = 3'b101,
        SIZE_64B  = 3'b110,
        SIZE_128B = 3'b111 
    } axi_size_t;

    typedef enum {
        SINGLE_BEAT,
        SHORT_BURST,
        MEDIUM_BURST,
        LONG_BURST,
        VERY_LONG_BURST
    } burst_type_e;

    typedef enum {
        LOW_ADDR_RANGE,
        MID_ADDR_RANGE, 
        HIGH_ADDR_RANGE,
        BOUNDARY_ADDR_RANGE
    } addr_range_e;

    typedef enum {
        RANDOM_DATA,
        ALL_ZEROS,
        ALL_ONES,
        ALTERNATING_AA,
        ALTERNATING_55
    } data_pattern_e;

    typedef enum {
        RANDOM_MODE,
        BOUNDARY_CROSSING_MODE,
        BURST_LENGTH_MODE,
        DATA_PATTERN_MODE
    } test_mode_e;
    
    typedef enum {
        READ_OP, 
        WRITE_OP
    } operation_type_e;
    
endpackage