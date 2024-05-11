// SINGLE CORE ASSOIATED CACHE -- stores words

import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;
import Vector :: * ;

// The types live in MemTypes.bsv

// Notice the asymmetry in this interface, as mentioned in lecture.
// The processor thinks in 32 bits, but the other side thinks in 512 bits.
interface Cache32;
    method Action putFromProc(CacheReq e); //  delivers a cache request from your processor to your cache.
    method ActionValue#(Word) getToProc(); // should return the associated data that is for that memory address that was requested.
    method ActionValue#(MainMemReq) getToMem(); // will deliver any requests from your cache to the next stage of memory.
    method Action putFromMem(MainMemResp e); // will respond with the data you requested from the next stage.
endinterface

//preguntar
// typedef struct {Bit#(n) writeen;
//     Bool responseOnWrite;
//     addr address;
//     data datain;
// } BRAMRequestBE#(type addr, type data, numeric type n) deriving (Bits, Eq);

// COMENTE ESTO CHEQUEAR 

// typedef struct {Bit#(512) writeen;
//     Bool responseOnWrite;
//     LineIndex address;
//     Vector#(16,Word) datain;
// } BRAMRequestBE#(type addr, type data, numeric type n) deriving (Bits, Eq);



(* synthesize *)
module mkCache32(Cache32);
    BRAM_Configure cfg = defaultValue;
    cfg.loadFormat = tagged Binary "zero.vmh";  // zero out for you. Thanks :)

    //// FIFO //////
    FIFO#(CacheReq) curReq <- mkFIFO; // fifo with request from processor requesting to the cache
    FIFO#(Word) hitq <- mkFIFO;
    FIFO#(MainMemReq) memReq <- mkFIFO;
    FIFO#(MainMemResp) memResp <- mkFIFO;


    BRAM1Port#(LineIndex, LineState) bstate <- mkBRAM1Server(cfg); // (address/index type, data type) 
    BRAM1Port#(LineIndex, LineTag) btag <- mkBRAM1Server(cfg);
    BRAM1PortBE#(LineIndex, Vector#(16, Word), 64) bdata <- mkBRAM1ServerBE(cfg); // CHANGED! CHECK!


    Reg#(State) state <- mkReg(Ready); // Initializing state to ready


    rule checkHitMiss if(state == Check);

        let bstate_info <- bstate.portA.response.get();
        let btag_info <- btag.portA.response.get();
        let bdata_info <- bdata.portA.response.get();

        let curReq_info = curReq.first(); // NEED DEQUEU? OR LATER?

        Vector#(16, Word) transformData = unpack(0);

        ParsedAddress eInfo = parseAddress(curReq_info.addr); // revisar si llamandolo igual que en el method no da problema
        transformData[eInfo.offset] = curReq_info.data;

        // HIT

        if((bstate_info != Invalid) && (eInfo.tag == btag_info)) begin

            // WRITE
            if(curReq_info.word_byte != 0) begin
                // $display("im a hit write");
                bstate.portA.request.put(BRAMRequest{write: True, // False for read
                  responseOnWrite: False,
                   address: eInfo.index, 
                  datain: Dirty});
        
                Bit#(8) offset_var = 4*zeroExtend(eInfo.offset);
                // $display("word_byte: %x; eInfo.offset: %x ", (curReq_info.word_byte), eInfo.offset);
                Bit#(64)  temp_index = zeroExtend(curReq_info.word_byte) << (offset_var);
                // $display("written value %x", temp_index);
                // $display("HIT WRITE:curReq_info.word_byte: %x; transformData: %x; curReq_info.data: %x;  address: %x", curReq_info.word_byte, transformData, curReq_info.data, eInfo.index);

                bdata.portA.request.put(BRAMRequestBE{
                        writeen: zeroExtend(curReq_info.word_byte) << (offset_var), // False for read
                        responseOnWrite: False,
                        address: eInfo.index, 
                        datain: transformData});

                state <= Ready;
                curReq.deq();
                
            end
            
            // READ
            if(curReq_info.word_byte == 0) begin
                // $display("im a hit read, address: %x", eInfo.index);
                hitq.enq(bdata_info[eInfo.offset]); // check this if true
                state <= Ready;
                curReq.deq();
            end  
        end

        // MISS 
        else begin

            Bit#(512) toMemData = pack(bdata_info); // Converting vector line from cache to 512 for mem

            if(bstate_info == Dirty) begin
                // $display("im dirty");
                memReq.enq(MainMemReq{write: 1, 
                            addr: {btag_info,eInfo.index},
                            data: toMemData}); //CHANGED. Sending 512 bits instead of vector to mem
                
                state <= SendMemReq;
            end
            // NO ES DIRTY
            else begin
                // $display("im not dirty");
                memReq.enq(MainMemReq{write: 0, 
                            addr: {eInfo.tag,eInfo.index}, // NO FALTARIA UNA PARTE DE LA DERECHA?
                            data: ?});
                
                state <= ReadMemReq;   
            end 
        
        end
    endrule

    rule sendMemoryRequest if(state == SendMemReq);
        let curReq_info = curReq.first();
        memReq.enq(MainMemReq{write: 0, 
                            addr: {curReq_info.addr[31:13],curReq_info.addr[12:6]}, // same as before
                            data: ?});
        state <= ReadMemReq;
    endrule

    rule readMemoryRequest if(state == ReadMemReq);

        let resp = memResp.first(); //chequear este fifo//  512 bit resp needs to change to a Vector(16,word)
        Vector#(16, Word) resp_vec = unpack(resp); // from Bit 512 to a Vector(16,Word)
 
        let curReq_info = curReq.first();
        ParsedAddress eInfo = parseAddress(curReq_info.addr);

        memResp.deq();


        // WRITE //
        if(curReq_info.word_byte != 0) begin
            // $display("im a miss write");
            bstate.portA.request.put(BRAMRequest{write: True, // False for read
                  responseOnWrite: False,
                   address: eInfo.index, 
                  datain: Dirty});
        
                
            btag.portA.request.put(BRAMRequest{write: True, // False for read
                    responseOnWrite: False,
                    address: eInfo.index, 
                    datain: eInfo.tag});
            Vector#(4, Bit#(8)) temp_data; 
            for (Integer idx=0; idx < 4; idx=idx+1) begin
                if(curReq_info.word_byte[idx] == 1) begin
                    temp_data[idx] = curReq_info.data[(idx+1)*8-1:idx*8];
                end
                else begin
                    temp_data[idx] = resp_vec[eInfo.offset][(idx+1)*8-1:idx*8];
                end
            end

            Bit#(32) final_data = (zeroExtend(temp_data[3]) << 24) + (zeroExtend(temp_data[2]) << 16) + (zeroExtend(temp_data[1])<< 8) + zeroExtend(temp_data[0]);
            // $display("curReq_info.word_byte: %x; resp_vec[eInfo.offset]: %x; curReq_info.data: %x; final_data: %x", curReq_info.word_byte, resp_vec[eInfo.offset], curReq_info.data, final_data);
            resp_vec[eInfo.offset] = final_data; // is okay to put the data like this because data from curReq is only one word :)
            // resp_vec[eInfo.offset] = curReq_info.data; // is okay to put the data like this because data from curReq is only one word :)

            bdata.portA.request.put(BRAMRequestBE{
                    writeen: 'hFFFFFFFFFFFFFFFF, // check if F's go like this
                    responseOnWrite: False,
                    address: eInfo.index, 
                    datain: resp_vec}); 
        end

        // READ //
        else begin
            hitq.enq(resp_vec[eInfo.offset]);
            // $display("im a miss read");
            bstate.portA.request.put(BRAMRequest{write: True, // False for read
                  responseOnWrite: False,
                   address: eInfo.index, 
                  datain: Clean});
            
            btag.portA.request.put(BRAMRequest{write: True, // False for read
                    responseOnWrite: False,
                    address: eInfo.index, 
                    datain: eInfo.tag});
            
            bdata.portA.request.put(BRAMRequestBE{
                    writeen: 'hFFFFFFFFFFFFFFFF, // False for read
                    responseOnWrite: False,
                    address: eInfo.index, 
                    datain: resp_vec});

        end

        curReq.deq();
        state <= Ready;


    endrule

    method Action putFromProc(CacheReq e) if (state == Ready); //  delivers a cache request from your processor to your cache.
        // CACHE REQUEST STRUCTURE:
        // typedef struct { Bit#(4) word_byte; Bit#(32) addr; Bit#(32) data; } CacheReq deriving (Eq, FShow, Bits, Bounded);

        ParsedAddress eInfo = parseAddress(e.addr);

        // Requesting read to see what is in the cache with the given cacheRequest

        bstate.portA.request.put(BRAMRequest{write: False, // False for read
                  responseOnWrite: False,
                   address: eInfo.index, 
                  datain: ?});
        
        btag.portA.request.put(BRAMRequest{write: False, // False for read
                  responseOnWrite: False,
                   address: eInfo.index, 
                  datain: ?});
        
        bdata.portA.request.put(BRAMRequestBE{
                  writeen: 0, // Zero since we are reading
                  responseOnWrite: False,
                   address: eInfo.index, 
                  datain: ?});

        curReq.enq(e); // sending info to FIFO so it activates next state
        state <= Check;

    endmethod
 
    method ActionValue#(Word) getToProc(); // should return the associated data that is for that memory address that was requested.
        
        hitq.deq();
        

        return hitq.first();
    endmethod
        
    method ActionValue#(MainMemReq) getToMem(); // will deliver any requests from your cache to the next stage of memory.
        memReq.deq();

        return memReq.first();
    endmethod
        
    method Action putFromMem(MainMemResp e); // getting a line from memory. // will respond with the data you requested from the next stage.
        memResp.enq(e);
    endmethod
endmodule
