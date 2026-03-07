import core.stdc.stdio : printf;

extern(C) int main(int argc, const(char) **argv)
{
    printf("argv[0]=", argv[0]);
    return 0;
}
