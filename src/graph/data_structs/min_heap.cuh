#ifndef MIN_HEAP_CUH
#define MIN_HEAP_CUH

typedef struct
{
    int node;
    int dist;
}
node_data_t;

typedef struct
{
    node_data_t *arr;
    int size;
    int capacity;
}
min_heap_t;

void init_min_heap(min_heap_t *h, int capacity);
void deinit_min_heap(min_heap_t *h);

int push_min_heap(min_heap_t *h, int node, int dist);
node_data_t pop_min_heap(min_heap_t *h);

bool is_empty_heap(min_heap_t *h);

#endif
