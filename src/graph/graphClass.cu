#include <stdio.h>
#include <stdlib.h>
#include "graphClass.h"

// Create a new node
node* createnode(int v, int w) {
    node* newnode = (node*) malloc(sizeof(node));
    newnode->vertex = v;
    newnode->weight = w;
    newnode->next = NULL;
    return newnode;
}

// Create a graph
graph* createGraph(int vertices) {
    graph* myGraph = (graph*)malloc(sizeof(graph));
    myGraph->numVertices = vertices;

    myGraph->adjLists = (node**)malloc(vertices * sizeof(node*));
    for (int i = 0; i < vertices; i++)
        myGraph->adjLists[i] = NULL;

    return myGraph;
}

// Add edge (undirected)
void addEdge(graph* myGraph, int src, int dest, int weight) {
    node* newnode = createnode(dest, weight);
    newnode->next = myGraph->adjLists[src];
    myGraph->adjLists[src] = newnode;

}

// Print the graph
void printgraph(graph* myGraph) {
    printf("\nThe final graph is\n");
    for (int i = 0; i < myGraph->numVertices; i++) {
        node* temp = myGraph->adjLists[i];
        printf("Vertex %d:", i);
        while (temp) {
            printf(" -> %d (w=%d)", temp->vertex, temp->weight);
            temp = temp->next;
        }
        printf(" -> NULL\n");
    }
}

graph* constructGraph(int numNodes, int numEdges){
    printf("\nConstructing graph with %d nodes and %d edges", numNodes, numEdges);
    int src, weight, dest;

    // to avoid duplicate edges
    bool **hasEdge = (bool**) malloc(numNodes * sizeof(bool*));
    for (int i = 0; i < numNodes; i++) {
        hasEdge[i] = (bool*) calloc(numNodes, sizeof(bool));
    }


    graph* myGraph = createGraph(numNodes);
    // to ensure a fully connected graph
    for(dest=1; dest<numNodes;dest++){
        src = rand() % dest;
        weight = (rand() % MAX_WEIGHT)+1;
        addEdge(myGraph, src, dest, weight);
        hasEdge[src][dest] = true;
    }
    int left = numEdges - (numNodes - 1);

    while (left>0){
        dest = rand() % numNodes;
        src = rand() % numNodes;
        if (dest == src) continue;
        if (hasEdge[src][dest]) continue;
        weight = (rand() % MAX_WEIGHT) +1;
        addEdge(myGraph, src, dest, weight);
        --left;
    }
    free(hasEdge);
    return myGraph;
}
