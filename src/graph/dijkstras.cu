#include "dijkstras.cuh"
#include "data_structs/min_heap.cuh"

int *dijkstras(graph_t *g, int src)
{
  min_heap_t h;
  init_min_heap(&h, g->num_nodes);

  bool *visited = (bool *)malloc(sizeof(bool) * g->num_nodes);
  int *dist = (int *)malloc(sizeof(int) * g->num_nodes);

  for (int i = 0; i < g->num_nodes; i++)
  {
    visited[i] = false;
    dist[i] = INT_MAX; // Invalid
  }
  dist[src] = 0;
  int *pred = (int *)malloc(sizeof(int) * g->num_nodes);

  // Push first node
  push_min_heap(&h, src, 0);

  while (!is_empty_heap(&h))
  {
    node_data_t u_node = pop_min_heap(&h);
    int u = u_node.node;
    int u_dist = u_node.dist;

    if (visited[u] || u_dist > dist[u]) { continue; }

    visited[u] = true;
    for (int i = 0; i < g->max_adj; i++)
    {
      int v = g->adj_nodes[g->max_adj * u + i];
      int w = g->adj_weights[g->max_adj * u + i];

      // End early?
      if (v == -1) { break; }

      if (visited[v]) { continue; }

      int new_dist = u_dist + w;
      if (new_dist < dist[v])
      {
        dist[v] = new_dist;
        push_min_heap(&h, v, new_dist);
      }
    }
  }

  free(visited);

  return dist;
}