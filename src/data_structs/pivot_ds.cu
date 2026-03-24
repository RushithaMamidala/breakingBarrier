#include "pivot_ds.cuh"
#include "util/returns.cuh"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

bool verb = 0;
#define NIL (-1)
#define INF 1000000000.0
#define DBL_MAX 100000000.0

/* ---------- Utility ---------- */

static int max_int(int a, int b) { return a > b ? a : b; }

/* ---------- Arena helpers ---------- */

static void ensure_block_cap(pivot_ds *ds) {
    if (ds->blocks_used < ds->blocks_cap) return;
    int new_cap = ds->blocks_cap ? ds->blocks_cap * 2 : 16;
    ds->blocks = (block *)realloc(ds->blocks, new_cap * sizeof(block));
    ds->blocks_cap = new_cap;
}

static void ensure_avl_cap(pivot_ds *ds) {
    if (ds->avl_used < ds->avl_cap) return;
    int new_cap = ds->avl_cap ? ds->avl_cap * 2 : 16;
    ds->avl_nodes = (avl_node *)realloc(ds->avl_nodes, new_cap * sizeof(avl_node));
    ds->avl_cap = new_cap;
}

static void ensure_bl_cap(pivot_ds *ds) {
    if (ds->bl_used < ds->bl_cap) return;
    int new_cap = ds->bl_cap ? ds->bl_cap * 2 : 32;
    ds->bl_nodes = (block_list_node *)realloc(ds->bl_nodes, new_cap * sizeof(block_list_node));
    ds->bl_cap = new_cap;
}

static int alloc_block_slot(pivot_ds *ds) {
    if (ds->free_block_head != NIL) {
        int idx = ds->free_block_head;
        ds->free_block_head = ds->blocks[idx].next;
        ds->blocks[idx].alive = 1;
        ds->blocks[idx].next = ds->blocks[idx].prev = NIL;
        ds->blocks[idx].size = 0;
        return idx;
    }
    ensure_block_cap(ds);
    int idx = ds->blocks_used++;
    memset(&ds->blocks[idx], 0, sizeof(block));
    ds->blocks[idx].next = ds->blocks[idx].prev = NIL;
    ds->blocks[idx].alive = 1;
    return idx;
}

static void free_block_slot(pivot_ds *ds, int idx) {
    if (idx == NIL) return;
    ds->blocks[idx].alive = 0;
    free(ds->blocks[idx].items);
    ds->blocks[idx].items = NULL;
    ds->blocks[idx].next = ds->free_block_head;
    ds->free_block_head = idx;
}

static int alloc_avl_slot(pivot_ds *ds) {
    if (ds->free_avl_head != NIL) {
        int idx = ds->free_avl_head;
        ds->free_avl_head = ds->avl_nodes[idx].left; /* freelist link stored in left */
        ds->avl_nodes[idx].alive = 1;
        ds->avl_nodes[idx].left = ds->avl_nodes[idx].right = NIL;
        ds->avl_nodes[idx].blocks_head = NIL;
        ds->avl_nodes[idx].height = 1;
        return idx;
    }
    ensure_avl_cap(ds);
    int idx = ds->avl_used++;
    memset(&ds->avl_nodes[idx], 0, sizeof(avl_node));
    ds->avl_nodes[idx].left = ds->avl_nodes[idx].right = NIL;
    ds->avl_nodes[idx].blocks_head = NIL;
    ds->avl_nodes[idx].height = 1;
    ds->avl_nodes[idx].alive = 1;
    return idx;
}

static void free_avl_slot(pivot_ds *ds, int idx) {
    if (idx == NIL) return;
    ds->avl_nodes[idx].alive = 0;
    ds->avl_nodes[idx].left = ds->free_avl_head; /* freelist link */
    ds->free_avl_head = idx;
}

static int alloc_bl_slot(pivot_ds *ds) {
    if (ds->free_bl_head != NIL) {
        int idx = ds->free_bl_head;
        ds->free_bl_head = ds->bl_nodes[idx].next;
        ds->bl_nodes[idx].alive = 1;
        ds->bl_nodes[idx].next = NIL;
        return idx;
    }
    ensure_bl_cap(ds);
    int idx = ds->bl_used++;
    memset(&ds->bl_nodes[idx], 0, sizeof(block_list_node));
    ds->bl_nodes[idx].next = NIL;
    ds->bl_nodes[idx].alive = 1;
    return idx;
}

