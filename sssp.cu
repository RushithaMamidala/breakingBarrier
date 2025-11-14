#include <stdio.h>
#include <stdlib.h>
#include "graphClass.h"
#include "minHeap.h"
#include "distanceClass.h"

int main(int argc, char **argv) {
    int numNodes = atoi(argv[1]);
    int numEdges = atoi(argv[2]);
    int source = atoi(argv[3]);
    int i=0;

    if (numEdges < numNodes-1) {
        fprintf(stderr, "Need atleast %d edges with %d nodes to construct a fully connected graph\n", numNodes-1, numNodes);
        return 1;
    }

    graph* myGraph = constructGraph(numNodes, numEdges);
    printgraph(myGraph);

    int* distDijk = dijkstraSerial(myGraph, numNodes, numEdges, source);
    
    printf("\nSource: %d\n", source);
    for(i=0;i<numNodes;++i){
        printf("Node %d Distance %d\t",i,distDijk[i]);
    }

    return 0;
}