; 我们会在链接阶段巧妙地将entry.asm的代码放在内核代码的最开始部分
; 使得bootloader在执行跳转到0x20000后，即内核代码的起始指令，执行的第一条指令是jmp setup_kernel

; 在jmp指令执行后，我们便跳转到使用C++编写的函数setup_kernel，此后我们便可以使用C++来写内核了

extern setup_kernel
enter_kernel:
    jmp setup_kernel