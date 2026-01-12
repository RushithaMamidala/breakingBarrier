#include "min_heap.cuh"
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

void init_min_heap(min_heap* h, int capacity)
{
    h->data = (min_heap_node *)malloc(sizeof(min_heap_node) * capacity);

    h->size = 0;
    h->capacity = capacity;
}

void free_min_heap(min_heap *h)
{
    free(h->data);
}

bool is_empty_heap(min_heap *h)
{
    return h->size == 0;
}

void swap_node_data(min_heap_node *a, min_heap_node *b)
{
    min_heap_node tmp = *a;
    *a = *b;
    *b = tmp;
}

int push_min_heap(min_heap *h, int node, double dist)
{
    if (h->size == h->capacity)
    {
        fprintf(stderr, "Heap overflow!\n");
        return -1;
    }

    // Insert
    int i = h->size++;
    h->data[i].node = node;
    h->data[i].dist = dist;

    // Bubble up
    while (i > 0 && h->data[(i - 1) / 2].dist > h->data[i].dist)
    {
        swap_node_data(&h->data[i], &h->data[(i - 1) / 2]);
        i = (i - 1) / 2;
    }

    return 0;
}

min_heap_node heap_top(min_heap *h) { return h->data[0]; }

void pop_min_heap(min_heap *h)
{
    if (h->size == 0)
    {
        fprintf(stderr, "Heap underflow!\n");
        // min_heap_node dummy = { -1, INT_MAX };
        return;
    }

    // Pop
    h->data[0] = h->data[--h->size];

    // Heapify down
    int i = 0;
    while (true)
    {
        int l = 2 * i + 1;  // Left
        int r = 2 * i + 2;  // Right
        int smallest = i;

        // Update smallest
        if (l < h->size && h->data[l].dist < h->data[smallest].dist)
        {
            smallest = l;
        }
        if (r < h->size && h->data[r].dist < h->data[smallest].dist)
        {
            smallest = r;
        }

        // No change?
        if (smallest == i) { break; }

        // Make the next swap
        swap_node_data(&h->data[i], &h->data[smallest]);
        i = smallest;
    }

}

void print_min_heap(min_heap *h)
{
    if (!h || !h->data) {
        printf("Heap not initialized.\n");
        return;
    }

    printf("Min Heap (size=%d, capacity=%d):\n", h->size, h->capacity);
    for (int i = 0; i < h->size; i++) {
        printf("  index=%d  node=%d  dist=%.2f\n",
               i, h->data[i].node, h->data[i].dist);
    }
}