static void free_bl_slot(pivot_ds *ds, int idx) {
    if (idx == NIL) return;
    ds->bl_nodes[idx].alive = 0;
    ds->bl_nodes[idx].next = ds->free_bl_head;
    ds->free_bl_head = idx;
}

/* ---------- AVL helpers ---------- */

static int avl_height(pivot_ds *ds, int nidx) {
    return (nidx == NIL) ? 0 : ds->avl_nodes[nidx].height;
}

static void avl_update_height(pivot_ds *ds, int nidx) {
    if (nidx != NIL) {
        avl_node *n = &ds->avl_nodes[nidx];
        n->height = 1 + max_int(avl_height(ds, n->left), avl_height(ds, n->right));
    }
}

static int avl_rotate_right(pivot_ds *ds, int yidx) {
    avl_node *y = &ds->avl_nodes[yidx];
    int xidx = y->left;
    avl_node *x = &ds->avl_nodes[xidx];
    int T2 = x->right;

    x->right = yidx;
    y->left = T2;

    avl_update_height(ds, yidx);
    avl_update_height(ds, xidx);
    return xidx;
}

static int avl_rotate_left(pivot_ds *ds, int xidx) {
    avl_node *x = &ds->avl_nodes[xidx];
    int yidx = x->right;
    avl_node *y = &ds->avl_nodes[yidx];
    int T2 = y->left;

    y->left = xidx;
    x->right = T2;

    avl_update_height(ds, xidx);
    avl_update_height(ds, yidx);
    return yidx;
}

static int avl_get_balance(pivot_ds *ds, int nidx) {
    return (nidx != NIL) ? avl_height(ds, ds->avl_nodes[nidx].left) - avl_height(ds, ds->avl_nodes[nidx].right) : 0;
}

static int avl_new_node(pivot_ds *ds, double key, int block_idx) {
    int nidx = alloc_avl_slot(ds);
    avl_node *node = &ds->avl_nodes[nidx];
    node->key = key;
    node->left = node->right = NIL;
    node->height = 1;

    int blidx = alloc_bl_slot(ds);
    ds->bl_nodes[blidx].block_idx = block_idx;
    ds->bl_nodes[blidx].next = NIL;
    node->blocks_head = blidx;
    return nidx;
}

static void avl_add_block_to_node(pivot_ds *ds, int nidx, int block_idx) {
    int blidx = alloc_bl_slot(ds);
    ds->bl_nodes[blidx].block_idx = block_idx;
    ds->bl_nodes[blidx].next = ds->avl_nodes[nidx].blocks_head;
    ds->avl_nodes[nidx].blocks_head = blidx;
}

static int avl_insert_block(pivot_ds *ds, int root, double key, int block_idx) {
    if (root == NIL) return avl_new_node(ds, key, block_idx);

    avl_node *r = &ds->avl_nodes[root];

    if (key < r->key) {
        r->left = avl_insert_block(ds, r->left, key, block_idx);
    } else if (key > r->key) {
        r->right = avl_insert_block(ds, r->right, key, block_idx);
    } else {
        avl_add_block_to_node(ds, root, block_idx);
        return root;
    }

    avl_update_height(ds, root);
    int balance = avl_get_balance(ds, root);

    if (balance > 1 && key < ds->avl_nodes[r->left].key)
        return avl_rotate_right(ds, root);

    if (balance < -1 && key > ds->avl_nodes[r->right].key)
        return avl_rotate_left(ds, root);

    if (balance > 1 && key > ds->avl_nodes[r->left].key) {
        r->left = avl_rotate_left(ds, r->left);
        return avl_rotate_right(ds, root);
    }

    if (balance < -1 && key < ds->avl_nodes[r->right].key) {
        r->right = avl_rotate_right(ds, r->right);
        return avl_rotate_left(ds, root);
    }

    return root;
}

static int avl_remove_block_from_list(pivot_ds *ds, int nidx, int block_idx) {
    int prev = NIL;
    int cur = ds->avl_nodes[nidx].blocks_head;

    while (cur != NIL) {
        if (ds->bl_nodes[cur].block_idx == block_idx) {
            if (prev != NIL) ds->bl_nodes[prev].next = ds->bl_nodes[cur].next;
            else ds->avl_nodes[nidx].blocks_head = ds->bl_nodes[cur].next;
            free_bl_slot(ds, cur);
            break;
        }
        prev = cur;
        cur = ds->bl_nodes[cur].next;
    }
    return ds->avl_nodes[nidx].blocks_head == NIL;
}

