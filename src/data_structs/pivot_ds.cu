#include "pivot_ds.cuh"
#include "util/returns.cuh"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

bool verb = 0;
/* ---------- Utility ---------- */

static int max_int(int a, int b) { return a > b ? a : b; }

/* ---------- AVL tree helpers ---------- */

static int avl_height(avl_node *n) {
    return n==NULL ? 0 : n->height;
}

static void avl_update_height(avl_node *n) {
    if (n!=NULL) n->height = 1 + max_int(avl_height(n->left), avl_height(n->right));
}

static avl_node *avl_rotate_right(avl_node *y) {
    avl_node *x = y->left;
    avl_node *T2 = x->right;
    x->right = y;
    y->left = T2;
    avl_update_height(y);
    avl_update_height(x);
    return x;
}

static avl_node *avl_rotate_left(avl_node *x) {
    avl_node *y = x->right;
    avl_node *T2 = y->left;
    y->left = x;
    x->right = T2;
    avl_update_height(x);
    avl_update_height(y);
    return y;
}

static int avl_get_balance(avl_node *n) {
    return n!=NULL ? avl_height(n->left) - avl_height(n->right) : 0;
}

/* Create a new AVL node with single block in its list */
static avl_node *avl_new_node(double key, block *b) {
    avl_node *node = (avl_node *)malloc(sizeof(avl_node));
    node->key = key;
    node->left = NULL;
    node->right = NULL;
    node->height = 1;
    block_list_node *bl = (block_list_node *)malloc(sizeof(block_list_node));
    bl->block_node = b;
    bl->next = NULL;
    node->blocks = bl;
    return node;
}

/* Insert block into node's block list */
static void avl_add_block_to_node(avl_node *node, block *b) {
    block_list_node *bl = (block_list_node *)malloc(sizeof(block_list_node));
    bl->block_node = b;
    bl->next = node->blocks;
    node->blocks = bl;
}

/* Insert (key, block) into AVL */
static avl_node *avl_insert_block(avl_node *root, double key, block *b) {
    if (root==NULL) return avl_new_node(key, b);

    if (key < root->key) {
        root->left = avl_insert_block(root->left, key, b);
    } else if (key > root->key) {
        root->right = avl_insert_block(root->right, key, b);
    } else {
        /* Same key: attach block to list */
        avl_add_block_to_node(root, b);
        return root;
    }

    avl_update_height(root);
    int balance = avl_get_balance(root);

    /* Left Left */
    if (balance > 1 && key < root->left->key)
        return avl_rotate_right(root);

    /* Right Right */
    if (balance < -1 && key > root->right->key)
        return avl_rotate_left(root);

    /* Left Right */
    if (balance > 1 && key > root->left->key) {
        root->left = avl_rotate_left(root->left);
        return avl_rotate_right(root);
    }

    /* Right Left */
    if (balance < -1 && key < root->right->key) {
        root->right = avl_rotate_right(root->right);
        return avl_rotate_left(root);
    }

    return root;
}

/* Remove a specific block from node->blocks, return 1 if list emptied */
static int avl_remove_block_from_list(avl_node *node, block *b) {
    block_list_node *prev = NULL, *cur = node->blocks;
    while (cur) {
        if (cur->block_node == b) {
            if (prev) prev->next = cur->next;
            else node->blocks = cur->next;
            free(cur);
            break;
        }
        prev = cur;
        cur = cur->next;
    }
    return node->blocks == NULL;
}

/* Free a node (assuming its children were handled) */
static void avl_free_node(avl_node *node) {
    block_list_node *bl = node->blocks;
    while (bl) {
        block_list_node *next = bl->next;
        free(bl);
        bl = next;
    }
    free(node);
}

/* Find minimum node in a subtree */
static avl_node *avl_min_node(avl_node *node) {
    avl_node *cur = node;
    while (cur!=NULL && cur->left!=NULL) cur = cur->left;
    return cur;
}

