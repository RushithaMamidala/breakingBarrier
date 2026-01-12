#ifndef SHORTEST_PATH_H
#define SHORTEST_PATH_H

#pragma once

typedef struct {
    graph *G;
    int k;
    int t;
    Length *dhat; // length N
    Vertex *prev; // length N
    Vertex *tree_size;
    VecVertex *F; // array size N of children vectors
    int N;
} ShortestPath;

void sp_init(ShortestPath *sp, Graph *G);
void sp_free(ShortestPath *sp);
Length* sp_get(ShortestPath *sp, Vertex s); // returns pointer to dhat array (owned by sp)

#endif // SHORTEST_PATH_H
