#!bin/bash

nvcc -std=c++17 -O2 bptree.cu bptree_test.cu -o bptree_test
./bptree_test