/* Delete (key, block) from AVL */
static avl_node *avl_delete_block(avl_node *root, double key, block *b) {
    if (!root) return NULL;

    if (key < root->key) {
        root->left = avl_delete_block(root->left, key, b);
    } else if (key > root->key) {
        root->right = avl_delete_block(root->right, key, b);
    } else {
        /* key == root->key; remove block from list */
        int list_empty = avl_remove_block_from_list(root, b);
        if (!list_empty) {
            /* Node stays; just updated list */
            return root;
        }

        /* No blocks left, delete this node */
        if (!root->left || !root->right) {
            avl_node *temp = root->left ? root->left : root->right;
            if (!temp) {
                /* No child */
                avl_free_node(root);
                return NULL;
            } else {
                /* One child */
                *root = *temp;   /* Copy child into root */
                free(temp);
                /* Free the blocks list that was in old root (already freed above) */
            }
        } else {
            /* Two children: get inorder successor */
            avl_node *temp = avl_min_node(root->right);
            /* Move successor's data into root */
            block_list_node *old_blocks = root->blocks;
            root->key = temp->key;
            root->blocks = temp->blocks;
            temp->blocks = old_blocks; /* so they will be freed when temp is deleted */
            /* Delete successor node (which now has old_blocks) */
            root->right = avl_delete_block(root->right, temp->key, NULL);
            /* NOTE: in this path, block is already removed from list above */
        }
    }

    if (!root) return NULL;

    avl_update_height(root);
    int balance = avl_get_balance(root);

    if (balance > 1 && avl_get_balance(root->left) >= 0)
        return avl_rotate_right(root);

    if (balance > 1 && avl_get_balance(root->left) < 0) {
        root->left = avl_rotate_left(root->left);
        return avl_rotate_right(root);
    }

    if (balance < -1 && avl_get_balance(root->right) <= 0)
        return avl_rotate_left(root);

    if (balance < -1 && avl_get_balance(root->right) > 0) {
        root->right = avl_rotate_right(root->right);
        return avl_rotate_left(root);
    }

    return root;
}

/* Lower bound search: smallest key >= x */
static avl_node *avl_lower_bound(avl_node *root, double x) {
    avl_node *res = NULL;
    while (root) {
        if (root->key >= x) {
            res = root;
            root = root->left;
        } else {
            root = root->right;
            
        }
    }
    return res;
}

/* Free entire AVL tree (without freeing blocks) */
static void avl_free_tree(avl_node *root) {
    if (!root) return;
    avl_free_tree(root->left);
    avl_free_tree(root->right);
    avl_free_node(root);
}

/* ---------- block helpers ---------- */

static block *block_create(int M, int in_D1) {
    block *b = (block *)malloc(sizeof(block));
    b->next = b->prev = NULL;
    b->size = 0;
    b->capacity = M;   /* initial capacity; can grow if needed */
    b->items = (data_pair *)malloc(sizeof(data_pair) * b->capacity);
    b->min_val = __DBL_MIN__;
    b->max_val = 100000000;
    b->upper  = 100000000;
    b->in_D1  = in_D1;
    return b;
}

static void block_free(block *b) {
    if (!b) return;
    free(b->items);
    free(b);
}

/* Comparator for sorting pairs by value */
static int compare_dpair_val(const void *a, const void *b) {
    const data_pair *pa = (const data_pair *)a;
    const data_pair *pb = (const data_pair *)b;
    if (pa->val < pb->val) return -1;
    if (pa->val > pb->val) return 1;
    return 0;
}

/* ---------- DS Creation / Destruction ---------- */

pivot_ds *pivotds_create(int M, double B, int max_key) {
    if (verb) printf("Creating the special DS with M=%d\n",M);
    if (M <= 0 || max_key <= 0) return NULL;
    pivot_ds *ds = (pivot_ds *)malloc(sizeof(pivot_ds));
    ds->M = M;
    ds->bound = B;
    ds->max_key = max_key;

    ds->D0_head = NULL;
    ds->D1_head = NULL;
    ds->tree_root = NULL;

    ds->key_block = (block **)calloc(max_key, sizeof(block *));
    ds->key_index = (int *)malloc(sizeof(int) * max_key);
    ds->key_dist   = (double *)malloc(sizeof(double) * max_key);
    // printf("Allocated\n");
    for (int i = 0; i < max_key; ++i) {
        ds->key_block[i] = NULL;
        ds->key_index[i] = -1;
        ds->key_dist[i]   = 100000000;
    }

    /* Initialize D1 with a single empty block with upper bound B */
    block *b = block_create(M, 1);
    b->upper = B;
    b->min_val = __DBL_MIN__;
    b->max_val = 100000000;
    ds->D1_head = b;

    ds->tree_root = avl_insert_block(ds->tree_root, b->upper, b);
    if (verb) printf("Creation complete\n");
    return ds;
}

