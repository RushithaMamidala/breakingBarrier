#ifndef MIN_HEAP_H
#define MIN_HEAP_H

#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <stdbool.h>

typedef struct {
    int vertex;  
    int dist;    
} heapNode;

typedef struct {
    heapNode* arr;
    int size;
    int capacity;
} minHeap;

minHeap* createMinHeap(int capacity);
void freeMinHeap(minHeap* h);
void pushHeap(minHeap* h, int vertex, int dist);
heapNode popHeap(minHeap* h);
bool isEmptyHeap(minHeap* h);

#endif
