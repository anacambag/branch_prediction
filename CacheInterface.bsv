// SINGLE CORE CACHE INTERFACE WITH NO PPP
import MainMem::*;
import MemTypes::*;
import Cache32::*;
import Cache512::*;
// import FIFOF::*;
import FIFO::*;
import FIFOF::*;


interface CacheInterface;
    method Action sendReqData(CacheReq req);
    method ActionValue#(Word) getRespData();
    method Action sendReqInstr(CacheReq req);
    method ActionValue#(Word) getRespInstr();
endinterface

(* synthesize *)
module mkCacheInterface(CacheInterface);
    let verbose = True;
    MainMem mainMem <- mkMainMem(); 
    Cache512 cacheL2 <- mkCache;
    Cache32 cacheI <- mkCache32;
    Cache32 cacheD <- mkCache32;

    FIFO#(Word) respD <- mkFIFO; // what types are this fifos
    FIFO#(Word) respI <- mkFIFO; // what types are this fifos?
    FIFO#(OwnerState) owner <- mkSizedFIFO(1); // fifo that keeps track of the owner state


    // You need to add rules and/or state elements.

    // Connect cache to interface 
    rule responseD;

        let resp <- cacheD.getToProc();
        respD.enq(resp);

    endrule

    rule responseI;
        let resp <- cacheI.getToProc();
        respI.enq(resp);

    endrule
    ////////


    // Connect L1 to L2

    rule i_to_l2;
        let req <- cacheI.getToMem();
        cacheL2.putFromProc(req);
        owner.enq(I);

    endrule

    rule d_to_l2;
        let req <- cacheD.getToMem();
        cacheL2.putFromProc(req);

        if(req.write == 0) begin
            owner.enq(D);
        end

    endrule


    rule l2_to_l1;

        let resp <- cacheL2.getToProc();
        if (owner.first() == I) begin
            cacheI.putFromMem(resp);

        
        end

        else begin
            cacheD.putFromMem(resp);
        end

        owner.deq();


    endrule

    /////////////


    // L2 TO MainMem ///

    rule respMem;
        let req <- mainMem.get();

        cacheL2.putFromMem(req);

    endrule

    rule sendMem;

        let req <- cacheL2.getToMem();
        mainMem.put(req);

    endrule

    ////



    method Action sendReqData(CacheReq req);
        cacheD.putFromProc(req);

        if(req.word_byte != 0) begin
            respD.enq(0);
        end
    endmethod

    method ActionValue#(Word) getRespData() ;

        respD.deq();
        return respD.first();
    endmethod


    method Action sendReqInstr(CacheReq req);
        cacheI.putFromProc(req);

    endmethod

    method ActionValue#(Word) getRespInstr();
        respI.deq();

        return respI.first();
    endmethod
endmodule
