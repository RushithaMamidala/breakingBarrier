#include "block_list.cuh"
#include "util/mem.cuh"
#include <stdio.h>

void init_block_list(block_list_t *b, int capacity_items, int capacity_blocks)
{
  b->verts = (int *)malloc(sizeof(int) * capacity_items * capacity_blocks);
  b->dists = (double *)malloc(sizeof(double) * capacity_items * capacity_blocks);

  b->num_items_tail = 0;
  b->num_blocks = 1;
  b->capacity_items = capacity_items;
  b->capacity_blocks = capacity_blocks;
}

void deinit_block_list(block_list_t *b)
{
  free(b->verts);
  free(b->dists);
}

inline int grandparent_idx(int i)
{
  return (i - 3) / 4;
}

inline int parent_idx(int i)
{
  return (i - 1) / 2;
}

inline int child_first_idx(int i)
{
  return (i * 2) + 1;
}

inline int grandchild_first_idx(int i)
{
  return (i * 4) + 3;
}

// T: Min, F: Max
inline bool layer_type(int i)
{
  return __builtin_clz(i + 1) % 2;
}

int *verts_block(block_list_t *b, int block)
{
  return &b->verts[b->capacity_items * block];
}

double *dists_block(block_list_t *b, int block)
{
  return &b->dists[b->capacity_items * block];
}

inline double min_block(block_list_t *b, int i)
{
  return dists_block(b, i)[0];
}

int item_count(block_list_t *b, int block)
{
  if (block == b->num_blocks - 1) { return  b->num_items_tail; }
  else                            { return  b->capacity_items; }
}

void push_down_block(block_list_t *b, int block, int idx)
{
  int *verts = verts_block(b, block);
  double *dists = dists_block(b, block);
  int num_items = item_count(b, block);

  while (idx < item_count(b, block))
  {
    int tgt_idx = idx;
    bool min_max_tf = layer_type(idx);

    // Find minimum/maximum distance among descendants
    double record;
    if (min_max_tf) { record = __DBL_MAX__; }
    else            { record = __DBL_MIN__; }
    // TODO: Merge loops?
    // Check children
    int child_idx = child_first_idx(idx);
    for (int i = 0; i < 2; i++)
    {
      // Prevent OOB
      if (child_idx >= num_items) { break; }

      double child = b->dists[child_idx];
      if ((child < record) == min_max_tf)
      {
        record = child;
        tgt_idx = child_idx;
      }

      child_idx++;
    }
    // Check grandchildren
    int grandchild_idx = grandchild_first_idx(idx);
    for (int i = 0; i < 4; i++)
    {
      // Prevent OOB
      if (grandchild_idx >= num_items) { break; }

      double grandchild = b->dists[grandchild_idx];
      if ((grandchild < record) == min_max_tf)
      {
        record = grandchild;
        tgt_idx = grandchild_idx;
      }

      grandchild_idx++;
    }

    // Conflict with child?
    if ((dists[idx] > record) == min_max_tf)
    {
      // Swap the current node with the chosen descendant
      memswp(&verts[idx], &verts[tgt_idx], sizeof(int));
      memswp(&dists[idx], &dists[tgt_idx], sizeof(double));
      
      // Swapped with grandchild?
      if (grandparent_idx(tgt_idx) == idx)
      {
        // New conflict with parent of target?
        if ((record > dists[parent_idx(tgt_idx)]) == min_max_tf)
        {
          // Swap target and its parent
          memswp(&verts[tgt_idx], &verts[parent_idx(tgt_idx)], sizeof(int));
          memswp(&dists[tgt_idx], &dists[parent_idx(tgt_idx)], sizeof(double));
        }
      }
      else { break; }
    }
  }
}

void push_up_block(block_list_t *b, int block, int i)
{

}

void append_empty_block(block_list_t *b)
{
  // Is the list full?
  if (b->num_blocks == b->capacity_blocks)
  {
    fprintf(stderr, "Block list overflow!\n");
    return;
  }
  // Update counts
  b->num_items_tail = 0;
  b->num_blocks++;
}

void push_up_tree(block_list_t *b)
{

}

// void push_up_tree(block_list_t *b)
// {
//   int i = b->num_blocks - 1;
//   double dist = *access_dist(b, i, b->num_items_tail - 1);

//   // First Iteration: Special since data is at end of block, not front
//   if (i <= 0 || dist >= *access_dist(b, (i - 1) / 2, 0))
//   {
//     // Update min of current block
//     b->min_dists[i] = min(b->min_dists[i], dist);

//     // Fix the block's max heap structure
//     max_heapify_up_block(b, i);

//     return;
//   }