void pivotds_destroy(pivot_ds *ds) {
    if (!ds) return;

    /* Free D0 blocks */
    block *b = ds->D0_head;
    while (b) {
        block *next = b->next;
        block_free(b);
        b = next;
    }

    /* Free D1 blocks */
    b = ds->D1_head;
    while (b) {
        block *next = b->next;
        block_free(b);
        b = next;
    }

    /* Free tree (without blocks) */
    avl_free_tree(ds->tree_root);

    free(ds->key_block);
    free(ds->key_index);
    free(ds->key_dist);
    free(ds);
}

/* ---------- Deletion of a single key ---------- */

static void ds_delete_key(pivot_ds *ds, int key) {
    if (key < 0 || key >= ds->max_key) return;
    block *b = ds->key_block[key];
    if (!b) return;

    int idx = ds->key_index[key];
    int last = b->size - 1;

    /* Swap with last, update moved key's meta */
    if (idx != last) {
        b->items[idx] = b->items[last];
        int moved_key = b->items[idx].key;
        ds->key_index[moved_key] = idx;
        ds->key_dist[moved_key]   = b->items[idx].val;
        ds->key_block[moved_key] = b;
    }
    b->size--;

    /* Clear metadata for removed key */
    ds->key_block[key] = NULL;
    ds->key_index[key] = -1;
    ds->key_dist[key]   = 100000000;

    if (b->size == 0) {
        ds_remove_block(ds, b);
    } else {
        /* Recompute min, max (size ≤ M) */
        double mn = b->items[0].val;
        double mx = b->items[0].val;
        for (int i = 1; i < b->size; ++i) {
            if (b->items[i].val < mn) mn = b->items[i].val;
            if (b->items[i].val > mx) mx = b->items[i].val;
        }
        double old_upper = b->upper;
        b->min_val = mn;
        b->max_val = mx;
        b->upper   = mx;

        if (b->in_D1 && old_upper != b->upper) {
            ds->tree_root = avl_delete_block(ds->tree_root, old_upper, b);
            ds->tree_root = avl_insert_block(ds->tree_root, b->upper, b);
        }
    }
}

/* ---------- Remove entire block from DS ---------- */

static void ds_remove_block(pivot_ds *ds, block *b) {
    if (!b) return;

    /* Detach from linked list */
    block **head_ptr = b->in_D1 ? &ds->D1_head : &ds->D0_head;

    if (b->prev) {
        b->prev->next = b->next;
    } else {
        *head_ptr = b->next;
    }
    if (b->next) {
        b->next->prev = b->prev;
    }

    if (b->in_D1) {
        /* Remove from AVL */
        ds->tree_root = avl_delete_block(ds->tree_root, b->upper, b);

        /* If D1 becomes empty, create a fresh empty block with upper B */
        if (ds->D1_head == NULL) {
            block *b = block_create(ds->M, 1);
            b->upper = ds->bound;
            b->min_val = __DBL_MIN__;
            b->max_val = 100000000;
            ds->D1_head = b;
            ds->tree_root = avl_insert_block(ds->tree_root, b->upper, b);
        }
    }

    block_free(b);
}

/* ---------- Split a D1 block when size > M ---------- */