static void avl_free_block_list(pivot_ds *ds, int head) {
    int cur = head;
    while (cur != NIL) {
        int next = ds->bl_nodes[cur].next;
        free_bl_slot(ds, cur);
        cur = next;
    }
}

static void avl_free_node(pivot_ds *ds, int nidx) {
    if (nidx == NIL) return;
    avl_free_block_list(ds, ds->avl_nodes[nidx].blocks_head);
    free_avl_slot(ds, nidx);
}

static int avl_min_node(pivot_ds *ds, int nidx) {
    int cur = nidx;
    while (cur != NIL && ds->avl_nodes[cur].left != NIL) cur = ds->avl_nodes[cur].left;
    return cur;
}

static int avl_delete_node_entire(pivot_ds *ds, int root) {
    if (root == NIL) return NIL;

    avl_node *r = &ds->avl_nodes[root];

    if (r->left == NIL || r->right == NIL) {
        int child = (r->left != NIL) ? r->left : r->right;
        avl_free_node(ds, root);
        return child;
    }

    int succ = avl_min_node(ds, r->right);
    avl_node *s = &ds->avl_nodes[succ];

    avl_free_block_list(ds, r->blocks_head);
    r->key = s->key;
    r->blocks_head = s->blocks_head;
    s->blocks_head = NIL;

    r->right = avl_delete_node_entire(ds, r->right);

    avl_update_height(ds, root);
    int balance = avl_get_balance(ds, root);

    if (balance > 1 && avl_get_balance(ds, r->left) >= 0)
        return avl_rotate_right(ds, root);
    if (balance > 1 && avl_get_balance(ds, r->left) < 0) {
        r->left = avl_rotate_left(ds, r->left);
        return avl_rotate_right(ds, root);
    }
    if (balance < -1 && avl_get_balance(ds, r->right) <= 0)
        return avl_rotate_left(ds, root);
    if (balance < -1 && avl_get_balance(ds, r->right) > 0) {
        r->right = avl_rotate_right(ds, r->right);
        return avl_rotate_left(ds, root);
    }

    return root;
}

static int avl_delete_block(pivot_ds *ds, int root, double key, int block_idx) {
    if (root == NIL) return NIL;

    avl_node *r = &ds->avl_nodes[root];

    if (key < r->key) {
        r->left = avl_delete_block(ds, r->left, key, block_idx);
    } else if (key > r->key) {
        r->right = avl_delete_block(ds, r->right, key, block_idx);
    } else {
        int list_empty = avl_remove_block_from_list(ds, root, block_idx);
        if (!list_empty) return root;
        return avl_delete_node_entire(ds, root);
    }

    if (root == NIL) return NIL;

    avl_update_height(ds, root);
    int balance = avl_get_balance(ds, root);

    if (balance > 1 && avl_get_balance(ds, ds->avl_nodes[root].left) >= 0)
        return avl_rotate_right(ds, root);

    if (balance > 1 && avl_get_balance(ds, ds->avl_nodes[root].left) < 0) {
        ds->avl_nodes[root].left = avl_rotate_left(ds, ds->avl_nodes[root].left);
        return avl_rotate_right(ds, root);
    }

    if (balance < -1 && avl_get_balance(ds, ds->avl_nodes[root].right) <= 0)
        return avl_rotate_left(ds, root);

    if (balance < -1 && avl_get_balance(ds, ds->avl_nodes[root].right) > 0) {
        ds->avl_nodes[root].right = avl_rotate_right(ds, ds->avl_nodes[root].right);
        return avl_rotate_left(ds, root);
    }

    return root;
}

static int avl_lower_bound(pivot_ds *ds, int root, double x) {
    int res = NIL;
    while (root != NIL) {
        if (ds->avl_nodes[root].key >= x) {
            res = root;
            root = ds->avl_nodes[root].left;
        } else {
            root = ds->avl_nodes[root].right;
        }
    }
    return res;
}

static int avl_max_node(pivot_ds *ds, int root) {
    if (root == NIL) return NIL;
    while (ds->avl_nodes[root].right != NIL) root = ds->avl_nodes[root].right;
    return root;
}

static void avl_free_tree(pivot_ds *ds, int root) {
    if (root == NIL) return;
    avl_free_tree(ds, ds->avl_nodes[root].left);
    avl_free_tree(ds, ds->avl_nodes[root].right);
    avl_free_node(ds, root);
}

