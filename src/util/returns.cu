#include "data_structs/graph.cuh"
#include "returns.cuh"
#include <stdio.h>
#include <stdlib.h>

void init_node_set(node_set *n, int capacity){
    n->count = 0;
    n->capacity = capacity;
    n->nodes = (int*)malloc(sizeof(int)*n->capacity);
    n->in_set = (char*)calloc(n->capacity, sizeof(char));
}

void extend_node_set(node_set* n){
    n->capacity += 16;
    n->nodes = (int*)realloc(n->nodes, n->capacity * sizeof(int));
    n->in_set = (char*)realloc(n->nodes, n->capacity * sizeof(char));
}

void copy_node_set(node_set* source_set, node_set* destination_set){
    if (destination_set->count!=0) destination_set->count=0;
    int count = source_set->count;
    while (destination_set->capacity < count) extend_node_set(destination_set);
    for( int i=0; i < count; i++){
        destination_set->nodes[i] = source_set->nodes[i];
        destination_set->in_set[destination_set->nodes[i]] = 1;
    }
    destination_set->count = count;
}

void free_node_set(node_set* n){
    n->count = 0;
    free(n->nodes);
    free(n->in_set);
}

void print_node_set(node_set* n){
    for(int i=0; i<n->count;i++){
        printf("%d\t",n->nodes[i]);
    } 
    printf("\n");
}


void append_node_set(node_set* main_set, node_set* append_set){
    for( int i=0; i < append_set->count; i++){
        int node = append_set->nodes[i];
        if(main_set->in_set[node]) continue;
        main_set->nodes[main_set->count++] = node;
        main_set->in_set[node] = 1;
    }
    // main_set->count += count;
}


void node_set_add(node_set* n, int v) {
    if (n->in_set[v]) return;
    while (n->count == n->capacity) extend_node_set(n);
    n->nodes[n->count++] = v;
    n->in_set[v] = 1;
}