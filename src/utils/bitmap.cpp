#include "bitmap.h"
#include "stdlib.h"
#include "stdio.h"

BitMap::BitMap()
{
    initialize(nullptr, 0);
}

// 设置BitMap，bitmap=起始地址，length=总位数(即被管理的资源个数)
void BitMap::initialize(char *bitmap, const int length)
{
    this->bitmap = bitmap;
    this->length = length;

    // 由于是char类型的指针，一个char类型占8个字节，所以需要向上取整
    int bytes = ceil(length, 8);

    memset(bitmap, 0, bytes);
}

// 获取第index个资源的状态，true=allocated，false=free
bool BitMap::get(const int index)
{
    int pos = index / 8;
    int offset = index % 8;

    // 判断 bitmap的第index位是否为 1
    // 先通过 pos定位到 bitmap的某个 char类型元素，然后通过 offset定位到该元素的第几位
    return (bitmap[pos] & (1 << offset));
}

// 设置第index个资源的状态，true=allocated，false=free
void BitMap::set(const int index, const bool status)
{
    int pos = index / 8;
    int offset = index % 8;

    // 清0
    bitmap[pos] = bitmap[pos] & (~(1 << offset));

    // 置1
    if (status)
    {
        bitmap[pos] = bitmap[pos] | (1 << offset);
    }
}

// 分配count个连续的资源，若没有则返回-1，否则返回分配的第1个资源单元序号
int BitMap::allocate(const int count)
{
    if (count == 0)
        return -1;

    int index, empty, start;

    index = 0;
    while (index < length)
    {
        // 越过已经分配的资源
        while (index < length && get(index))
            ++index;

        // 不存在连续的count个资源
        if (index == length)
            return -1;

        // 找到1个未分配的资源
        // 检查是否存在从index开始的连续count个资源
        empty = 0;
        start = index;
        while ((index < length) && (!get(index)) && (empty < count))
        {
            ++empty;
            ++index;
        }

        // 存在连续的count个资源
        if (empty == count)
        {
            // 将这count个资源分配出去
            for (int i = 0; i < count; ++i)
            {
                set(start + i, true);
            }

            return start;
        }
    }

    return -1;
}

// 释放第index个资源开始的count个资源
void BitMap::release(const int index, const int count)
{
    for (int i = 0; i < count; ++i)
    {
        set(index + i, false);
    }
}

// 返回Bitmap存储区域
char *BitMap::getBitmap()
{
    return (char *)bitmap;
}

// 返回Bitmap的大小
int BitMap::size() const
{
    return length;
}