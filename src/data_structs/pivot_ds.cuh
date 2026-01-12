#pragma once
#include "util/returns.cuh"

typedef struct {
    int key;
    double val;
} data_pair;

typedef struct block{
    struct block *next;
    struct block *prev;
    data_pair       *items;
    int          size;
    int          capacity;
    double min_val;
    double max_val;
    double upper;      /* used as key in tree for D1 */
    int in_D1;      /* 1 if in D1, 0 if in D0 */
} block;

/* AVL tree node to index D1 blocks by upper bound */
typedef struct block_list_node{
    block *block_node;
    struct block_list_node *next;
} block_list_node;

typedef struct avl_node{
    double              key;     /* upper bound */
    block_list_node      *blocks;  /* list of blocks with this upper */
    struct avl_node     *left;
    struct avl_node     *right;
    int                 height;
} avl_node;

/* Main DS structure */
typedef struct pivot_ds{
    int      M;
    double   bound;
    int      max_key;

    /* Two sequences of blocks */
    block   *D0_head;  /* batch-prepend blocks */
    block   *D1_head;  /* insert blocks */

    /* Balanced tree over D1 block uppers */
    avl_node *tree_root;

    /* Per-key metadata: ensures unique smallest pair per key */
    block   **key_block;  /* key -> block pointer (or NULL) */
    int     *key_index;   /* key -> index inside block->items */
    double  *key_dist;     /* key -> value (for convenience) */
}pivot_ds;

/* Public API */

/* ---------- Core DS Helpers ---------- */

static void ds_remove_block(pivot_ds *ds, block *block);   /* forward */
static void ds_delete_key(pivot_ds *ds, int key);
static void ds_split_block(pivot_ds *ds, block *block);

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