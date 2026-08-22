	#define CREATE_COLOR(r, g, b, a) new float[4] {(float)r, (float)g, (float)b, (float)a};
	uint32_t Color[] = {0x53BB0C, 0x530826, 0x0FC3F4, 0xDC2855, 0x0A31DE, 0xBAA7FD, 0xCEDB3F, 0x286A45, 0x58F014, 0x45CAE6, 0x773702, 0xB0CEF0, 0x3C5F51, 0x453CD7, 0x364024, 0x439997, 0x4CB612, 0xC6B564, 0x17F250, 0xE41BC0, 0xAF8E27, 0x8E382E, 0x47A101, 0x9DAC33, 0x66F4CF, 0x59A9F0, 0x798D1A, 0x2EBB59, 0xBF66C3, 0x4BD8FB, 0xBBFA54, 0x6B9881, 0x144967, 0xBAA3AE, 0xE80B9D, 0x7BA552, 0x96A456, 0x17D7B4, 0x130C39, 0x3C06A8, 0x62737E, 0xA87E89, 0xB6D3E4, 0x66B77D, 0x66E304, 0x1B80E1, 0x7A06BC, 0xBFFB1B, 0x618506, 0x7E4D34};

long Random1(int index) {
    srand(index);

    int a = 255;
    int r = ((Color[rand() % sizeof(Color)] & 0xFF0000) >> 17);
    int g = ((Color[rand() % sizeof(Color)] & 0x00FF00) >> 9);
    int b = (Color[rand() % sizeof(Color)] & 0x0000FF);

    return IM_COL32(r, g, b, a);
}
long Random2(int index) {
    srand(index);

    int a = 130;
    int r = ((Color[rand() % sizeof(Color)] & 0xFF0000) >> 17);
    int g = ((Color[rand() % sizeof(Color)] & 0x00FF00) >> 9);
    int b = (Color[rand() % sizeof(Color)] & 0x0000FF);

    return IM_COL32(r, g, b, a);
}