static void ds_split_block(pivot_ds *ds, block *b) {
    if (!b || !b->in_D1) return;
    if (b->size <= ds->M) return;

    int n = b->size;
    double old_upper = b->upper;

    /* Sort items by value (n ≤ M+something, very small) */
    qsort(b->items, n, sizeof(data_pair), compare_dpair_val);

    int n1 = n / 2;
    int n2 = n - n1;

    block *b2 = block_create(ds->M, 1);

    if (b2->capacity < n2) {
        b2->capacity = n2;
        b2->items = (data_pair *)realloc(b2->items, sizeof(data_pair) * b2->capacity);
    }

    /* Move upper half to new block */
    memcpy(b2->items, b->items + n1, sizeof(data_pair) * n2);
    b2->size = n2;

    b->size = n1;

    /* Update per-key metadata */
    for (int i = 0; i < n1; ++i) {
        int k = b->items[i].key;
        ds->key_block[k] = b;
        ds->key_index[k] = i;
        ds->key_dist[k]   = b->items[i].val;
    }
    for (int i = 0; i < n2; ++i) {
        int k = b2->items[i].key;
        ds->key_block[k] = b2;
        ds->key_index[k] = i;
        ds->key_dist[k]   = b2->items[i].val;
    }

    /* Recompute block stats */
    b->min_val = b->items[0].val;
    b->max_val = b->items[n1 - 1].val;
    b->upper   = b->max_val;

    b2->min_val = b2->items[0].val;
    b2->max_val = b2->items[n2 - 1].val;
    b2->upper   = b2->max_val;

    /* Insert b2 after block in D1 list */
    b2->next = b->next;
    b2->prev = b;
    if (b->next) b->next->prev = b2;
    b->next = b2;

    /* Update AVL: remove old mapping for block, insert new ones */
    ds->tree_root = avl_delete_block(ds->tree_root, old_upper, b);
    ds->tree_root = avl_insert_block(ds->tree_root, b->upper, b);
    ds->tree_root = avl_insert_block(ds->tree_root, b2->upper, b2);
}

/* ---------- Insert(a, b) ---------- */

static avl_node* avl_max_node(avl_node *root) {
    if (!root) return NULL;
    while (root->right) root = root->right;
    return root;
}

void pivotds_insert(pivot_ds *ds, int key, double val) {
    // printf("Inserting\n");
    if (!ds) return;
    if (key < 0 || key >= ds->max_key) return;

    /* Check existing key */
    block *blk = ds->key_block[key];
    if (blk) {
        double old = ds->key_dist[key];
        if (val >= old) {
            /* Not better, ignore */
            return;
        }
        /* Better value: delete old pair first */
        ds_delete_key(ds, key);
    }

    /* Find appropriate D1 block via upper-bound tree */
    block *target = NULL;
    if (ds->tree_root) {
        avl_node *node = avl_lower_bound(ds->tree_root, val);
        if (!node) node = avl_max_node(ds->tree_root);
        if (node && node->blocks) target = node->blocks->block_node;
    }
    if (!target) {
        printf("Target not found\n");
        /* Fallback: should not normally happen, but be safe */
        target = ds->D1_head;
    }

    /* Ensure capacity */
    if (target->size >= target->capacity) {
        target->capacity *= 2;
        target->items = (data_pair *)realloc(target->items, sizeof(data_pair) * target->capacity);
    }

    int idx = target->size;
    target->items[idx].key = key;
    target->items[idx].val = val;
    target->size++;

    /* Update block stats */
    if (val < target->min_val) target->min_val = val;
    if (val > target->max_val) {
        /* In principle val <= old upper from lower_bound, so this won't increase upper.
           But we keep upper = max_val for robustness. */
        double old_upper = target->upper;
        target->max_val = val;
        target->upper   = target->max_val;
        if (target->upper != old_upper) {
            ds->tree_root = avl_delete_block(ds->tree_root, old_upper, target);
            ds->tree_root = avl_insert_block(ds->tree_root, target->upper, target);
        }
    }

    /* Update per-key metadata */
    ds->key_block[key] = target;
    ds->key_index[key] = idx;
    ds->key_dist[key]   = val;

    /* Split if necessary */
    if (target->size > ds->M) {
        ds_split_block(ds, target);
    }
}

/* ---------- BatchPrepend(L) ---------- */

/* Local hash map for dedup keys in L */
typedef struct {
    int    key;
    double val;
    char   used;
} LocalMapEntry;

static int next_pow2(int n) {
    int p = 1;
    while (p < n) p <<= 1;
    return p;
}

