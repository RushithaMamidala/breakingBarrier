#include "min_heap.cuh"
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

void init_min_heap(min_heap_t *h, int capacity)
{
    h->arr = (node_data_t *)malloc(sizeof(node_data_t) * capacity);

    h->size = 0;
    h->capacity = capacity;
}

void deinit_min_heap(min_heap_t *h)
{
    free(h->arr);
}

bool is_empty_heap(min_heap_t *h)
{
    return h->size == 0;
}

void swap_node_data(node_data_t *a, node_data_t *b)
{
    node_data_t tmp = *a;
    *a = *b;
    *b = tmp;
}

int push_min_heap(min_heap_t *h, int node, int dist)
{
    if (h->size == h->capacity)
    {
        fprintf(stderr, "Heap overflow!\n");
        return -1;
    }

    // Insert
    int i = h->size++;
    h->arr[i].node = node;
    h->arr[i].dist = dist;

    // Bubble up
    while (i > 0 && h->arr[(i - 1) / 2].dist > h->arr[i].dist)
    {
        swap_node_data(&h->arr[i], &h->arr[(i - 1) / 2]);
        i = (i - 1) / 2;
    }

    return 0;
}

node_data_t pop_min_heap(min_heap_t *h)
{
    if (h->size == 0)
    {
        fprintf(stderr, "Heap underflow!\n");
        node_data_t dummy = { -1, INT_MAX };
        return dummy;
    }

    // Pop
    node_data_t root = h->arr[0];
    h->arr[0] = h->arr[--h->size];

    // Heapify down
    int i = 0;
    while (true)
    {
        int l = 2 * i + 1;  // Left
        int r = 2 * i + 2;  // Right
        int smallest = i;

        // Update smallest
        if (l < h->size && h->arr[l].dist < h->arr[smallest].dist)
        {
            smallest = l;
        }
        if (r < h->size && h->arr[r].dist < h->arr[smallest].dist)
        {
            smallest = r;
        }

        // No change?
        if (smallest == i) { break; }

        // Make the next swap
        swap_node_data(&h->arr[i], &h->arr[smallest]);
        i = smallest;
    }

    return root;
}