/* ---------- block helpers ---------- */

static int block_create(pivot_ds *ds, int M, int in_D1) {
    int idx = alloc_block_slot(ds);
    block *b = &ds->blocks[idx];
    b->next = b->prev = NIL;
    b->size = 0;
    b->capacity = M;
    b->items = (data_pair *)malloc(sizeof(data_pair) * b->capacity);
    b->min_val = DBL_MAX;
    b->max_val = -DBL_MAX;
    b->upper = INF;
    b->in_D1 = in_D1;
    return idx;
}

static int compare_dpair_val(const void *a, const void *b) {
    const data_pair *pa = (const data_pair *)a;
    const data_pair *pb = (const data_pair *)b;
    if (pa->val < pb->val) return -1;
    if (pa->val > pb->val) return 1;
    return 0;
}

/* ---------- DS Creation / Destruction ---------- */

pivot_ds *pivotds_create(int M, double B, int max_key) {
    if (M <= 0 || max_key <= 0) return NULL;

    pivot_ds *ds = (pivot_ds *)calloc(1, sizeof(pivot_ds));
    ds->M = M;
    ds->bound = B;
    ds->max_key = max_key;

    ds->D1_head = NIL;
    ds->tree_root = NIL;

    ds->blocks = NULL; ds->blocks_used = ds->blocks_cap = 0; ds->free_block_head = NIL;
    ds->avl_nodes = NULL; ds->avl_used = ds->avl_cap = 0; ds->free_avl_head = NIL;
    ds->bl_nodes = NULL; ds->bl_used = ds->bl_cap = 0; ds->free_bl_head = NIL;

    ds->key_block = (int *)malloc(sizeof(int) * max_key);
    ds->key_index = (int *)malloc(sizeof(int) * max_key);
    ds->key_dist = (double *)malloc(sizeof(double) * max_key);

    for (int i = 0; i < max_key; ++i) {
        ds->key_block[i] = NIL;
        ds->key_index[i] = -1;
        ds->key_dist[i] = INF;
    }

    int bidx = block_create(ds, M, 1);
    ds->blocks[bidx].upper = B;
    ds->blocks[bidx].min_val = DBL_MAX;
    ds->blocks[bidx].max_val = -DBL_MAX;
    ds->D1_head = bidx;
    ds->tree_root = avl_insert_block(ds, ds->tree_root, ds->blocks[bidx].upper, bidx);

    return ds;
}

void pivotds_destroy(pivot_ds *ds) {
    if (!ds) return;

    avl_free_tree(ds, ds->tree_root);

    for (int i = 0; i < ds->blocks_used; ++i) {
        if (ds->blocks[i].alive && ds->blocks[i].items) free(ds->blocks[i].items);
    }

    free(ds->blocks);
    free(ds->avl_nodes);
    free(ds->bl_nodes);
    free(ds->key_block);
    free(ds->key_index);
    free(ds->key_dist);
    free(ds);
}

/* ---------- Forward decl ---------- */
static void ds_remove_block(pivot_ds *ds, int bidx);

/* ---------- Deletion of a single key ---------- */

static void ds_delete_key(pivot_ds *ds, int key) {
    if (key < 0 || key >= ds->max_key) return;

    int bidx = ds->key_block[key];
    if (bidx == NIL) return;

    block *b = &ds->blocks[bidx];
    int idx = ds->key_index[key];
    int last = b->size - 1;

    if (idx != last) {
        b->items[idx] = b->items[last];
        int moved_key = b->items[idx].key;
        ds->key_index[moved_key] = idx;
        ds->key_dist[moved_key] = b->items[idx].val;
        ds->key_block[moved_key] = bidx;
    }
    b->size--;

    ds->key_block[key] = NIL;
    ds->key_index[key] = -1;
    ds->key_dist[key] = INF;

    if (b->size == 0) {
        ds_remove_block(ds, bidx);
    } else {
        double mn = b->items[0].val, mx = b->items[0].val;
        for (int i = 1; i < b->size; ++i) {
            if (b->items[i].val < mn) mn = b->items[i].val;
            if (b->items[i].val > mx) mx = b->items[i].val;
        }

        double old_upper = b->upper;
        b->min_val = mn;
        b->max_val = mx;
        b->upper = mx;

        if (b->in_D1 && old_upper != b->upper) {
            ds->tree_root = avl_delete_block(ds, ds->tree_root, old_upper, bidx);
            ds->tree_root = avl_insert_block(ds, ds->tree_root, b->upper, bidx);
        }
    }
}

