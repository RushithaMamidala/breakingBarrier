#include "mem.cuh"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

void memswp(void *a, void *b, int n)
{
  switch (n)
  {
    case 1:
    {
      int8_t a_val = *(int8_t *)a;
      int8_t b_val = *(int8_t *)b;
      a_val ^= b_val;
      b_val ^= a_val;
      a_val ^= b_val;
      *(int8_t *)a = a_val;
      *(int8_t *)b = b_val;
      break;
    }
    case 2:
    {
      int16_t a_val = *(int16_t *)a;
      int16_t b_val = *(int16_t *)b;
      a_val ^= b_val;
      b_val ^= a_val;
      a_val ^= b_val;
      *(int16_t *)a = a_val;
      *(int16_t *)b = b_val;
      break;
    }
    case 4:
    {
      int32_t a_val = *(int32_t *)a;
      int32_t b_val = *(int32_t *)b;
      a_val ^= b_val;
      b_val ^= a_val;
      a_val ^= b_val;
      *(int32_t *)a = a_val;
      *(int32_t *)b = b_val;
      break;
    }
    case 8:
    {
      int64_t a_val = *(int64_t *)a;
      int64_t b_val = *(int64_t *)b;
      a_val ^= b_val;
      b_val ^= a_val;
      a_val ^= b_val;
      *(int64_t *)a = a_val;
      *(int64_t *)b = b_val;
      break;
    }
    default:
    {
      void *tmp = malloc(n);
      memcpy(tmp, a, n);
      memcpy(a, b, n);
      memcpy(b, tmp, n);
      free(tmp);
    }
  }
}