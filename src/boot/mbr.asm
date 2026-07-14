
%include "boot.inc"

; 告诉编译器代码中的代码标号和数据标号从0x7c00开始
; 告诉编译器按16位代码格式编译代码
org 0x7c00
[bits 16]

; eax = 0
xor ax, ax

; 初始化段寄存器，段地址都设置为0
mov ds, ax
mov ss, ax
mov es, ax
mov fs, ax
mov gs, ax

; 设置栈指针
mov sp, 0x7c00

; 准备加载bootloader
mov ax, LOADER_START_SECTOR
mov cx, LOADER_SECTOR_COUNT
mov bx, LOADER_START_ADDRESS   

load_bootloader:

    ; 即将调用asm_read_hard_disk函数，先通过栈传入参数
    push ax               ; 传入参数：要读取的逻辑扇区号，即block参数
    push bx               ; 传入参数：要写入的内存地址，即memory参数
    call asm_read_hard_disk
    add sp, 4             ; 清理栈上的参数
    inc ax                ; 读取下一个逻辑扇区
    add bx, 512           ; 内存地址增加512字节，指向下一个扇区的内存位置
    loop load_bootloader  ; 循环读取bootloader的所有扇区

    ; 获取内存大小
    mov ax, 0xe801
    int 15h               ; 通过 int 15h 获取内存大小，这是实模式下的中断
    mov [0x7c00], ax
    mov [0x7c00+2], bx

    ; 跳转到bootloader
    ; 使用远跳转，会同时改变CS和IP寄存器的值
    jmp 0x0000:LOADER_START_ADDRESS

; 死循环
jmp $

; asm_read_hard_disk(memory, block)
; 加载逻辑扇区号为block的扇区到内存地址memory
asm_read_hard_disk:

    ; BP在函数内部，作为一个固定的参照物，便于稳定地访问到传入的参数和局部变量
    push bp
    mov bp, sp
    ; 执行完上面两句后：[bp] == 旧的bp值，[bp+2] == 返回地址，[bp+4] == 参一，[bp+6] == 参二

    ; 保存寄存器
    push ax
    push bx
    push cx
    push dx

    ; 读取参数block，它表示要读取的逻辑扇区号的低16位
    mov ax, [bp + 6]

    ; 用的是LBA28（使用28位来表示逻辑扇区的编号）
    ; 没有一个IO端口能够容纳下28位的地址，逻辑扇区号是被分成4段写入端口的
    ; 逻辑扇区的0~7位被写入0x1F3端口，8~15位被写入0x1F4端口，16~23位被写入0x1F5端口，最后4位被写入0x1F6端口的低4位

    mov dx, 0x1f3
    out dx, al               ; 0x1F3端口，写入逻辑扇区号的0~7位

    inc dx                   ; dx = 0x1F4
    mov al, ah               
    out dx, al               ; 0x1F4端口，写入逻逻辑扇区号的8~15位

    inc dx                   ; dx = 0x1F5
    xor ax, ax
    out dx, al               ; 0x1F5端口，写入逻辑扇区号的16~23位，全部为0

    inc dx                   ; dx = 0x1F6
    mov al, ah
    and al, 0x0f             ; 取逻辑扇区号的24~27位
    or al, 0xe0              ; 24~27位全部为0
    out dx, al               ; 0x1F6端口的低4位，写入逻辑扇区号的24~27位

    ; 将要读取的扇区数量写入0x1F2端口，由于这是一个8位端口，因此每次最多只能读写255个扇区
    mov dx, 0x1f2
    mov al, 1                ; 读取1个扇区
    out dx, al

    ; 向0x1F7端口写入0x20，请求硬盘读
    mov dx, 0x1f7
    mov al, 0x20
    out dx, al

    ; 等待硬盘准备好以及其他处理操作
.wait:
    ; 等待完成的标志是0x1F7端口的第7位为0，第3位为1，第0位为0，表示硬盘已经准备好
    in al, dx             ; 读取0x1F7端口的值
    and al, 0x88          ; 只保留第7位和第3位
    cmp al, 0x08          ; 检查是否准备好
    jnz .wait             ; 如果没有准备好，继续等待

    ; 读取512字节到地址ds:memory
    mov bx, [bp + 4]      ; 获取要写入的内存地址，即memory参数
    mov cx, 256           ; 每次读取2字节，共读取256次
    mov dx, 0x1f0         ; 0x1F0是硬盘接口的数据端口，16位

.readw:
    in ax, dx             ; 从硬盘接口读取2字节
    mov [bx], ax          ; 将读取到的2字节写入内存
    add bx, 2             ; 移动到下一个内存地址
    loop .readw           ; 循环读取，直到读取完512字节

    ; 恢复寄存器
    pop dx
    pop cx
    pop bx
    pop ax

    ; 恢复旧的bp值
    pop bp

    ; 返回
    ret 

; 填充字符0直到第510个字节
; 最后两个字节是0x55AA，表示这是一个有效的引导扇区
times 510 - ($ - $$) db 0
db 0x55, 0xaa