/* ---------- Remove entire block from DS ---------- */

static void ds_remove_block(pivot_ds *ds, int bidx) {
    if (bidx == NIL) return;
    block *b = &ds->blocks[bidx];

    if (b->prev != NIL) ds->blocks[b->prev].next = b->next;
    else ds->D1_head = b->next;

    if (b->next != NIL) ds->blocks[b->next].prev = b->prev;

    if (b->in_D1) {
        ds->tree_root = avl_delete_block(ds, ds->tree_root, b->upper, bidx);

        if (ds->D1_head == NIL) {
            int nb = block_create(ds, ds->M, 1);
            ds->blocks[nb].upper = ds->bound;
            ds->D1_head = nb;
            ds->tree_root = avl_insert_block(ds, ds->tree_root, ds->blocks[nb].upper, nb);
        }
    }

    free_block_slot(ds, bidx);
}

static inline void dpair_swap(data_pair *a, data_pair *b) {
    data_pair t = *a; *a = *b; *b = t;
}

static void partition_by_val(data_pair *a, int lo, int hi, double pivot, int *out_lt, int *out_gt) {
    int lt = lo, i = lo, gt = hi;
    while (i <= gt) {
        double v = a[i].val;
        if (v < pivot) dpair_swap(&a[lt++], &a[i++]);
        else if (v > pivot) dpair_swap(&a[i], &a[gt--]);
        else i++;
    }
    *out_lt = lt;
    *out_gt = gt;
}

static void insertion_sort_by_val(data_pair *a, int lo, int hi) {
    for (int i = lo + 1; i <= hi; ++i) {
        data_pair x = a[i];
        int j = i - 1;
        while (j >= lo && a[j].val > x.val) {
            a[j + 1] = a[j];
            --j;
        }
        a[j + 1] = x;
    }
}

static void mom_select(data_pair *a, int lo, int hi, int nth);

static double median_of_medians(data_pair *a, int lo, int hi) {
    int n = hi - lo + 1;
    if (n <= 5) {
        insertion_sort_by_val(a, lo, hi);
        return a[lo + n/2].val;
    }

    int m = 0;
    for (int g = lo; g <= hi; g += 5) {
        int g_hi = g + 4;
        if (g_hi > hi) g_hi = hi;
        insertion_sort_by_val(a, g, g_hi);
        int med = g + (g_hi - g)/2;
        dpair_swap(&a[lo + m], &a[med]);
        m++;
    }

    int mom_idx = lo + m/2;
    mom_select(a, lo, lo + m - 1, mom_idx);
    return a[mom_idx].val;
}

static void mom_select(data_pair *a, int lo, int hi, int nth) {
    while (lo < hi) {
        double pivot = median_of_medians(a, lo, hi);
        int lt, gt;
        partition_by_val(a, lo, hi, pivot, &lt, &gt);

        if (nth < lt) hi = lt - 1;
        else if (nth > gt) lo = gt + 1;
        else return;
    }
}

/* ---------- Split a D1 block when size > M ---------- */

