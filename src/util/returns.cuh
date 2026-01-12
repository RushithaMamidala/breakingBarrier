#pragma once

typedef struct
{
    int count;
    int capacity;
    int* nodes;
    char *in_set;
}node_set;

typedef struct
{
    node_set* p;
    node_set* w;
}pivot_returns;

typedef struct
{
    double bound;
    node_set* U;
}bmssp_returns;

void init_node_set(node_set *g, int capacity);

void copy_node_set(node_set* source_set, node_set* destination_set);

void append_node_set(node_set* main_set, node_set* append_set);

void free_node_set(node_set* n);

void print_node_set(node_set* n);

void node_set_add(node_set* n, int v) ;