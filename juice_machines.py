#!/bin/python3

import re
import sys
import math
import random
import os

#
# implement method/function with name 'machine' below.
#
# The function is expected to return a value of type INTEGER.
# The function accepts following parameters:
#  1. ar is of type INTEGER ARRAY.


def machine(ar):
    n = len(ar) // 2
    total = 0
    current = 0
    start = 0
    for i in range(n):
        diff = ar[2 * i] - ar[2 * i + 1]
        total += diff
        current += diff
        if current < 0:
            start = i + 1
            current = 0
    return start if total >= 0 else -1


if __name__ == '__main__':
    fptr = open(os.environ['OUTPUT_FILE_PATH'], 'w')
    fptr.write('\n')
    ar_count = int(input().strip())

    ar = []
    arItems = input().rstrip().split(" ")

    for i in range(ar_count):
        ar_item = int(arItems[i])
        ar.append(ar_item)

    outcome = machine(ar)

    fptr.write(str(outcome) + '\n');

    fptr.close()