static int ds_split_block(pivot_ds *ds, int bidx) {
    if (bidx == NIL) return NIL;
    block *b = &ds->blocks[bidx];
    if (!b->in_D1 || b->size < ds->M) return NIL;

    int n = b->size;
    double old_upper = b->upper;

    int n1 = n / 2;
    int n2 = n - n1;

    mom_select(b->items, 0, n - 1, n1);

    int b2idx = block_create(ds, ds->M, 1);
    block *b2 = &ds->blocks[b2idx];

    if (b2->capacity < n2) {
        b2->capacity = n2;
        b2->items = (data_pair *)realloc(b2->items, sizeof(data_pair) * b2->capacity);
    }

    memcpy(b2->items, b->items + n1, sizeof(data_pair) * n2);
    b2->size = n2;
    b->size = n1;

    for (int i = 0; i < b->size; ++i) {
        int k = b->items[i].key;
        ds->key_block[k] = bidx;
        ds->key_index[k] = i;
        ds->key_dist[k] = b->items[i].val;
    }
    for (int i = 0; i < b2->size; ++i) {
        int k = b2->items[i].key;
        ds->key_block[k] = b2idx;
        ds->key_index[k] = i;
        ds->key_dist[k] = b2->items[i].val;
    }

    double bmin = INF, bmax = -DBL_MAX;
    for (int i = 0; i < b->size; ++i) {
        double v = b->items[i].val;
        if (v < bmin) bmin = v;
        if (v > bmax) bmax = v;
    }
    b->min_val = bmin; b->max_val = bmax; b->upper = bmax;

    double b2min = INF, b2max = -DBL_MAX;
    for (int i = 0; i < b2->size; ++i) {
        double v = b2->items[i].val;
        if (v < b2min) b2min = v;
        if (v > b2max) b2max = v;
    }
    b2->min_val = b2min; b2->max_val = b2max; b2->upper = b2max;

    b2->next = b->next;
    b2->prev = bidx;
    if (b->next != NIL) ds->blocks[b->next].prev = b2idx;
    b->next = b2idx;

    ds->tree_root = avl_delete_block(ds, ds->tree_root, old_upper, bidx);
    ds->tree_root = avl_insert_block(ds, ds->tree_root, b->upper, bidx);
    ds->tree_root = avl_insert_block(ds, ds->tree_root, b2->upper, b2idx);

    return b2idx;
}

/* ---------- Insert(a, b) ---------- */

void pivotds_insert(pivot_ds *ds, int key, double val) {
    if (!ds) return;
    if (key < 0 || key >= ds->max_key) return;

    int blk = ds->key_block[key];
    if (blk != NIL) {
        double old = ds->key_dist[key];
        if (val >= old) return;
        ds_delete_key(ds, key);
    }

    int target_idx = NIL;
    if (ds->tree_root != NIL) {
        int node = avl_lower_bound(ds, ds->tree_root, val);
        if (node == NIL) node = avl_max_node(ds, ds->tree_root);
        if (node != NIL && ds->avl_nodes[node].blocks_head != NIL) {
            target_idx = ds->bl_nodes[ds->avl_nodes[node].blocks_head].block_idx;
        }
    }
    if (target_idx == NIL) target_idx = ds->D1_head;

    block *target = &ds->blocks[target_idx];

    if (ds->M == 1) {
        int nbidx = block_create(ds, 1, 1);
        block *nb = &ds->blocks[nbidx];
        nb->min_val = nb->max_val = nb->upper = val;

        nb->next = target_idx;
        nb->prev = target->prev;
        if (target->prev != NIL) ds->blocks[target->prev].next = nbidx;
        else ds->D1_head = nbidx;
        target->prev = nbidx;

        ds->tree_root = avl_insert_block(ds, ds->tree_root, nb->upper, nbidx);
        target_idx = nbidx;
        target = &ds->blocks[target_idx];
    } else {
        if (target->size >= target->capacity) {
            int b2idx = ds_split_block(ds, target_idx);
            if (b2idx != NIL) {
                if (val > target->upper) {
                    target_idx = b2idx;
                    target = &ds->blocks[target_idx];
                }
            }
        }
    }

    int idx = target->size;
    target->items[idx].key = key;
    target->items[idx].val = val;
    target->size++;

    if (val < target->min_val) target->min_val = val;
    if (val > target->max_val) {
        double old_upper = target->upper;
        target->max_val = val;
        target->upper = target->max_val;
        if (target->upper != old_upper) {
            ds->tree_root = avl_delete_block(ds, ds->tree_root, old_upper, target_idx);
            ds->tree_root = avl_insert_block(ds, ds->tree_root, target->upper, target_idx);
        }
    }

    ds->key_block[key] = target_idx;
    ds->key_index[key] = idx;
    ds->key_dist[key] = val;
}

/* ---------- BatchPrepend(L) ---------- */

typedef struct {
    int key;
    double val;
    char used;
} LocalMapEntry;

static int next_pow2(int n) {
    int p = 1;
    while (p < n) p <<= 1;
    return p;
}