void pivotds_batch_prepend(pivot_ds *ds, const data_pair *pairs, int L) {
    if (!ds || !pairs || L <= 0) return;

    /* 1) Deduplicate keys within L using local hash map (key -> min value in L) */
    int table_size = next_pow2(L * 2);
    LocalMapEntry *table = (LocalMapEntry *)calloc(table_size, sizeof(LocalMapEntry));
    int mask = table_size - 1;

    for (int i = 0; i < L; ++i) {
        int k = pairs[i].key;
        double v = pairs[i].val;
        int idx = (unsigned)k & (unsigned)mask;
        while (table[idx].used && table[idx].key != k) {
            idx = (idx + 1) & mask;
        }
        if (!table[idx].used) {
            table[idx].used = 1;
            table[idx].key = k;
            table[idx].val = v;
        } else {
            if (v < table[idx].val) {
                table[idx].val = v;
            }
        }
    }

    /* 2) Compare with existing DS, keep only strictly better values and delete old ones */
    data_pair *filtered = (data_pair *)malloc(sizeof(data_pair) * L);
    int fcount = 0;

    for (int i = 0; i < table_size; ++i) {
        if (!table[i].used) continue;
        int k = table[i].key;
        if (k < 0 || k >= ds->max_key) continue;
        double newv = table[i].val;
        block *blk = ds->key_block[k];
        double old = ds->key_dist[k];
        if (blk && old <= newv) {
            /* Existing value is smaller or equal -> ignore new one */
            continue;
        }
        if (blk) {
            /* Replace with strictly smaller */
            ds_delete_key(ds, k);
        }
        filtered[fcount].key = k;
        filtered[fcount].val = newv;
        fcount++;
    }

    free(table);

    if (fcount == 0) {
        free(filtered);
        return;
    }

    /* 3) Sort filtered ascending by value */
    qsort(filtered, fcount, sizeof(data_pair), compare_dpair_val);

    /* 4) Build blocks in D0 from filtered, with correct block value ordering.
       We process from the end backwards so that final D0 list is increasing by value. */

    int idx = fcount;
    while (idx > 0) {
        int block_size = ds->M;
        if (block_size > idx) block_size = idx;
        idx -= block_size;

        block *b = block_create(ds->M, 0);  /* in_D1 = 0 */
        if (b->capacity < block_size) {
            b->capacity = block_size;
            b->items = (data_pair *)realloc(b->items, sizeof(data_pair) * b->capacity);
        }

        /* Copy chunk filtered[idx .. idx+block_size-1] */
        for (int j = 0; j < block_size; ++j) {
            data_pair p = filtered[idx + j];
            b->items[j] = p;
            /* Update per-key metadata */
            int k = p.key;
            ds->key_block[k] = b;
            ds->key_index[k] = j;
            ds->key_dist[k]   = p.val;
            // printf("added %d %f\t",p.val,ds->key_dist[k]);
        }
        b->size = block_size;
        b->min_val = filtered[idx].val;
        b->max_val = filtered[idx + block_size - 1].val;
        b->upper   = b->max_val;  /* not used in D0, but keep consistent */

        /* Prepend to D0 list */
        b->prev = NULL;
        b->next = ds->D0_head;
        if (ds->D0_head) ds->D0_head->prev = b;
        ds->D0_head = b;
    }

    free(filtered);
}

/* ---------- Pull() ---------- */

typedef struct {
    int    key;
    double val;
} Candidate;

static int compare_candidate_val(const void *a, const void *b) {
    const Candidate *pa = (const Candidate *)a;
    const Candidate *pb = (const Candidate *)b;
    if (pa->val < pb->val) return -1;
    if (pa->val > pb->val) return 1;
    return 0;
}

bool is_empty_pivotds(pivot_ds* ds){
    if (verb) printf("Checking special ds is empty\n");
    if (ds==NULL) return 1;
    // printf("a\n");
    if (ds->D0_head==NULL && ds->D1_head == NULL) return 1;
    // printf("b\n");
    if (ds->D0_head==NULL){
        return (ds->D1_head->size == 0);
    }
    // printf("c\n");
    if (ds->D1_head==NULL){
        return (ds->D0_head->size == 0);
    }
    return 0;
}

