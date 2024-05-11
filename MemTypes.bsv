// Types used in L1 interface
typedef struct { Bit#(1) write; Bit#(26) addr; Bit#(512) data; } MainMemReq deriving (Eq, FShow, Bits, Bounded);
typedef struct { Bit#(4) word_byte; Bit#(32) addr; Bit#(32) data; } CacheReq deriving (Eq, FShow, Bits, Bounded);
typedef Bit#(512) MainMemResp;
typedef Bit#(32) Word;
typedef Bit#(32) CacheLineAddr;
typedef Bit#(26) LineAddr;

// (Curiosity Question: CacheReq address doesn't actually need to be 32 bits. Why?)

// Helper types for implementation (L1 cache):
typedef enum {
    Dirty,
    Invalid,
    Clean
    
} LineState deriving (Eq, Bits, FShow);

typedef enum {
    I,
    D
} OwnerState deriving (Eq, Bits, FShow);

typedef enum {
    Ready,
    Check,
    ReadMemReq,
    SendMemReq
} State deriving (Bits, Eq, FShow);

// You should also define a type for LineTag, LineIndex. Calculate the appropriate number of bits for your design.
typedef Bit#(19) LineTag; // since it is 32 bits - (index bits + offset bits) == 32 - (7+4)?
typedef Bit#(7) LineIndex; // since it only goes until index 128 which is 0b1111111
typedef Bit#(4) WordOffset;

// You may also want to define a type for WordOffset, since multiple Words can live in a line.


// You can translate between Vector#(16, Word) and Bit#(512) using the pack/unpack builtin functions.
// typedef Vector#(16, Word) LineData  (optional)

// Optional: You may find it helpful to make a function to parse an address into its parts.
// e.g.,
typedef struct {
        LineTag tag;
        LineIndex index;
        WordOffset offset;
} ParsedAddress deriving (Bits, Eq);

typedef struct {
        LineTag2 tag;
        LineIndex2 index;
} ParsedAddress2 deriving (Bits, Eq);
    
// typedef Bit#(1) ParsedAddress;  // placeholder

function ParsedAddress parseAddress(Bit#(32) address);
    ParsedAddress parsedAddr;

    parsedAddr.tag = address[31:13];
    parsedAddr.offset = address[5:2];
    parsedAddr.index = address[12:6];

    return parsedAddr;
endfunction



// and define whatever other types you may find helpful.


// Helper types for implementation (L2 cache):


// To convert from Bit to any other type, use unpack:

// Bit#(3) x = 3'b101;     // x is the binary value 101
// UInt#(3) y = unpack(x); // y = 5, the UInt represented by the bits 101
// Int#(3) z = unpack(x);  // z = -3, the Int represented by the bits 101
// To convert from any type to Bit, use pack:

// typedef enum Color { Red, Green, Blue, Yellow } deriving (Bits, Eq);

// Color red = Red;
// Color yellow = Yellow;

// Bit#(2) x = pack(red);    // x = 2'b00, the binary representation of Red
// Bit#(2) y = pack(yellow); // y = 2'b11, the binary representation of Yellow

// Vector(16, Word) toCacheData = unpack(); // from Bit 512 to a Vector(16,Word)
// Bit#(512) toMemData = pack(bdata_info); // from Vector(16,Word) to Bit 512


    // READ FROM A BRAM

    // bram.portA.request.put(BRAMRequest{write: False, // False for read
    //                 responseOnWrite: False,
    //                 address: zero_row_count, 
    //                 datain: ?});

    // WRITE TO A BRAM

    // bram.portA.request.put(BRAMRequest{write: True, // False for read
    //                 responseOnWrite: False,
    //                 address: zero_row_count, 
    //                 datain: something_here to write});

    // GET REQUEST

    // let response <- bram.portA.response.get();




            // resp_vec[0]  = resp[31:0];
            // resp_vec[1]  = resp[63:32];
            // resp_vec[2]  = resp[95:64];
            // resp_vec[3]  = resp[127:96];
            // resp_vec[4]  = resp[159:128];
            // resp_vec[5]  = resp[191:160];
            // resp_vec[6]  = resp[223:192];
            // resp_vec[7]  = resp[255:224];
            // resp_vec[8]  = resp[287:256];
            // resp_vec[9]  = resp[319:288];
            // resp_vec[10] = resp[351:320];
            // resp_vec[11] = resp[383:352];
            // resp_vec[12] = resp[415:384];
            // resp_vec[13] = resp[447:416];
            // resp_vec[14] = resp[479:448];
            // resp_vec[15] = resp[511:480];


// L2 CACHE 


typedef Bit#(18) LineTag2; // since it is 32 bits - (index bits + offset bits) == 32 - (7+4)?
typedef Bit#(8) LineIndex2; // since it only goes until index 128 which is 0b1111111

function ParsedAddress2 parseAddress2(Bit#(26) address);
    ParsedAddress2 parsedAddr;

    parsedAddr.tag = address[25:8];
    parsedAddr.index = address[7:0];

    return parsedAddr;
endfunction