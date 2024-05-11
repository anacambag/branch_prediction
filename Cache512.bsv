import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MemTypes::*;
import Ehr::*;

// Note that this interface *is* symmetric. 
interface Cache512;
    method Action putFromProc(MainMemReq e);
    method ActionValue#(MainMemResp) getToProc();
    method ActionValue#(MainMemReq) getToMem();
    method Action putFromMem(MainMemResp e);
endinterface



(* synthesize *)
module mkCache(Cache512);
    BRAM_Configure cfg = defaultValue;
    cfg.loadFormat = tagged Binary "zero512.vmh";  // zero out for you

    //// FIFO //////
    FIFO#(MainMemReq) curReq <- mkFIFO; // fifo with request from processor requesting to the cache
    FIFO#(MainMemResp) hitq <- mkFIFO;
    FIFO#(MainMemReq) memReq <- mkFIFO;
    FIFO#(MainMemResp) memResp <- mkFIFO;

    // Rename this to a meaningful name if you're keeping it, or adding more.
    BRAM1Port#(LineIndex2, LineState) bstate <- mkBRAM1Server(cfg); // (address/index type, data type) 
    BRAM1Port#(LineIndex2, LineTag2) btag <- mkBRAM1Server(cfg);
    BRAM1Port#(LineIndex2, Bit#(512)) bdata <- mkBRAM1Server(cfg); // CHANGED! CHECK!

    Reg#(State) state <- mkReg(Ready); // Initializing state to ready

    rule checkHitMiss if(state == Check);

        let bstate_info <- bstate.portA.response.get();
        let btag_info <- btag.portA.response.get();
        let bdata_info <- bdata.portA.response.get();

        let curReq_info = curReq.first(); // NEED DEQUEU? OR LATER?


        ParsedAddress2 eInfo = parseAddress2(curReq_info.addr); // revisar si llamandolo igual que en el method no da problema

        // HIT

        if((bstate_info != Invalid) && (eInfo.tag == btag_info)) begin

            // WRITE
            if(curReq_info.write != 0) begin

                bstate.portA.request.put(BRAMRequest{write: True, // False for read
                  responseOnWrite: False,
                   address: eInfo.index, 
                  datain: Dirty});

                bdata.portA.request.put(BRAMRequest{
                        write: True, // False for read
                        responseOnWrite: False,
                        address: eInfo.index, 
                        datain: curReq_info.data});

                state <= Ready;
                curReq.deq();
                
            end
            
            // READ
            if(curReq_info.write == 0) begin

                hitq.enq(bdata_info); 
                state <= Ready;
                curReq.deq();
            end  
        end

        // MISS 
        else begin

            if(bstate_info == Dirty) begin

                memReq.enq(MainMemReq{write: 1, 
                            addr: {btag_info,eInfo.index},
                            data: bdata_info}); //CHANGED. Sending 512 bits instead of vector to mem
                
                state <= SendMemReq;
            end

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
                            addr: {curReq_info.addr[25:8],curReq_info.addr[7:0]}, // same as before
                            data: ?});
        state <= ReadMemReq;
    endrule

    rule readMemoryRequest if(state == ReadMemReq);

        let resp = memResp.first(); //   512 bit resp needs to change to a Vector(16,word)
         // from Bit 512 to a Vector(16,Word)
 
        let curReq_info = curReq.first();
        ParsedAddress2 eInfo = parseAddress2(curReq_info.addr);

        memResp.deq();

        // WRITE //
        if(curReq_info.write != 0) begin
            // $display("im a miss write");
            bstate.portA.request.put(BRAMRequest{write: True, // False for read
                  responseOnWrite: False,
                   address: eInfo.index, 
                  datain: Dirty});
        
                
            btag.portA.request.put(BRAMRequest{write: True, // False for read
                    responseOnWrite: False,
                    address: eInfo.index, 
                    datain: eInfo.tag});
           
           // Do we use this?? curReq_info.data
            
            // $display("curReq_info.word_byte: %x; resp_vec[eInfo.offset]: %x; curReq_info.data: %x; final_data: %x", curReq_info.word_byte, resp_vec[eInfo.offset], curReq_info.data, final_data);
             // is okay to put the data like this because data from curReq is only one word :)
            // resp_vec[eInfo.offset] = curReq_info.data; // is okay to put the data like this because data from curReq is only one word :)

            bdata.portA.request.put(BRAMRequest{
                    write: True, // check if F's go like this
                    responseOnWrite: False,
                    address: eInfo.index, 
                    datain: resp}); // check if curReq_info.data goes here
        end

        // READ //
        else begin
            hitq.enq(resp);
            // $display("im a miss read");
            bstate.portA.request.put(BRAMRequest{write: True, // False for read
                  responseOnWrite: False,
                   address: eInfo.index, 
                  datain: Clean});
            
            btag.portA.request.put(BRAMRequest{write: True, // False for read
                    responseOnWrite: False,
                    address: eInfo.index, 
                    datain: eInfo.tag});
            
            bdata.portA.request.put(BRAMRequest{
                    write: True, // False for read
                    responseOnWrite: False,
                    address: eInfo.index, 
                    datain: resp});

        end

        curReq.deq();
        state <= Ready;


    endrule

    method Action putFromProc(MainMemReq e) if (state == Ready);
        ParsedAddress2 eInfo = parseAddress2(e.addr); // this wont work now

        // typedef struct { Bit#(1) write; Bit#(26) addr; Bit#(512) data; } MainMemReq deriving (Eq, FShow, Bits, Bounded);

   
        bstate.portA.request.put(BRAMRequest{write: False, // False for read
                  responseOnWrite: False,
                   address: eInfo.index, 
                  datain: ?});
        
        btag.portA.request.put(BRAMRequest{write: False, // False for read
                  responseOnWrite: False,
                   address: eInfo.index, 
                  datain: ?});
        
        bdata.portA.request.put(BRAMRequest{
                  write: False, 
                  responseOnWrite: False,
                   address: eInfo.index, 
                  datain: ?});

        curReq.enq(e); // sending info to FIFO so it activates next state
        state <= Check;
    endmethod

    method ActionValue#(MainMemResp) getToProc();
        hitq.deq();
        

        return hitq.first();
    endmethod

    method ActionValue#(MainMemReq) getToMem();
        memReq.deq();

        return memReq.first();
    endmethod

    method Action putFromMem(MainMemResp e);
        memResp.enq(e);
    endmethod
endmodule