bmssp_returns* pivotds_pull(pivot_ds *ds) {
    if (verb) printf("Pulling elements from the special data structure, current bound is %.2f\n", ds->bound);
    if (!ds) return 0;
    bmssp_returns* pull_nodes = (bmssp_returns*)malloc(sizeof(bmssp_returns));
    pull_nodes->U = (node_set*)malloc(sizeof(node_set));
    init_node_set(pull_nodes->U, ds->max_key);

    int M = ds->M;

    /* 1) Collect prefix blocks from D0 and D1, up to M elements each */
    Candidate *cand = (Candidate *)malloc(sizeof(Candidate) * (2 * M));
    int cand_count = 0;

    block *b0 = ds->D0_head;
    block *first_after_D0 = NULL;
    int count0 = 0;

    while (b0 && count0 < M) {
        /* All elements in b0 are part of S'_0 */
        // printf("/* All elements in b0 are part of S'_0 */\n");
        for (int i = 0; i < b0->size && cand_count < 2 * M; ++i) {
            cand[cand_count].key = b0->items[i].key;
            cand[cand_count].val = b0->items[i].val;
            // printf("k: %d v: %.2f\n",cand[cand_count].key, cand[cand_count].val);
            cand_count++;
        }
        count0 += b0->size;
        if (count0 >= M) {
            first_after_D0 = b0->next;
            break;
        }
        b0 = b0->next;
    }
    if (!first_after_D0 && b0) {
        first_after_D0 = b0->next;
    }

    block *b1 = ds->D1_head;
    block *first_after_D1 = NULL;
    int count1 = 0;

    while (b1 && count1 < M) {
        for (int i = 0; i < b1->size && cand_count < 2 * M; ++i) {
            cand[cand_count].key = b1->items[i].key;
            cand[cand_count].val = b1->items[i].val;
            cand_count++;
        }
        count1 += b1->size;
        if (count1 >= M) {
            first_after_D1 = b1->next;
            break;
        }
        b1 = b1->next;
    }
    // printf("count1: %d count0 %d\n", count0,count1);
    if (!first_after_D1 && b1) {
        // printf("first_after_D1: %d\n",first_after_D1);
        first_after_D1 = b1->next;
    }

    if (cand_count == 0) {
        /* No elements in DS */
        // printf("/* No elements in DS */\n");
        pull_nodes->bound = ds->bound;
        free(cand);
        return pull_nodes;
    }

    /* 2) Decide if we are returning all elements or only M smallest */
    /* To know if we have all elements, we need to check whether any blocks remain
       outside the prefixes. If not, S'_0 ∪ S'_1 is entire DS. */

    int all_D0_covered = 1;
    block *b = ds->D0_head;
    int collected = 0;
    while (b && collected < count0) {
        collected += b->size;
        b = b->next;
    }
    if (b != NULL) all_D0_covered = 0;
    // printf("all_D0_covered %d\n",all_D0_covered);
    int all_D1_covered = 1;
    b = ds->D1_head;
    collected = 0;
    while (b && collected < count1) {
        collected += b->size;
        b = b->next;
    }
    if (b != NULL) all_D1_covered = 0;
    // printf("all_D1_covered %d\n",all_D1_covered);

    int total_is_all = all_D0_covered && all_D1_covered;

    /* Case A: total elements ≤ M => return all, x = B */
    if (total_is_all && cand_count <= M) {
        int k = cand_count;
        for (int i = 0; i < k; ++i) {
            node_set_add(pull_nodes->U, cand[i].key);
            // out_pairs[i].key = cand[i].key;
            // out_pairs[i].val = cand[i].val;
            ds_delete_key(ds, cand[i].key);
        }
        
        pull_nodes->bound = ds->bound;
        if (verb) printf("<=M elements in the block, so returning entire block, new bound = %.2f\n",pull_nodes->bound);
        free(cand);
        return pull_nodes;
    }

    /* Case B: need to choose M smallest from cand[0 .. cand_count-1] */
    qsort(cand, cand_count, sizeof(Candidate), compare_candidate_val);

    int out_count = (cand_count < M) ? cand_count : M;
    if (out_count <= 0) {
        pull_nodes->bound  = ds->bound; // needs change
        free(cand);
        return pull_nodes;
    }

    double max_in_S = cand[out_count - 1].val;
    if (verb) printf("Max in S: %.2f\n", max_in_S);

    /* Remove those M keys from DS and output them */
    for (int i = 0; i < out_count; ++i) {
        node_set_add(pull_nodes->U, cand[i].key);
        // out_pairs[i].key = cand[i].key;
        // out_pairs[i].val = cand[i].val;
        ds_delete_key(ds, cand[i].key);
    }

    /* Compute x: smallest remaining value in DS.
       It must satisfy max(S') < x ≤ min(D_remaining).
       Remaining candidates are cand[out_count .. cand_count-1], all from prefixes.
       Plus blocks after the prefixes: first_after_D0 and first_after_D1. */

    double x = ds->bound;
    if (verb) printf("Getting the bound in DS %d %d\n",out_count,cand_count);
    for (int i = out_count; i < cand_count; ++i) {
        // printf("%d", cand[i].val >= max_in_S && cand[i].val < x);
        if (cand[i].val >= max_in_S && cand[i].val < x) {
            x = cand[i].val;
        }
    }
    if (verb) printf("Max in S: %.2f\n", x);

    if (first_after_D0 && first_after_D0->size > 0 && first_after_D0->min_val >= max_in_S) {
        if (first_after_D0->min_val < x) x = first_after_D0->min_val;
    }
    while(first_after_D1){
        if (verb) printf("|%.2f|", first_after_D1->min_val);
        if (first_after_D1 && first_after_D1->size > 0 && first_after_D1->min_val >= max_in_S) {
            // printf("%d|",first_after_D1->min_val);
            if (first_after_D1->min_val < x) x = first_after_D1->min_val;
            if (verb) printf("x: %.2f", x);
        }
        first_after_D1 = first_after_D1->next;
    }
    if (verb) printf("Updated x: %.2f", x);

    /* If nothing remains, x = B */
    if (x == ds->bound) {
        pull_nodes->bound = ds->bound;
    } else {
        pull_nodes->bound = x;
    }

    free(cand);
    return pull_nodes;
}

