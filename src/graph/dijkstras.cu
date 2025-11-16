#include "dijkstras.cuh"
#include "data_structs/min_heap.cuh"

int *dijkstras(graph_t *g, int num_nodes, int src)
{
  min_heap_t h;
  init_min_heap(&h, num_nodes);

  bool *visited = (bool *)malloc(sizeof(bool) * num_nodes);
  int *dist = (int *)malloc(sizeof(int) * num_nodes);

  for (int i = 0; i < num_nodes; i++)
  {
    visited[i] = false;
    dist[i] = INT_MAX; // Invalid
  }
  dist[src] = 0;
  int *pred = (int *)malloc(sizeof(int) * num_nodes);

  // Push first node
  push_min_heap(&h, src, 0);

  while (!is_empty_heap(&h))
  {
    node_data_t u_node = pop_min_heap(&h);
    int u = u_node.node;
    int u_dist = u_node.dist;

    if (visited[u] || u_dist > dist[u]) { continue; }

    adj_list_t a = g->adj_lists[u];
    visited[u] = true;
    for (int i = 0; i < a.num_adj; i++)
    {
      int v = a.adj_nodes[i];
      int w = a.adj_weights[i];

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