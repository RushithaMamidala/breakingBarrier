#include "minHeap.h"

static void swap(heapNode* a, heapNode* b) {
    heapNode tmp = *a;
    *a = *b;
    *b = tmp;
}

minHeap* createMinHeap(int capacity) {
    minHeap* h = (minHeap*) malloc(sizeof(minHeap));
    h->arr = (heapNode*) malloc(sizeof(heapNode) * capacity);
    h->size = 0;
    h->capacity = capacity;
    return h;
}

void freeminHeap(minHeap* h) {
    free(h->arr);
    free(h);
}

bool isEmptyHeap(minHeap* h) {
    return h->size == 0;
}

void pushHeap(minHeap* h, int vertex, int dist) {
    if (h->size == h->capacity) {
        fprintf(stderr, "Heap overflow\n");
        return;
    }

    int i = h->size++;
    h->arr[i].vertex = vertex;
    h->arr[i].dist = dist;

    // bubble up
    while (i > 0 && h->arr[(i - 1) / 2].dist > h->arr[i].dist) {
        swap(&h->arr[i], &h->arr[(i - 1) / 2]);
        i = (i - 1) / 2;
    }
}

heapNode popHeap(minHeap* h) {
    if (h->size == 0) {
        fprintf(stderr, "Heap underflow\n");
        heapNode dummy = { -1, INT_MAX };
        return dummy;
    }

    heapNode root = h->arr[0];
    h->arr[0] = h->arr[--h->size];

    // heapify down
    int i = 0;
    while (1) {
        int l = 2 * i + 1;
        int r = 2 * i + 2;
        int smallest = i;

        if (l < h->size && h->arr[l].dist < h->arr[smallest].dist)
            smallest = l;
        if (r < h->size && h->arr[r].dist < h->arr[smallest].dist)
            smallest = r;

        if (smallest != i) {
            swap(&h->arr[i], &h->arr[smallest]);
            i = smallest;
        } else break;
    }

    return root;
}
