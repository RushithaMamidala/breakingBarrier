
/* ---------- Optional: simple test main ---------- */

#include "data_structs/pivot_ds.cuh"
#include "util/returns.cuh"
#include <stdio.h>

int main(void) {
    int M = 3;
    double B = 1000000000LL;
    int max_key = 100;

    pivot_ds *ds = pivotds_create(M, B, max_key);

    pivotds_insert(ds, 1, 1.0);
    pivotds_insert(ds, 2, 0.5);
    pivotds_insert(ds, 3, 2.0);
    // pivotds_insert(ds, 4, 2);
    // pivotds_insert(ds, 5, 15);
    // pivotds_insert(ds, 6, 8);
    pivotds_print(ds, 1);

    data_pair batch[] = { {4, 0.1}, {5, 1.5}, {2, 0.3} };  // note: key 2 has better value 3
    pivotds_batch_prepend(ds, batch, 3);

    pivotds_print(ds, 1);

    // data_pair out[10];
    bmssp_returns* bmssp_ret = pivotds_pull(ds);

    pivotds_print(ds, 1);

    printf("Pulled %d elements, x = %f\n", bmssp_ret->U->count,bmssp_ret->bound);
    for (int i = 0; i < bmssp_ret->U->count; ++i) {
        printf("  key=%d val=%d\n", bmssp_ret->U->nodes[i], ds->key_dist[i]);
    }

    pivotds_destroy(ds);
    return 0;
}

