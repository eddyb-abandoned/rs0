format ELF64

; # RS-3 Dual Stack Machine

; ## Notation
; S: Data stack
; R: Return stack
; IP: Instruction pointer
; immN: Immediate bits following the opcode

; ## Memory layout
; 0x0000_0000..0x0000_1000 Zero page
; 0x0000_1000..0x0000_2000 VM native code
; 0x0000_2000..0x1000_0000 Code & read-only data
; 0x1000_0000..0xfff0_0000 Arena
; 0xfff0_0000..0xfff0_1000 Guard page
; 0xfff0_1000..0xffff_f000 Data stack
; 0xffff_f000..0xffff_fffe Guard page

; At the end of the address space, within the upper
; guard page, there are several builtin call targets:
; 0xffff_fffe vm.print(data, len)
; 0xffff_ffff vm.exit()

; ## Register usage
; R8D: Data stack pointer (S.P)
; RSP: Return stack pointer (R.P)
; R9D: Instruction pointer (IP)
; EAX: General purpose temporary register
; EBX: Byte fetch register (BL = [IP++])

; NB: The return stack is not visible within the VM memory

; ## Instruction set
; 00 NOP
; 01 LIT8       S.push(imm8 as i32)
; 02 LIT32      S.push(imm32)
; 03 CALL       R.push(IP + 1), IP = S.pop()
; 04 RET        IP = R.pop()
; 05 JMP        IP = S.pop()
; 06 CMP        S.push([S.pop(), S.pop(), S.pop()][S.pop().cmp(S.pop())])
; 1x ALU        S.push([+, -, *, /, %, &, |, ^][op - 0x10](S.pop(), S.pop()))
; 18 DIVREM     a = S.pop(), b = S.pop(), S.push(b / a), S.push(b % a)
;
; 80-BF GET     S.push(S[op & 0x3f])
; C0-FF SET     S[op & 0x3f] = S.pop()
; .. UD         vm.panic("Undefined instruction")

section "vm.native" executable

vm.SP equ r8d
vm.RP equ rsp
vm.IP equ r9d

; TODO check stack bounds
macro vm.push_ r, x {
    sub vm.#r#P, 4
    mov [vm.#r#P], dword x
}
macro vm.pop_ r, x {
    mov dword x, [vm.#r#P]
    add vm.#r#P, 4
}

macro S.push x {vm.push_ S, x}
macro S.pop x {vm.pop_ S, x}
macro R.push x {vm.push_ R, x}
macro R.pop x {vm.pop_ R, x}

op.table:
    ; 00 - 0F
    dq op.nop, op.lit8, op.lit32, op.call, op.ret, op.jmp, op.cmp, op.ud
    times 8 dq op.ud
    ; 10 - 18
    dq alu.add, alu.sub, alu.mul, alu.and, alu.or, alu.xor, op.ud, op.ud
    dq alu.divrem
op.last = 0x18
;    times 256-op.last dq op.ud

op.nop:
    jmp vm.loop

op.lit8:
    mov bl, [vm.IP]
    inc vm.IP
    S.push ebx
    jmp vm.loop

op.lit32:
    mov eax, [vm.IP]
    add vm.IP, 4
    S.push eax
    jmp vm.loop

op.call:
    R.push vm.IP
op.jmp:
    S.pop vm.IP
op.jmp.check:
    cmp vm.IP, 0
    jl op.jmp.builtin
    jmp vm.loop

op.jmp.builtin:
    inc vm.IP ; 0xffff_ffff
    jz vm.exit

    inc vm.IP ; 0xffff_fffe
    jnz op.jmp.builtin.undef

    S.pop edx ; len
    S.pop esi ; data
    call vm.print
    jmp op.ret

op.jmp.builtin.undef:
    mov esi, msg.undef_builtin
    mov edx, msg.undef_builtin.len
    jmp vm.panic

op.ret:
    R.pop vm.IP
    jmp op.jmp.check

op.dup:
    mov eax, [vm.SP]
    S.push eax
    jmp vm.loop

op.cmp:
    ; Stack: [a, b, lt, eq, gt] <- SP
    add vm.SP, 4 * 4 ; Point SP to a
    mov eax, [vm.SP]
    cmp eax, [vm.SP-4] ; a, b
    cmovl eax, [vm.SP-2*4] ; lt
    cmove eax, [vm.SP-3*4] ; eq
    cmovg eax, [vm.SP-4*4] ; gt
    mov [vm.SP], eax
    jmp vm.loop

macro op.alu op {
    alu.#op:
        S.pop eax
        op [vm.SP], eax
        jmp vm.loop
}

op.alu add
op.alu sub
op.alu and
op.alu or
op.alu xor

alu.mul:
    S.pop eax
    imul eax, [vm.SP]
    mov [vm.SP], eax
    jmp vm.loop

alu.divrem:
    mov eax, [vm.SP+4] ; dividend
    cdq ; edx:eax = sext eax

    idiv dword [vm.SP] ; divisor
    mov [vm.SP+4], eax ; quotient
    mov [vm.SP], edx ; remainder
    jmp vm.loop

op.getset:
    shl bl, 2 ; CF = op & 0x40, BL = (op & 0x3f) * 4
    jc op.set
op.get:
    mov eax, [vm.SP + ebx]
    S.push eax
    jmp vm.loop
op.set:
    S.pop eax
    mov [vm.SP + ebx], eax
    jmp vm.loop

op.ud:
    mov esi, msg.undef_op
    mov edx, msg.undef_op.len
vm.panic:
    push qword vm.exit
vm.print:
    ; sys_write(stdout, data=esi, len=edx)
    mov eax, 1
    mov edi, 1
    syscall
    ret

vm.exit:
    ; sys_exit(0)
    mov eax, 60
    mov edi, 0
    syscall
    jmp $

public vm.start
vm.start:
    ; Initialize VM registers
    mov vm.IP, 0x00002000
    mov vm.SP, 0xfffff000
    xor ebx, ebx

    ; Prevent one too many returns.
    R.push 0xffffffff

vm.loop:
    mov bl, [vm.IP]
    inc vm.IP

    cmp bl, 0x80
    jae op.getset

    cmp bl, op.last
    ja op.ud

    jmp qword [op.table + ebx * 8]

msg.undef_op: db "Undefined instruction\n"
msg.undef_op.len = $ - msg.undef_op

msg.undef_builtin: db "Undefined builtin function\n"
msg.undef_builtin.len = $ - msg.undef_builtin

section "vm.arena"
section "vm.stack"