static void print_block(block *b, const char *label) {
    printf("%s (size=%d, min=%.2f, max=%.2f, upper=%.2f, in_D1=%d)\n",
        label, b->size,
        b->min_val,
        b->max_val,
        b->upper,
        b->in_D1);

    printf("   items: ");
    for (int i = 0; i < b->size; ++i) {
        printf("(%d,%.2f) ",
               b->items[i].key,
               b->items[i].val);
    }
    printf("\n");
}

static void print_block_list(block *head, const char *name) {
    printf("\n===== %s BLOCK LIST =====\n", name);
    int idx = 0;
    block *b = head;
    while (b) {
        char label[64];
        snprintf(label, sizeof(label), "%s[%d]", name, idx);
        print_block(b, label);
        b = b->next;
        idx++;
    }
    if (idx == 0) printf("(empty)\n");
}

/* Recursive AVL printer */
static void print_avl(avl_node *root, int depth) {
    if (!root) return;

    print_avl(root->right, depth + 1);

    for (int i = 0; i < depth; ++i) printf("        ");
    printf("-> [upper=%.2f]  blocks: ",
           root->key);

    block_list_node *bl = root->blocks;
    while (bl) {
        printf("%p ", (void*)bl->block_node);
        bl = bl->next;
    }
    printf("\n");

    print_avl(root->left, depth + 1);
}

static void print_tree(pivot_ds *ds) {
    printf("\n===== AVL TREE (D1 upper bounds) =====\n");
    if (!ds->tree_root) {
        printf("(empty)\n");
        return;
    }
    print_avl(ds->tree_root, 0);
}

/* Optional: key metadata printer */
static void print_key_metadata(pivot_ds *ds) {
    printf("\n===== PER-KEY METADATA =====\n");
    for (int k = 0; k < ds->max_key; ++k) {
        if (ds->key_block[k]) {
            printf("key=%d → val=%.2f  block=%p  idx=%d\n",
                   k,
                   ds->key_dist[k],
                   (void*)ds->key_block[k],
                   ds->key_index[k]);
        }
    }
}

/* PUBLIC DEBUG FUNCTION */
void pivotds_print(pivot_ds *ds, int show_keys) {
    if (!ds) return;

    printf("\n=====================================================\n");
    printf("               SNAPSHOT OF Pivot_ds (D)\n");
    printf("=====================================================\n");
    printf("M=%d   B=%.2f   max_key=%d\n",
           ds->M, ds->bound, ds->max_key);

    print_block_list(ds->D0_head, "D0");
    print_block_list(ds->D1_head, "D1");
    print_tree(ds);

    if (show_keys)
        print_key_metadata(ds);

    printf("=====================================================\n\n");
}