//   // Current location of the new data.
//   int *p_new_vert = access_vert(b, i, b->num_items_tail - 1);
//   double *p_new_dist = access_dist(b, i, b->num_items_tail - 1);

//   // Heapify up the outer min heap
//   // Continue until parent and child ranges do not overlap
//   bool outer_fixed = false;
//   while (!outer_fixed)
//   {
//     // Root?
//     if (i <= 0) { outer_fixed = true; }
//     else
//     {
//       // Location of the maximum data of the parent.
//       // NOTE: This is always at idx 0 because we form block into max heap.
//       int *p_parent_max_vert = access_vert(b, (i - 1) / 2, 0);
//       double *p_parent_max_dist = access_dist(b, (i - 1) / 2, 0);

//       // Overlap with parent range?
//       if (dist < *p_parent_max_dist)
//       {
//         // Swap max of parent block and min of current block
//         // NOTE: Min must be the new data (there was no conflict before)!
//         memswp(p_new_vert, p_parent_max_vert, sizeof(int));
//         memswp(p_new_dist, p_parent_max_dist, sizeof(double));
//         // Point to the new location
//         p_new_vert = p_parent_max_vert;
//         p_new_dist = p_parent_max_dist;
//       }
//       else { outer_fixed = true; }
//     }

//     // Update min of current block
//     b->min_dists[i] = min(b->min_dists[i], *access_dist(b, i, 0));

//     // Fix the block's max heap structure
//     max_heapify_down_block(b, i);

//     // Move up a level
//     i = (i - 1) / 2;
//   }
// }

void push_block_list(block_list_t *b, int vert, double dist)
{
  // Is the tail full?
  if (b->num_items_tail >= b->capacity_items)
  {
    // Make a new tail block
    append_empty_block(b);
  }

  // Append to tail block
  int tail = b->num_blocks - 1;
  verts_block(b, tail)[b->num_items_tail] = vert;
  dists_block(b, tail)[b->num_items_tail] = dist;
  b->num_items_tail++;

  // Fix the block list structure
  push_up_tree(b);
}

void push_down_tree(block_list_t *b)
{
  
}

void pop_block_list(block_list_t *b, int *verts, double *dists, double *upper_bound)
{

}

// void fix_down_block_list(block_list_t *b)
// {
//   // TODO:
//   // Note: Watch out that the current block has b->num_items_tail size!!!

//   // THOUGHTS: Perhaps pop & fix one element at a time?



//   int i = 0;
//   bool outer_fixed = false;
//   while (!outer_fixed)
//   {
//     int l = 2 * i + 1; // Left
//     int r = 2 * i + 2; // Right

//     // Find the child (or self) with smallest minimum
//     double min_block = i;
//     if (l < b->num_blocks &&
//         *access_dist(b, l, 0) < *access_dist(b, i, 0))
//     {
//       min_block = l;
//     }
//     if (r < b->num_blocks &&
//         *access_dist(b, r, 0) < *access_dist(b, i, 0))
//     {
//       min_block = r;
//     }

//     // Outer heap fixed?
//     if (min_block == i) { outer_fixed = true; }
//     else
//     {
//       // Swap with the min block
//       // ...

//     }

//     // Resolve all parent-child overlaps
//     // ...

//     // Follow the swapped block down
//     i = min_block;
//   }
// }

// void pop_block_list(block_list_t *b, int *verts, double *dists, double *upper_bound)
// {
//   if (b->num_blocks == 0)
//   {
//     fprintf(stderr, "Block list underflow!\n");
//     return;
//   }

//   // Fetch first block
//   memcpy(verts, access_vert(b, 0, 0), sizeof(int) * item_count(b, 0));
//   memcpy(dists, access_dist(b, 0, 0), sizeof(double) * item_count(b, 0));

//   // Overwrite tail with head
//   int tail = b->num_blocks - 1;
//   memcpy(access_vert(b, 0, 0), access_vert(b, tail, 0), sizeof(int) * item_count(b, tail));
//   memcpy(access_dist(b, 0, 0), access_dist(b, tail, 0), sizeof(double) * item_count(b, tail));
//   b->num_blocks--;

//   // Fix the block list structure
//   fix_down_block_list(b);

//   // Peek minimum
//   *upper_bound = min_block(b, 0);
// }

void print_block_list(block_list_t *b)
{
  for (int i=0; i < b->num_blocks; i++)
  {
    printf("Block %d | Min = %lf:\n", i, min_block(b, i));
    for (int j=0; j < item_count(b, i); j++)
    {
      printf("  %d : %f\n", verts_block(b, i)[j], dists_block(b, i)[j]);
    }
  }
}

bool is_empty_block_list(block_list_t *b)
{
  return (b->num_blocks == 0);
}