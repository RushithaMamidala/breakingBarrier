#include "dijkstras.cuh"
#include "data_structs/min_heap.cuh"

int *dijkstras(graph_t *g, int src)
{
  // Min heap to store nodes and dist.
  // Note: We keep duplicates, so we need at most #edges size.
  min_heap_t h;
  init_min_heap(&h, g->num_nodes * g->max_adj);

  // Visited nodes and their distances
  bool *visited = (bool *)malloc(sizeof(bool) * g->num_nodes);
  int *dist = (int *)malloc(sizeof(int) * g->num_nodes);
  for (int i = 0; i < g->num_nodes; i++)
  {
    visited[i] = false;
    dist[i] = INT_MAX; // Invalid
  }
  dist[src] = 0;

  // Push first node to seed Dijkstra's
  push_min_heap(&h, src, 0);

  while (!is_empty_heap(&h))
  {
    // Pop node and dist
    node_data_t u_node = pop_min_heap(&h);
    int u = u_node.node;
    int u_dist = u_node.dist;

    // Skip?
    if (visited[u] || u_dist > dist[u]) { continue; }

    visited[u] = true;

    // Loop over edge list
    for (int i = 0; i < g->max_adj; i++)
    {
      // Get edge
      int v = g->adj_nodes[g->max_adj * u + i];
      int w = g->adj_weights[g->max_adj * u + i];

      // List ends early?
      if (v == -1) { break; }

      // Skip?
      if (visited[v]) { continue; }

      // Improved dist?
      int new_dist = u_dist + w;
      if (new_dist < dist[v])
      {
        // Push update to heap
        dist[v] = new_dist;
        push_min_heap(&h, v, new_dist);
      }
    }
  }
  // Cleanup
  deinit_min_heap(&h);
  free(visited);

  return dist;
}