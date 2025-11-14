#ifndef GRAPH_CLASS_H
#define GRAPH_CLASS_H

// node structure for adjacency list
typedef struct node {
    int vertex;
    int weight;
    struct node* next;
} node;

// graph structure
typedef struct graph {
    int numVertices;
    node** adjLists;
} graph;


graph* createGraph(int n);
void addEdge(graph* g, int src, int dest, int weight);
void printgraph(graph* g);
node* createnode(int v, int w);

graph* constructGraph(int numNodes, int numEdges);
#endif 

#define MAX_WEIGHT 20