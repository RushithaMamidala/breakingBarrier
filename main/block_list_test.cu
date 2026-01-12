#include "data_structs/block_list.cuh"
#include <stdio.h>

int main(int argc, char **argv)
{
  int block_size;
  int capacity;
  printf("Block Size: ");
  scanf("%d", &block_size);
  printf("Capacity: ");
  scanf("%d", &capacity);

  block_list_t b;
  init_block_list(&b, block_size, capacity);

  while (true)
  {
    int vert;
    double dist;
    printf("Vert: ");
    scanf("%d", &vert);
    printf("Dist: ");
    scanf("%lf", &dist);
    
    push_block_list(&b, vert, dist);
    printf("\n");
    print_block_list(&b);
    printf("\n");
  }

  deinit_block_list(&b);

  return 0;
}