void pivotds_batch_prepend(pivot_ds *ds, const data_pair *pairs, int L) {
    if (!ds || !pairs || L <= 0) return;

    int table_size = next_pow2(L * 2);
    LocalMapEntry *table = (LocalMapEntry *)calloc(table_size, sizeof(LocalMapEntry));
    int mask = table_size - 1;

    for (int i = 0; i < L; ++i) {
        int k = pairs[i].key;
        double v = pairs[i].val;
        int idx = (unsigned)k & (unsigned)mask;
        while (table[idx].used && table[idx].key != k) idx = (idx + 1) & mask;
        if (!table[idx].used) {
            table[idx].used = 1;
            table[idx].key = k;
            table[idx].val = v;
        } else if (v < table[idx].val) {
            table[idx].val = v;
        }
    }

    data_pair *filtered = (data_pair *)malloc(sizeof(data_pair) * L);
    int fcount = 0;

    for (int i = 0; i < table_size; ++i) {
        if (!table[i].used) continue;
        int k = table[i].key;
        if (k < 0 || k >= ds->max_key) continue;
        double newv = table[i].val;
        int blk = ds->key_block[k];
        double old = ds->key_dist[k];
        if (blk != NIL && old <= newv) continue;
        if (blk != NIL) ds_delete_key(ds, k);
        filtered[fcount].key = k;
        filtered[fcount].val = newv;
        fcount++;
    }

    free(table);

    if (fcount == 0) {
        free(filtered);
        return;
    }

    qsort(filtered, fcount, sizeof(data_pair), compare_dpair_val);

    int idx = fcount;
    while (idx > 0) {
        int block_size = ds->M;
        if (block_size > idx) block_size = idx;
        idx -= block_size;

        int bidx = block_create(ds, ds->M, 1);
        block *b = &ds->blocks[bidx];

        if (b->capacity < block_size) {
            data_pair *tmp = (data_pair *)realloc(b->items, sizeof(data_pair) * block_size);
            if (!tmp) {
                free_block_slot(ds, bidx);
                break;
            }
            b->items = tmp;
            b->capacity = block_size;
        }

        for (int j = 0; j < block_size; ++j) {
            data_pair p = filtered[idx + j];
            b->items[j] = p;
            ds->key_block[p.key] = bidx;
            ds->key_index[p.key] = j;
            ds->key_dist[p.key] = p.val;
        }

        b->size = block_size;
        b->min_val = filtered[idx].val;
        b->max_val = filtered[idx + block_size - 1].val;
        b->upper = b->max_val;

        b->prev = NIL;
        b->next = ds->D1_head;
        if (ds->D1_head != NIL) ds->blocks[ds->D1_head].prev = bidx;
        ds->D1_head = bidx;

        ds->tree_root = avl_insert_block(ds, ds->tree_root, b->upper, bidx);
    }

    free(filtered);
}

/* ---------- Pull() ---------- */

typedef struct {
    int key;
    double val;
} Candidate;

static int compare_candidate_val(const void *a, const void *b) {
    const Candidate *pa = (const Candidate *)a;
    const Candidate *pb = (const Candidate *)b;
    if (pa->val < pb->val) return -1;
    if (pa->val > pb->val) return 1;
    return 0;
}

bool is_empty_pivotds(pivot_ds *ds) {
    if (!ds) return 1;
    return ds->D1_head == NIL;
}

bmssp_returns* pivotds_pull(pivot_ds *ds) {
    if (!ds) return 0;

    bmssp_returns* pull_nodes = (bmssp_returns*)malloc(sizeof(bmssp_returns));
    pull_nodes->U = (node_set*)malloc(sizeof(node_set));
    init_node_set(pull_nodes->U, ds->max_key);

    int M = ds->M;
    Candidate *cand = (Candidate *)malloc(sizeof(Candidate) * (2 * M));
    int cand_count = 0;

    int b1 = ds->D1_head;
    int first_after_D1 = NIL;
    int count1 = 0;

    while (b1 != NIL && count1 < M) {
        block *blk = &ds->blocks[b1];
        for (int i = 0; i < blk->size && cand_count < 2 * M; ++i) {
            cand[cand_count].key = blk->items[i].key;
            cand[cand_count].val = blk->items[i].val;
            cand_count++;
        }
        count1 += blk->size;
        if (count1 >= M) {
            first_after_D1 = blk->next;
            break;
        }
        b1 = blk->next;
    }
    if (first_after_D1 == NIL && b1 != NIL) first_after_D1 = ds->blocks[b1].next;

    if (cand_count == 0) {
        pull_nodes->bound = ds->bound;
        free(cand);
        return pull_nodes;
    }

    int all_D1_covered = 1;
    int b = ds->D1_head;
    int collected = 0;
    while (b != NIL && collected < count1) {
        collected += ds->blocks[b].size;
        b = ds->blocks[b].next;
    }
    if (b != NIL) all_D1_covered = 0;

    if (all_D1_covered && cand_count <= M) {
        for (int i = 0; i < cand_count; ++i) {
            node_set_add(pull_nodes->U, cand[i].key);
            ds_delete_key(ds, cand[i].key);
        }
        pull_nodes->bound = ds->bound;
        free(cand);
        return pull_nodes;
    }

    qsort(cand, cand_count, sizeof(Candidate), compare_candidate_val);

    int out_count = (cand_count < M) ? cand_count : M;
    if (out_count <= 0) {
        pull_nodes->bound = ds->bound;
        free(cand);
        return pull_nodes;
    }

    double max_in_S = cand[out_count - 1].val;

    for (int i = 0; i < out_count; ++i) {
        node_set_add(pull_nodes->U, cand[i].key);
        ds_delete_key(ds, cand[i].key);
    }

    double x = INF;
    for (int i = out_count; i < cand_count; ++i) {
        if (cand[i].val >= max_in_S && cand[i].val < x) x = cand[i].val;
    }

    while (first_after_D1 != NIL) {
        block *blk = &ds->blocks[first_after_D1];
        if (blk->size > 0 && blk->min_val >= max_in_S && blk->min_val < x) x = blk->min_val;
        first_after_D1 = blk->next;
    }

    pull_nodes->bound = (x == INF) ? ds->bound : x;
    free(cand);
    return pull_nodes;
}

