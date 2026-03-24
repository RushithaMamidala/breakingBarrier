#pragma once
#include "util/returns.cuh"

typedef struct {
    int key;
    double val;
} data_pair;

typedef struct block{
    int next, prev;
    data_pair *items;
    int size;
    int capacity;
    double min_val;
    double max_val;
    double upper;      /* used as key in tree for D1 */
    int in_D1;      /* 1 if in D1, 0 if in D0 */
    int alive;
} block;

/* AVL tree node to index D1 blocks by upper bound */
typedef struct block_list_node{
    int block_idx;
    int next; 
    int alive;
} block_list_node;

typedef struct avl_node{
    double key;     /* upper bound */
    int blocks_head;  /* list of blocks with this upper */
    int left, right;
    int height;
    int alive;
} avl_node;

/* Main DS structure */
typedef struct pivot_ds{
    int      M;
    double   bound;
    int      max_key;

    int   D1_head;  /* insert blocks */

    /* AVL index over D1 block uppers */
    int tree_root;

    /* Block arena */
    block   *blocks;  /* block arena: blocks[idx] is a block */
    int blocks_used, blocks_cap;
    int free_block_head;

    /* AVL node arena */
    avl_node *avl_nodes;
    int avl_used, avl_cap;
    int free_avl_head;

    /* Per-AVL-node list of blocks sharing same upper */
    block_list_node *bl_nodes;
    int bl_used, bl_cap;
    int free_bl_head;

    int *key_block;          /* key -> block index, -1 if absent */
    int *key_index;       /* key -> slot inside block->items */
    double *key_dist;     /* key -> current best distance */
}pivot_ds;

/* Public API */

/* ---------- Core DS Helpers ---------- */
static void mom_select(data_pair *a, int lo, int hi, int nth);
static void ds_remove_block(pivot_ds *ds, block *block);   /* forward */
static void ds_delete_key(pivot_ds *ds, int key);
static block* ds_split_block(pivot_ds *ds, block *block);

pivot_ds *pivotds_create(int M, double bound, int max_key);
void     pivotds_destroy(pivot_ds *ds);

void     pivotds_insert(pivot_ds *ds, int key, double val);
void     pivotds_batch_prepend(pivot_ds *ds, const data_pair *pairs, int L);
bool is_empty_pivotds(pivot_ds* ds);

/* Returns number of elements in S' (≤ M). out_pairs must have space for at least M.
 * x_out is set to B if structure becomes empty, otherwise the separating x as in Lemma 3.3.
 */
bmssp_returns* pivotds_pull(pivot_ds *ds);


void pivotds_print(pivot_ds *ds, int show_keys);
static void print_key_metadata(pivot_ds *ds);
static void print_tree(pivot_ds *ds);
static void print_avl(avl_node *root, int depth);
static void print_block_list(block *head, const char *name);
static void print_block(block *b, const char *label);
