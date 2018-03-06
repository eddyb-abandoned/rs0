vm.SP equ r8
vm.RP equ rsp
vm.IP equ r9d
vm.IP.base equ r10
vm.IP.mem equ r10 + r9
vm.mem.base equ r12

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

imm.varuint32:
    xor eax, eax
    xor cl, cl
imm.varuint32.loop:
    inc vm.IP
    mov bl, [vm.IP.mem - 1]
    mov edx, ebx
    and edx, 0x7f
    shl edx, cl
    or eax, edx
    add cl, 7
    test bl, 0x80
    jnz imm.varuint32.loop
    ret

imm.varint32:
    xor eax, eax
    xor cl, cl
imm.varint32.loop:
    inc vm.IP
    mov bl, [vm.IP.mem - 1]
    mov edx, ebx
    and edx, 0x7f
    shl edx, cl
    or eax, edx
    add cl, 7
    test bl, 0x80
    jnz imm.varint32.loop
    ; Sign-extend the last 7-bit group
    neg cl
    add cl, 32
    cmp cl, 0
    jl imm.varint32.ret
    shl eax, cl
    sar eax, cl
imm.varint32.ret:
    ret

op.table: times 256 dq (op.ud - $$)

macro def_op opcode {
    store qword ($ - $$) at op.table + opcode * 8
}

def_op 0x00 ; unreachable
    mov rsi, msg.trap_op
    mov rdx, msg.trap_op.len
    call vm.panic

def_op 0x01 ; nop
    jmp vm.loop

def_op 0x0c ; br
    call imm.varuint32
    mov vm.IP, eax
    jmp vm.loop

def_op 0x0d ; br_if
    call imm.varuint32
    S.pop ecx
    cmp ecx, 0
    jz vm.loop
    mov vm.IP, eax
    jmp vm.loop

def_op 0x0f ; return
op.ret:
    R.pop vm.IP
    jmp vm.loop

def_op 0x10 ; call
    call imm.varuint32
    R.push vm.IP
    cmp eax, 0
    jl vm.call.builtin
    mov vm.IP, eax
    jmp vm.loop

def_op 0x41 ; i32.const
    call imm.varint32
    S.push eax
    jmp vm.loop

; S.push(f(S.pop(), S.pop()))
macro def_op.i32.binop opcode, op {
    def_op opcode
        S.pop eax
        op [vm.SP], eax
        jmp vm.loop
}

def_op.i32.binop 0x6a, add ; i32.add
def_op.i32.binop 0x6b, sub ; i32.sub

def_op 0x6c ; i32.mul
    S.pop eax
    imul eax, [vm.SP]
    mov [vm.SP], eax
    jmp vm.loop

; div(S.pop(), S.pop()); S.push(out)
macro def_op.i32.divrem opcode, div, out {
    def_op opcode
        S.pop ecx ; divisor
        mov eax, [vm.SP] ; dividend
        if div eq idiv
            cdq ; edx:eax = sext eax
        else
            xor edx, edx
        end if

        div ecx
        mov [vm.SP], out
        jmp vm.loop
}

def_op.i32.divrem 0x6d, idiv, eax ; i32.div_s
def_op.i32.divrem 0x6e, div, eax ; i32.div_u
def_op.i32.divrem 0x6f, idiv, edx ; i32.rem_s
def_op.i32.divrem 0x70, div, edx ; i32.rem_u

def_op.i32.binop 0x71, and ; i32.and
def_op.i32.binop 0x72, or ; i32.or
def_op.i32.binop 0x73, xor ; i32.xor

; Legacy (pre-WASM) RS-3 opcodes
def_op 0xf1 ; CMP        S.push([S.pop(), S.pop(), S.pop()][S.pop().cmp(S.pop())])
    ; Stack: [a, b, lt, eq, gt] <- SP
    add vm.SP, 4 * 4 ; Point SP to a
    mov eax, [vm.SP]
    cmp eax, [vm.SP-4] ; a, b
    cmovl eax, [vm.SP-2*4] ; lt
    cmove eax, [vm.SP-3*4] ; eq
    cmovg eax, [vm.SP-4*4] ; gt
    mov [vm.SP], eax
    jmp vm.loop

def_op 0xf2 ; GET        S.push(S[varuint32])
    call imm.varuint32
    mov eax, [vm.SP + rax * 4]
    S.push eax
    jmp vm.loop

def_op 0xf3 ; SET        S[varuint32] = S.pop()
    call imm.varuint32
    S.pop ecx
    mov [vm.SP + rax * 4], ecx
    jmp vm.loop

op.ud:
    mov rsi, msg.undef_op
    mov rdx, msg.undef_op.len
    jmp vm.panic

vm.call.builtin:
    inc eax ; 0xffff_ffff
    jz vm.exit

    inc eax ; 0xffff_fffe
    jz vm.call.builtin.print

    jmp vm.call.builtin.undef

vm.call.builtin.print:
    S.pop edx ; len
    S.pop esi ; data
    ; Clamp the length to the 32-bit address space.
    add rdx, rsi
    mov edx, edx
    sub rdx, rsi
    add rsi, vm.mem.base
    call vm.print
    jmp op.ret

vm.call.builtin.undef:
    mov rsi, msg.undef_builtin
    mov rdx, msg.undef_builtin.len
    jmp vm.panic

vm.panic:
    call vm.print
    jmp vm.exit

public start
start:
    ; Initialize VM registers
    extrn vm.code.start
    mov vm.IP.base, vm.code.start
    mov vm.IP, 0x00000000
    xor ebx, ebx

    ; Prevent one too many returns.
    R.push 0xffffffff

    ; Set up the 4GiB guest address space.
    mov rsi, 0x100000000
    call vm.alloc
    mov vm.mem.base, rax

    ; Copy in the static data.
    extrn vm.data.start
    extrn vm.data.end
    mov rsi, vm.data.start
    mov rdi, vm.mem.base
    mov rcx, vm.data.end
    sub rcx, rsi
    rep movsb

    ; Set up the stack area.
    mov rsi, 0x10000000
    call vm.alloc
    lea vm.SP, [rax + 0xffff000]

    mov r15, $$

vm.loop:
    ; TODO(eddyb) Check that vm.IP is within bounds.
    mov bl, [vm.IP.mem]
    inc vm.IP
    ; HACK(eddyb) Relative addressing - should figure out RIP-relative instead.
    mov rcx, [r15 + (op.table - $$) + rbx * 8]
    add rcx, r15
    jmp rcx

msg.trap_op: db "Trap instruction", 10
msg.trap_op.len = $ - msg.trap_op

msg.undef_op: db "Undefined instruction", 10
msg.undef_op.len = $ - msg.undef_op

msg.undef_builtin: db "Undefined builtin function", 10
msg.undef_builtin.len = $ - msg.undef_builtin
