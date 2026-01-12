#pragma once

typedef struct
{
    int node;
    double dist;
}
min_heap_node;

typedef struct
{
    min_heap_node *data;
    int size;
    int capacity;
}
min_heap;

void init_min_heap(min_heap *h, int capacity);
void free_min_heap(min_heap *h);

int push_min_heap(min_heap *h, int node, double dist);
void pop_min_heap(min_heap *h);
min_heap_node heap_top(min_heap *h); 

bool is_empty_heap(min_heap *h);
void print_min_heap(min_heap *h);

