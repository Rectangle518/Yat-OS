#include "stdio.h"
#include "os_type.h"
#include "asm_utils.h"

STDIO::STDIO()
{
    initialize();
}

void STDIO::initialize()
{
    // 初始化屏幕指针，指向显存的起始地址
    screen = (uint8 *)0xb8000;
}

// 三个重载的print是直接向显存写入字符和颜色

void STDIO::print(uint x, uint y, uint8 c, uint8 color)
{

    if (x >= 25 || y >= 80)
    {
        return;
    }

    uint pos = x * 80 + y;
    screen[2 * pos] = c;
    screen[2 * pos + 1] = color;
}

void STDIO::print(uint8 c, uint8 color)
{
    uint cursor = getCursor();
    screen[2 * cursor] = c;
    screen[2 * cursor + 1] = color;
    cursor++;
    if (cursor == 25 * 80)
    {
        rollUp();
        cursor = 24 * 80;
    }
    moveCursor(cursor);
}

void STDIO::print(uint8 c)
{
    print(c, 0x07);
}

// 屏幕的像素为25*80，所以光标的位置从上到下，从左到右依次编号为0-1999，用16位表示

// 与光标读写相关的端口为0x3d4和0x3d5
// 在对光标读写之前，我们需要向端口0x3d4写入数据，表明我们操作的是光标的低8位还是高8位
// 写入0x0e表示操作的是高8位，写入0x0f表示操作的是低8位

// 如果我们需要需要读取光标，那么我们从0x3d5从读取数据
// 如果我们需要更改光标的位置，那么我们将光标的位置写入0x3d5

void STDIO::moveCursor(uint position)
{
    if (position >= 80 * 25)
    {
        return;
    }

    uint8 temp;

    // 处理高8位
    temp = (position >> 8) & 0xff;
    asm_out_port(0x3d4, 0x0e);
    asm_out_port(0x3d5, temp);

    // 处理低8位
    temp = position & 0xff;
    asm_out_port(0x3d4, 0x0f);
    asm_out_port(0x3d5, temp);
}

uint STDIO::getCursor()
{
    uint pos;
    uint8 temp;

    pos = 0;
    temp = 0;
    // 处理高8位
    asm_out_port(0x3d4, 0x0e);
    asm_in_port(0x3d5, &temp);
    pos = ((uint)temp) << 8;

    // 处理低8位
    asm_out_port(0x3d4, 0x0f);
    asm_in_port(0x3d5, &temp);
    pos = pos | ((uint)temp);

    return pos;
}

void STDIO::moveCursor(uint x, uint y)
{
    if (x >= 25 || y >= 80)
    {
        return;
    }

    moveCursor(x * 80 + y);
}

// 如果过光标超出了屏幕的范围，即字符占满了整个屏幕，我们需要向上滚屏，然后将光标放在(24,0)处
// 滚屏实际上就是将第2行的字符放到第1行，第3行的字符放到第2行
// 以此类推，最后第24行的字符放到了第23行，然后第24行清空，光标放在第24行的起始位置
void STDIO::rollUp()
{
    uint length;
    length = 25 * 80;
    for (uint i = 80; i < length; ++i)
    {
        screen[2 * (i - 80)] = screen[2 * i];
        screen[2 * (i - 80) + 1] = screen[2 * i + 1];
    }

    for (uint i = 24 * 80; i < length; ++i)
    {
        screen[2 * i] = ' ';
        screen[2 * i + 1] = 0x07;
    }
}