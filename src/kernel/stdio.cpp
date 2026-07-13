#include "stdio.h"
#include "os_type.h"
#include "asm_utils.h"
#include "os_modules.h"
#include "stdarg.h"
#include "stdlib.h"

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

// 打印字符串到控制台
int STDIO::print(const char *const str)
{
    int i = 0;

    // 遍历字符串
    for (i = 0; str[i]; ++i) 
    {
        switch(str[i])
        {
            // 处理换行符
            case '\n':
                uint row;  // 当前行号
                row = getCursor() / 80;  // 获取当前光标所在的行号(假设每行80字符)
                // 如果当前是最后一行(第24行)
                if (row == 24)
                {
                    rollUp();  // 向上滚动屏幕
                }
                else 
                {
                    ++row;  // 若不是最后一行，则移动到下一行
                }
                moveCursor(row * 80);  // 将光标移动到新行的开始位置
                break;

            // 处理普通字符
            default:
                print(str[i]);  // 直接打印字符
                break;
        }
    }

    return i;  // 返回打印的字符数
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

// 将fmt[i]放到缓冲区
int printf_add_to_buffer(char *buffer, char c, int &idx, const int BUF_LEN)
{
    int counter = 0;

    buffer[idx] = c;
    ++idx;

    // 如果缓冲区满，则将缓冲区输出并清空
    if (idx == BUF_LEN)
    {
        buffer[idx] = '\0';
        counter = stdio.print(buffer);
        idx = 0;
    }

    // 返回打印的字符数
    return counter;
}

int printf(const char *const fmt, ...)
{
    // 缓冲区大小为32
    const int BUF_LEN = 32;

    // 多出来的1个字符是用来放置\0的
    char buffer[BUF_LEN + 1];

    // 后面会将一个整数转化为字符串表示，number使用来存放转换后的数字字符串
    // 保护模式是运行在32位环境下的，最大的数字字符串也不会超过32位
    char number[33];

    int idx, counter;
    va_list ap;

    // 让ap指向fmt后面的第一个参数
    va_start(ap, fmt);

    // idx表示缓冲区的下标，counter表示累计打印的字符数
    idx = 0;
    counter = 0;

    // 遍历 fmt
    for (int i = 0; fmt[i]; ++i)
    {
        if (fmt[i] != '%')
        {
            counter += printf_add_to_buffer(buffer, fmt[i], idx, BUF_LEN);
        }
        else
        {
            i++;
            if (fmt[i] == '\0')
            {
                break;
            }

            switch (fmt[i])
            {
            case '%':
                // 处理%符号
                counter += printf_add_to_buffer(buffer, fmt[i], idx, BUF_LEN);
                break;

            case 'c':
                // 处理字符，将字符放到缓冲区
                counter += printf_add_to_buffer(buffer, va_arg(ap, char), idx, BUF_LEN);
                break;

            case 's':
                // 处理字符串，清空当前缓冲区，然后直接打印字符串
                buffer[idx] = '\0';
                idx = 0;
                counter += stdio.print(buffer);
                counter += stdio.print(va_arg(ap, const char *));
                break;

            case 'd':
            case 'x':
                // 处理整数，先判断正负，再处理进制转换，最后将转换后的结果以字符串形式存进number，再逐个字符放到缓冲区
                int temp = va_arg(ap, int);

                if (temp < 0 && fmt[i] == 'd')
                {
                    counter += printf_add_to_buffer(buffer, '-', idx, BUF_LEN);
                    temp = -temp;
                }

                itos(number, temp, (fmt[i] == 'd' ? 10 : 16));

                for (int j = temp - 1; j >= 0; --j)
                {
                    counter += printf_add_to_buffer(buffer, number[j], idx, BUF_LEN);
                }
                break;

            }
        }
    }

    // 最后清空缓冲区，并全部打印出来
    buffer[idx] = '\0';
    counter += stdio.print(buffer);

    return counter;
}