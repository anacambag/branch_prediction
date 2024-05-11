import FIFO::*;
import SpecialFIFOs::*;
import RegFile::*;
import RVUtil::*;
import Vector::*;
import KonataHelper::*;
import Printf::*;
import Ehr::*;

typedef struct { Bit#(4) byte_en; Bit#(32) addr; Bit#(32) data; } Mem deriving (Eq, FShow, Bits);

interface RVIfc;
    method ActionValue#(Mem) getIReq();
    method Action getIResp(Mem a);
    method ActionValue#(Mem) getDReq();
    method Action getDResp(Mem a);
    method ActionValue#(Mem) getMMIOReq();
    method Action getMMIOResp(Mem a);
endinterface
typedef struct { Bool isUnsigned; Bit#(2) size; Bit#(2) offset; Bool mmio; } MemBusiness deriving (Eq, FShow, Bits);
typedef enum {
	Fetch, Decode, Execute, Writeback
} StateProc deriving (Eq, FShow, Bits); // ADDED THIS

function Bool isMMIO(Bit#(32) addr);
    Bool x = case (addr) 
        32'hf000fff0: True;
        32'hf000fff4: True;
        32'hf000fff8: True;
        default: False;
    endcase;
    return x;
endfunction

typedef struct { Bit#(32) pc;
                 Bit#(32) ppc;
                 Bit#(1) epoch; 
                 KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
             } F2D deriving (Eq, FShow, Bits); 

typedef struct { 
    DecodedInst dinst;
    Bit#(32) pc;
    Bit#(32) ppc;
    Bit#(1) epoch;
    Bit#(32) rv1; 
    Bit#(32) rv2; 
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
    } D2E deriving (Eq, FShow, Bits); // 

typedef struct { 
    MemBusiness mem_business;
    Bit#(32) data;
    DecodedInst dinst;
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
} E2W deriving (Eq, FShow, Bits); // 

(* synthesize *)
module mkpipelined(RVIfc);
    // Interface with memory and devices
    FIFO#(Mem) toImem <- mkBypassFIFO;
    FIFO#(Mem) fromImem <- mkBypassFIFO;
    FIFO#(Mem) toDmem <- mkBypassFIFO;
    FIFO#(Mem) fromDmem <- mkBypassFIFO;
    FIFO#(Mem) toMMIO <- mkBypassFIFO;
    FIFO#(Mem) fromMMIO <- mkBypassFIFO;

	// Code to support Konata visualization
    String dumpFile = "output.log" ;
    let lfh <- mkReg(InvalidFile);

	Reg#(KonataId) fresh_id <- mkReg(0);
	Reg#(KonataId) commit_id <- mkReg(0);

	FIFO#(KonataId) retired <- mkFIFO;
	FIFO#(KonataId) squashed <- mkFIFO;

    Ehr#(3, Bit#(32)) pc <- mkEhr(0);
    Vector#(32,Ehr#(2, Bit#(32))) bypass_val <- replicateM(mkEhr(0));

    // EhrReg#(Bit#(32)) pc <- mkReg(0);
    Ehr#(2, Bit#(1)) epoch <- mkEhr(0); // when is different in execute it will delete // 2 port EHR

   Vector#(32,Ehr#(2, Bit#(32))) rf <- replicateM(mkEhr(0)); // check this // 3 port EHR

    Vector#(32,Ehr#(3, Bit#(32))) scoreboard <- replicateM(mkEhr(0)); // would this be the correct implementation?


    FIFO#(F2D) f2d <- mkFIFO; 
    FIFO#(D2E) d2e <- mkFIFO;
    FIFO#(E2W) e2w <- mkFIFO;

    Reg#(Bool) fetch_flag <- mkReg(True);
    Reg#(Bool) decode_flag <- mkReg(False);
    Reg#(Bool) execute_flag <- mkReg(False);
    Reg#(Bool) writeback_flag <- mkReg(False);


    Reg#(StateProc) state <- mkReg(Fetch);
    Reg#(Bool) starting <- mkReg(True);

	rule do_tic_logging;
        if (starting) begin
            let f <- $fopen(dumpFile, "w") ;
            lfh <= f;
            $fwrite(f, "Kanata\t0004\nC=\t1\n");
            starting <= False;
        end
		konataTic(lfh);
	endrule
		
    rule fetch if (!starting); 

        Bit#(32) pc_fetched = pc[1]; 

        // You should put the pc that you fetch in pc_fetched

       pc[1] <= pc[1] +4; // CHECK THIS 

		let iid <- fetch1Konata(lfh, fresh_id, 0);
        labelKonataLeft(lfh, iid, $format("0x%x: ", pc_fetched));
        
        // TODO implement fetch
        let req = Mem {byte_en : 0,
			   addr : pc_fetched,
			   data : 0}; // requesting in BRAM the instruction at given address

        f2d.enq(F2D{pc: pc_fetched, ppc: pc_fetched+4, epoch: epoch[1], k_id: iid });

        
        toImem.enq(req);

    endrule

    rule decode if (!starting);
        let resp = fromImem.first();
		
        let instr = resp.data;
        let decodedInst = decodeInst(instr);
		
        let from_fetch = f2d.first();

   	    decodeKonata(lfh, from_fetch.k_id);
        labelKonataLeft(lfh,from_fetch.k_id, $format("DASM(%x)", instr));

        let rs1_idx = getInstFields(instr).rs1; 
        let rs2_idx = getInstFields(instr).rs2;
        let rd_idx = getInstFields(instr).rd; 

		let rs1 = (rs1_idx ==0 ? 0 : rf[rs1_idx][1]); 
		let rs2 = (rs2_idx == 0 ? 0 : rf[rs2_idx][1]);

        if(scoreboard[rs1_idx][2] == 0 && scoreboard[rs2_idx][2] == 0) begin 
            // check valid check non zero
            if (decodedInst.valid_rd && rd_idx !=0)begin
                scoreboard[rd_idx][2] <= 1; 
            end
            
            d2e.enq(D2E{dinst: decodedInst, pc: from_fetch.pc, ppc: from_fetch.ppc, epoch: from_fetch.epoch, rv1: rs1, rv2: rs2, k_id: from_fetch.k_id });
       
            f2d.deq(); 
            fromImem.deq();
        end

        else begin
            // STALL 
        
        end
        

    endrule

    rule execute if (!starting);
        let from_decode = d2e.first();
        d2e.deq(); 


        if (from_decode.epoch == epoch[0]) begin  // checking epoch value
            executeKonata(lfh, from_decode.k_id);
            let imm = getImmediate(from_decode.dinst);
            
            Bool mmio = False;

            let data = execALU32(from_decode.dinst.inst, from_decode.rv1, from_decode.rv2, imm, from_decode.pc); // would it be like this? Especially this: from_decode.dinst.inst
            let isUnsigned = 0;
   
            let funct3 = getInstFields(from_decode.dinst.inst).funct3;
            let size = funct3[1:0];
            let addr = from_decode.rv1 + imm;
            Bit#(2) offset = addr[1:0];
            if (isMemoryInst(from_decode.dinst)) begin
                // Technical details for load byte/halfword/word
                let shift_amount = {offset, 3'b0};
                let byte_en = 0;
                case (size) matches
                2'b00: byte_en = 4'b0001 << offset;
                2'b01: byte_en = 4'b0011 << offset;
                2'b10: byte_en = 4'b1111 << offset;
                endcase
                data = from_decode.rv2 << shift_amount;
                addr = {addr[31:2], 2'b0};
                isUnsigned = funct3[2];
                let type_mem = (from_decode.dinst.inst[5] == 1) ? byte_en : 0;
                let req = Mem {byte_en : type_mem,
                        addr : addr,
                        data : data};
                if (isMMIO(addr)) begin 
                    toMMIO.enq(req);
                    labelKonataLeft(lfh,from_decode.k_id, $format(" (MMIO)", fshow(req)));
                    mmio = True;
                end else begin 
                    labelKonataLeft(lfh,from_decode.k_id, $format(" (MEM)", fshow(req)));
                    toDmem.enq(req);
                end
            end
            else if (isControlInst(from_decode.dinst)) begin
                    labelKonataLeft(lfh,from_decode.k_id, $format(" (CTRL)"));
                    data = from_decode.pc + 4; // relying on fetch pc+4
            end else begin 
                labelKonataLeft(lfh,from_decode.k_id, $format(" (ALU)"));
            end
            let controlResult = execControl32(from_decode.dinst.inst, from_decode.rv1, from_decode.rv2, imm, from_decode.pc);
            let nextPc = controlResult.nextPC;

            if(from_decode.ppc != nextPc) begin // MISS PREDICTION!!!
                epoch[0] <= epoch[0] + 1;
                pc[0] <= nextPc;
                
                // flush the pipeline or handle the mispredicted instructions.
                // squashed.enq(from_decode.k_id);
                
            end

            let mem_bus = MemBusiness { isUnsigned : unpack(isUnsigned), size : size, offset : offset, mmio: mmio}; // CHECK IF THIS IS VALID OR NEEDS TO BE IN DIF CYCLES
            e2w.enq(E2W{mem_business: mem_bus, data: data, dinst: from_decode.dinst, k_id: from_decode.k_id });
            labelKonataLeft(lfh,from_decode.k_id, $format("ALU output %x", data));
            //bypass_val[getInstFields(from_decode.dinst.inst).rd][0] <= data; // sending the bypass value computed in executed to make it available in decode
            //rf[getInstFields(from_decode.dinst.inst).rd][1] <= data;
      
        end

        else begin // SQUASH INSTRUCTION. EPOCH DID NOT MATCH SO WE DO NOT WANT THIS INSTRUCTION
            squashed.enq(from_decode.k_id);
            scoreboard[getInstFields(from_decode.dinst.inst).rd][1] <= 0;
        end

        

    endrule

    rule writeback if (!starting);
        // TODO
        let from_execute = e2w.first();
        e2w.deq();
        writebackKonata(lfh,from_execute.k_id);
        retired.enq(from_execute.k_id);
        // state <= Fetch;
        let data = from_execute.data;
        let fields = getInstFields(from_execute.dinst.inst);


        if (isMemoryInst(from_execute.dinst)) begin // (* // write_val *)
            let resp = ?;
		    if (from_execute.mem_business.mmio) begin 
                resp = fromMMIO.first();
		        fromMMIO.deq();
		    end else begin 
                resp = fromDmem.first();
		        fromDmem.deq();
		    end
            let mem_data = resp.data;
            mem_data = mem_data >> {from_execute.mem_business.offset ,3'b0};
            case ({pack(from_execute.mem_business.isUnsigned), from_execute.mem_business.size}) matches
	     	3'b000 : data = signExtend(mem_data[7:0]);
	     	3'b001 : data = signExtend(mem_data[15:0]);
	     	3'b100 : data = zeroExtend(mem_data[7:0]);
	     	3'b101 : data = zeroExtend(mem_data[15:0]);
	     	3'b010 : data = mem_data;
             endcase
		end

        // if (!from_execute.dinst.legal) begin

		// 	pc[2] <= 0;	// Fault. 
	    // end

		if (from_execute.dinst.valid_rd) begin
            let rd_idx = fields.rd;
            scoreboard[rd_idx][0] <= 0; // ADDED THIS
            if (rd_idx != 0) begin rf[rd_idx][0] <=data; end // CHANGED THIS SO THAT RF USES EHR
		end

	   	// In writeback is also the moment where an instruction retires (there are no more stages)
	endrule
		

	// ADMINISTRATION:

    rule administrative_konata_commit;
		    retired.deq();
		    let f = retired.first();
		    commitKonata(lfh, f, commit_id);
	endrule
		
	rule administrative_konata_flush;
		    squashed.deq();
		    let f = squashed.first();
		    squashKonata(lfh, f);
	endrule
		
    method ActionValue#(Mem) getIReq();
		toImem.deq();
		return toImem.first();
    endmethod
    method Action getIResp(Mem a);
    	fromImem.enq(a);
    endmethod
    method ActionValue#(Mem) getDReq();
		toDmem.deq();
		return toDmem.first();
    endmethod
    method Action getDResp(Mem a);
		fromDmem.enq(a);
    endmethod
    method ActionValue#(Mem) getMMIOReq();
		toMMIO.deq();
		return toMMIO.first();
    endmethod
    method Action getMMIOResp(Mem a);
		fromMMIO.enq(a);
    endmethod
endmodule

