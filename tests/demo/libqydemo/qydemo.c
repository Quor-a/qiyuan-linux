#include "qydemo.h"

static const char _version[] = "0.2.0";

const char *qydemo_version(void)
{
    return _version;
}

int qydemo_add(int a, int b)
{
    return a + b;
}
