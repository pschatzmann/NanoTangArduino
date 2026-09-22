/* Standard malloc()/free()/calloc()/realloc(), backed by the embedded
 * SDRAM (see gateware/src/sdram_bus.v, mapped at 0x1000_0000-0x107f_ffff,
 * 8MB). This core is -nostdlib with no libc, so there is no heap unless we
 * provide one ourselves - a small first-fit, address-sorted free list with
 * coalescing (the classic K&R allocator shape), not a general-purpose
 * allocator tuned for fragmentation or speed.
 *
 * The internal block-RAM (gateware/src/sram.v, used for .text/.data/.bss/
 * stack - see cores/tangnano20k/link_cmd.ld) is NOT part of this heap; it
 * is far too small (32KB) to spare for dynamic allocation.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define HEAP_BASE ((uint8_t *)0x10000000UL)
#define HEAP_SIZE (8UL * 1024UL * 1024UL)
#define ALIGNMENT 8UL

typedef struct block_header {
  size_t size; // usable bytes in this block, excluding this header
  struct block_header *next;
} block_header_t;

static block_header_t *free_list;
static int heap_initialized;

static size_t align_up(size_t n)
{
  return (n + (ALIGNMENT - 1)) & ~(ALIGNMENT - 1);
}

static void heap_init(void)
{
  free_list = (block_header_t *)HEAP_BASE;
  free_list->size = HEAP_SIZE - sizeof(block_header_t);
  free_list->next = NULL;
  heap_initialized = 1;
}

void *malloc(size_t size)
{
  if (!heap_initialized)
    heap_init();
  if (size == 0)
    return NULL;

  size = align_up(size);

  block_header_t *prev = NULL;
  block_header_t *cur = free_list;
  while (cur) {
    if (cur->size >= size) {
      size_t remaining = cur->size - size;
      if (remaining > sizeof(block_header_t) + ALIGNMENT) {
        block_header_t *split =
            (block_header_t *)((uint8_t *)cur + sizeof(block_header_t) + size);
        split->size = remaining - sizeof(block_header_t);
        split->next = cur->next;
        cur->size = size;
        if (prev)
          prev->next = split;
        else
          free_list = split;
      } else {
        if (prev)
          prev->next = cur->next;
        else
          free_list = cur->next;
      }
      cur->next = NULL;
      return (void *)((uint8_t *)cur + sizeof(block_header_t));
    }
    prev = cur;
    cur = cur->next;
  }

  return NULL; // Out of memory.
}

void free(void *ptr)
{
  if (!ptr)
    return;

  block_header_t *blk = (block_header_t *)((uint8_t *)ptr - sizeof(block_header_t));

  block_header_t *prev = NULL;
  block_header_t *cur = free_list;
  while (cur && cur < blk) {
    prev = cur;
    cur = cur->next;
  }

  blk->next = cur;
  if (prev)
    prev->next = blk;
  else
    free_list = blk;

  // Coalesce with the following free block, if adjacent.
  if (cur && (uint8_t *)blk + sizeof(block_header_t) + blk->size == (uint8_t *)cur) {
    blk->size += sizeof(block_header_t) + cur->size;
    blk->next = cur->next;
  }

  // Coalesce with the preceding free block, if adjacent.
  if (prev && (uint8_t *)prev + sizeof(block_header_t) + prev->size == (uint8_t *)blk) {
    prev->size += sizeof(block_header_t) + blk->size;
    prev->next = blk->next;
  }
}

void *calloc(size_t nmemb, size_t size)
{
  size_t total = nmemb * size;
  if (nmemb != 0 && total / nmemb != size)
    return NULL; // Overflow.

  void *ptr = malloc(total);
  if (ptr)
    memset(ptr, 0, total);
  return ptr;
}

void *realloc(void *ptr, size_t size)
{
  if (!ptr)
    return malloc(size);
  if (size == 0) {
    free(ptr);
    return NULL;
  }

  block_header_t *blk = (block_header_t *)((uint8_t *)ptr - sizeof(block_header_t));
  size_t oldSize = blk->size;
  if (align_up(size) <= oldSize)
    return ptr;

  void *newPtr = malloc(size);
  if (!newPtr)
    return NULL;

  memcpy(newPtr, ptr, oldSize);
  free(ptr);
  return newPtr;
}
