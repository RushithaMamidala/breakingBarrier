#include "distanceClass.h"
#include "minHeap.h"

int* dijkstraSerial(graph* g, int numNodes, int numEdges, int source){
    int u, v, u_dist;
    minHeap* heap = createMinHeap(numNodes);
    bool* visited = (bool*)malloc(sizeof(bool)*numNodes);
    int* dist = (int*)malloc(sizeof(int)*numNodes);
    for (int i=0;i<numNodes;i++){
        visited[i] = false;
        dist[i] = MAX_WEIGHT + 1;
    }
    dist[source] = 0;
    int* pred = (int*)malloc(sizeof(int)*numNodes);

    pushHeap(heap, source, 0);

    while(!isEmptyHeap(heap)){
        heapNode u_node = popHeap(heap);
        u = u_node.vertex;
        u_dist = u_node.dist;
        if (visited[u] || u_dist > dist[u]) continue;
        visited[u] = true;
        for (node* nbr = g->adjLists[u]; nbr!=NULL; nbr = nbr->next) {
            v = nbr->vertex;
            if (visited[v]) continue;
            int newDist = u_dist + nbr->weight;
            if (newDist < dist[v]) {
                dist[v] = newDist;
                pushHeap(heap, v, newDist);
            }
        }
    }
    return dist;
}