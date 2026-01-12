#include "dijkstras.cuh"
#include "data_structs/min_heap.cuh"
#include "data_structs/graph.cuh"
#include <stdio.h>

double* dijkstras(graph* g, int src)
{
  // Min heap to store nodes and dist.
  // Note: We keep duplicates, so we need at most #edges size.
  min_heap* h = (min_heap*)malloc(sizeof(min_heap));
  init_min_heap(h, g->num_nodes);
  // printf("size of min_heap: %d",h->capacity);

  // Visited nodes and their distances
  bool *visited = (bool *)malloc(sizeof(bool) * g->num_nodes);
  double *dist = (double *)malloc(sizeof(double) * g->num_nodes);
  
  for (int i = 0; i < g->num_nodes; i++)
  {
    visited[i] = false;
    dist[i] = 100000000; // Invalid
  }
  
  dist[src] = 0;
  
  // Push first node to seed Dijkstra's
  int ret = push_min_heap(h, src, 0);
  if (ret == -1) return NULL;

  while (!is_empty_heap(h))
  {
    // Pop node and dist
    
    min_heap_node u_node = heap_top(h);
    pop_min_heap(h);
    int u = u_node.node;
    double u_dist = u_node.dist;

    // Skip?
    if (visited[u] || u_dist > dist[u]) { continue; }

    visited[u] = true;

    // Loop over edge list
    int adj_start = g->indices[u];
    int adj_end   = g->indices[u + 1];
    for (int j = adj_start; j < adj_end; j++)
    {
      // Get edge
      int v = g->adj_nodes[j];
      double w = g->weights[j];

      // Skip?
      if (visited[v]) { continue; }

      // Improved dist?
      double new_dist = u_dist + w;
      if (new_dist < dist[v])
      {
        // Push update to heap
        dist[v] = new_dist;
        ret = push_min_heap(h, v, new_dist);
        if (ret == -1) return NULL;
      }
    }
  }
  // Cleanup
  free_min_heap(h);
  free(visited);

  return dist;
}