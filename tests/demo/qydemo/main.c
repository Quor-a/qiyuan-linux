#include <stdio.h>
#include <qydemo.h>

int main(void)
{
    printf("qydemo %s\n", qydemo_version());
    printf("1 + 2 = %d\n", qydemo_add(1, 2));
    return 0;
}
