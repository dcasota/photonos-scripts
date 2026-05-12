/* heapsort.c — Doug-Finke max-heapsort port.
 * Mirrors photonos-package-report.ps1 L 1590-1641 line-for-line.
 *
 * PS source (abbreviated):
 *
 *   class HeapSort {
 *       [array] static Sort($targetList) {
 *           $heapSize = $targetList.Count
 *           for ($p = ($heapSize - 1) / 2; $p -ge 0; $p--) MaxHeapify(...)
 *           for ($i = $targetList.Count - 1; $i -gt 0; $i--) {
 *               swap targetList[0] <-> targetList[$i]
 *               $heapSize--; MaxHeapify($targetList, $heapSize, 0)
 *           }
 *           return $targetList
 *       }
 *       static MaxHeapify($targetList, $heapSize, $index) {
 *           $left  = ($index + 1) * 2 - 1
 *           $right = ($index + 1) * 2
 *           ... pick largest by  [int64](concat bytes-as-"000") ...
 *           if largest != index: swap + recurse
 *       }
 *   }
 *
 * The bizarre comparator is preserved verbatim. For ASCII-only short
 * (≤6-byte) strings it is equivalent to strcmp; longer inputs silently
 * wrap. PS L 4252 is the only call site and feeds short fragments
 * (docbook-xml directory names), so overflow is unreachable in practice.
 */
#include "pr_heapsort.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* PS key: bytes → 3-digit zero-padded decimals → concat → int64. */
static int64_t key_of(const char *s)
{
    int64_t k = 0;
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        /* multiply by 1000, add byte value. Overflow wraps; PS would
         * throw — we mirror the algorithm not the exception model. */
        k = k * 1000 + (int64_t)(*p);
    }
    return k;
}

static void swap_str(char **arr, size_t i, size_t j)
{
    char *t = arr[i];
    arr[i] = arr[j];
    arr[j] = t;
}

static void max_heapify(char **arr, size_t heap_size, size_t index)
{
    /* PS uses 1-based math: left = (index+1)*2-1, right = (index+1)*2.
     * Translates 1:1 to 0-based: left = 2*index+1, right = 2*index+2. */
    size_t left    = index * 2 + 1;
    size_t right   = index * 2 + 2;
    size_t largest = index;

    if (left  < heap_size && key_of(arr[left])  > key_of(arr[largest])) largest = left;
    if (right < heap_size && key_of(arr[right]) > key_of(arr[largest])) largest = right;

    if (largest != index) {
        swap_str(arr, index, largest);
        max_heapify(arr, heap_size, largest);
    }
}

int pr_heapsort_strings(char **arr, size_t n)
{
    if (arr == NULL && n != 0) return -1;
    if (n <= 1) return 0;

    /* Build the heap. PS iterates p from (heapSize - 1) / 2 down to 0. */
    for (long p = (long)((n - 1) / 2); p >= 0; p--) {
        max_heapify(arr, n, (size_t)p);
    }

    /* Sort: swap root with last, shrink heap, re-heapify. */
    for (size_t i = n - 1; i > 0; i--) {
        swap_str(arr, 0, i);
        max_heapify(arr, i, 0);
    }
    return 0;
}