/* ---------- Debug ---------- */

static void print_block(pivot_ds *ds, int bidx, const char *label) {
    block *b = &ds->blocks[bidx];
    printf("%s [idx=%d] (size=%d, min=%.2f, max=%.2f, upper=%.2f, in_D1=%d, prev=%d, next=%d)\n",
        label, bidx, b->size, b->min_val, b->max_val, b->upper, b->in_D1, b->prev, b->next);

    printf("   items: ");
    for (int i = 0; i < b->size; ++i) {
        printf("(%d,%.2f) ", b->items[i].key, b->items[i].val);
    }
    printf("\n");
}

static void print_block_list(pivot_ds *ds, int head, const char *name) {
    printf("\n===== %s BLOCK LIST =====\n", name);
    int idx = 0;
    int b = head;
    while (b != NIL) {
        char label[64];
        snprintf(label, sizeof(label), "%s[%d]", name, idx);
        print_block(ds, b, label);
        b = ds->blocks[b].next;
        idx++;
    }
    if (idx == 0) printf("(empty)\n");
}

static void print_avl(pivot_ds *ds, int root, int depth) {
    if (root == NIL) return;

    print_avl(ds, ds->avl_nodes[root].right, depth + 1);

    for (int i = 0; i < depth; ++i) printf("        ");
    printf("-> [node=%d upper=%.2f] blocks: ", root, ds->avl_nodes[root].key);

    int bl = ds->avl_nodes[root].blocks_head;
    while (bl != NIL) {
        printf("%d ", ds->bl_nodes[bl].block_idx);
        bl = ds->bl_nodes[bl].next;
    }
    printf("\n");

    print_avl(ds, ds->avl_nodes[root].left, depth + 1);
}

static void print_tree(pivot_ds *ds) {
    printf("\n===== AVL TREE (D1 upper bounds) =====\n");
    if (ds->tree_root == NIL) {
        printf("(empty)\n");
        return;
    }
    print_avl(ds, ds->tree_root, 0);
}

static void print_key_metadata(pivot_ds *ds) {
    printf("\n===== PER-KEY METADATA =====\n");
    for (int k = 0; k < ds->max_key; ++k) {
        if (ds->key_block[k] != NIL) {
            printf("key=%d -> val=%.2f block=%d idx=%d\n",
                   k, ds->key_dist[k], ds->key_block[k], ds->key_index[k]);
        }
    }
}

void pivotds_print(pivot_ds *ds, int show_keys) {
    if (!ds) return;

    printf("\n=====================================================\n");
    printf("               SNAPSHOT OF Pivot_ds (D)\n");
    printf("=====================================================\n");
    printf("M=%d   B=%.2f   max_key=%d   D1_head=%d   tree_root=%d\n",
           ds->M, ds->bound, ds->max_key, ds->D1_head, ds->tree_root);

    print_block_list(ds, ds->D1_head, "D1");
    print_tree(ds);

    if (show_keys) print_key_metadata(ds);

    printf("=====================================================\n\n");
}

