#pragma once

// A min-heap of min-max heaps
typedef struct
{
  int *verts;
  double *dists;
  int num_blocks;
  int num_items_tail;
  int capacity_items;
  int capacity_blocks;
}
block_list_t;

void init_block_list(block_list_t *b, int capacity_items, int capacity_blocks);
void deinit_block_list(block_list_t *b);

void push_block_list(block_list_t *b, int vert, double dist);
void pop_block_list(block_list_t *b, int *verts, double *dists, double *upper_bound);

void print_block_list(block_list_t *b);

bool is_empty_block_list(block_list_t *b);