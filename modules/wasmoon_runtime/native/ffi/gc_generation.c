// Stable-identity generation metadata. Root coordination and policy are MoonBit.
#include "gc_heap.h"
#include "native_alloc.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

struct GcCardSet {
    int32_t field_count, word_count, all_dirty;
    uint64_t bits[];
};

static GcCardSet *object_cards(GcIdentityPage *page, int32_t ref) {
    return page && page->cards ? page->cards[(ref - 1) & (GC_ID_PAGE_SIZE - 1)] : NULL;
}

static void clear_cards(GcCardSet *cards) {
    if (!cards) return;
    cards->all_dirty = 0;
    memset(cards->bits, 0, (size_t)cards->word_count * sizeof(uint64_t));
}

static void clear_remembered(GcHeap *heap) {
    GcIdentityPage *page = heap->generation.remembered_pages;
    while (page) {
        GcIdentityPage *next = page->remembered_next;
        if (page->cards) {
            for (int32_t word = 0; word < GC_ID_PAGE_SIZE / 64; ++word) {
                uint64_t bits = page->remembered[word];
                for (int32_t bit = 0; bits; ++bit, bits >>= 1)
                    if (bits & 1) clear_cards(page->cards[word * 64 + bit]);
            }
        }
        memset(page->remembered, 0, sizeof(page->remembered));
        page->remembered_next = NULL;
        page->remembered_linked = 0;
        page = next;
    }
    heap->generation.remembered_pages = NULL;
    heap->generation.remembered_count = 0;
}

void gc_generation_enable(GcHeap *heap) {
    heap->generation.tracking_enabled = 1;
}

static int can_track_young(GcHeap *heap) {
    GcGeneration *generation = &heap->generation;
    return heap->data && heap->precise_roots && generation->tracking_enabled &&
        !generation->has_untyped_allocations && !heap->has_marked_objects &&
        !heap->byte_reservation && !heap->object_reservation &&
        !heap->exception_arena && !heap->continuation_arena &&
        gc_heap_allocation_faults_disabled() && !wasmoon_native_failures_enabled();
}

int gc_generation_can_collect_young(GcHeap *heap) {
    return heap->generation.old_count > 0 && heap->generation.old_boundary > 0 &&
        can_track_young(heap);
}

void gc_generation_prepare_object(GcHeap *heap, int32_t ref) {
    if (!can_track_young(heap)) return;
    GcIdentityPage *page = gc_heap_identity_page(heap, ref);
    GcHeader *header = (GcHeader *)(heap->data + gc_heap_identity_offset(heap, ref));
    GcTypeLayout *layout = gc_object_layout(heap, header);
    if (!layout || !layout->reference_count || object_cards(page, ref)) return;
    int32_t count = header->kind == GC_KIND_ARRAY
        ? *(int32_t *)(header + 1) : (int32_t)header->reserved;
    if (count < GC_CARD_MIN_FIELDS) return;
    // This optional cache is prepared while compacting survivors, never in a
    // mutator barrier. Failure retains the complete owner-scanning fallback.
    if (!page->cards) {
        page->cards = wasmoon_native_calloc(GC_ID_PAGE_SIZE, sizeof(*page->cards));
        if (!page->cards) return;
    }
    int32_t words = (int32_t)(((int64_t)count + GC_CARD_SIZE * 64 - 1) / (GC_CARD_SIZE * 64));
    GcCardSet *cards = wasmoon_native_calloc(1, sizeof(*cards) + (size_t)words * sizeof(uint64_t));
    if (!cards) {
        if (page->card_objects == 0) { free(page->cards); page->cards = NULL; }
        return;
    }
    cards->field_count = count;
    cards->word_count = words;
    page->cards[(ref - 1) & (GC_ID_PAGE_SIZE - 1)] = cards;
    ++page->card_objects;
}

void gc_generation_retire_object(GcIdentityPage *page, int32_t ref) {
    if (!page->cards) return;
    int32_t slot = (ref - 1) & (GC_ID_PAGE_SIZE - 1);
    if (!page->cards[slot]) return;
    free(page->cards[slot]);
    page->cards[slot] = NULL;
    if (--page->card_objects == 0) { free(page->cards); page->cards = NULL; }
}

void gc_generation_free_page(GcIdentityPage *page) {
    if (!page) return;
    if (page->cards) {
        for (int32_t slot = 0; slot < GC_ID_PAGE_SIZE; ++slot) free(page->cards[slot]);
        free(page->cards);
    }
    free(page);
}

size_t gc_generation_page_metadata_bytes(const GcIdentityPage *page) {
    if (!page->cards) return 0;
    size_t bytes = GC_ID_PAGE_SIZE * sizeof(*page->cards);
    for (int32_t slot = 0; slot < GC_ID_PAGE_SIZE; ++slot) {
        GcCardSet *cards = page->cards[slot];
        if (cards) bytes += sizeof(*cards) + (size_t)cards->word_count * sizeof(uint64_t);
    }
    return bytes;
}

GcCardSet *gc_generation_dirty_cards(GcHeap *heap, int32_t ref) {
    GcCardSet *cards = object_cards(gc_heap_identity_page(heap, ref), ref);
    return cards && !cards->all_dirty ? cards : NULL;
}

int32_t gc_generation_next_card(const GcCardSet *cards, int32_t start) {
    int32_t word = start >> 6;
    if (word >= cards->word_count) return -1;
    uint64_t bits = cards->bits[word] & (UINT64_MAX << (start & 63));
    for (;;) {
        if (bits) {
            int32_t bit = 0;
            while (!(bits & 1)) { bits >>= 1; ++bit; }
            return word * 64 + bit;
        }
        if (++word == cards->word_count) return -1;
        bits = cards->bits[word];
    }
}

int32_t gc_generation_card_count(GcHeap *heap, int32_t ref) {
    GcCardSet *cards = object_cards(gc_heap_identity_page(heap, ref), ref);
    if (!cards) return -2;
    if (cards->all_dirty) return -1;
    int32_t count = 0;
    for (int32_t word = 0; word < cards->word_count; ++word)
        for (uint64_t bits = cards->bits[word]; bits; bits >>= 1) count += (int32_t)(bits & 1);
    return count;
}

void gc_generation_prepare_major(GcHeap *heap) {
    // Clear links before a full sweep or rollback may release identity pages.
    // If discovery aborts, the next attempt must establish a full prefix again.
    clear_remembered(heap);
    heap->generation.old_count = 0;
    heap->generation.old_boundary = 0;
    heap->generation.old_size = 0;
    heap->generation.tracing_young = 0;
}

void gc_generation_prepare_young(GcHeap *heap) {
    // Aborted attempts do not advance collection counters or the mature
    // boundary. Their graph handles must still expire before another attempt.
    if (++heap->generation.young_epoch == 0) ++heap->generation.young_epoch;
    heap->generation.tracing_young = 1;
}

void gc_generation_remember(GcHeap *heap, int32_t owner, int32_t child, int32_t field) {
    GcGeneration *generation = &heap->generation;
    if (!generation->tracking_enabled || owner > generation->old_boundary ||
        child <= generation->old_boundary) return;
    GcIdentityPage *page = gc_heap_identity_page(heap, owner);
    if (!page) return;
    int32_t slot = (owner - 1) & (GC_ID_PAGE_SIZE - 1);
    uint64_t bit = UINT64_C(1) << (slot & 63);
    if (!(page->remembered[slot >> 6] & bit)) {
        page->remembered[slot >> 6] |= bit;
        ++generation->remembered_count;
        if (!page->remembered_linked) {
            page->remembered_next = generation->remembered_pages;
            generation->remembered_pages = page;
            page->remembered_linked = 1;
        }
    }
    GcCardSet *cards = object_cards(page, owner);
    if (cards && !cards->all_dirty) {
        if (field < 0 || field >= cards->field_count) cards->all_dirty = 1;
        else {
            int32_t card = field >> GC_CARD_SHIFT;
            cards->bits[card >> 6] |= UINT64_C(1) << (card & 63);
        }
    }
}

int32_t gc_generation_copy_remembered_roots(GcHeap *heap, int64_t *roots) {
    int32_t count = 0;
    for (GcIdentityPage *page = heap->generation.remembered_pages; page;
         page = page->remembered_next) {
        int32_t base = page->page_index * GC_ID_PAGE_SIZE;
        for (int32_t word = 0; word < GC_ID_PAGE_SIZE / 64; ++word) {
            uint64_t bits = page->remembered[word];
            for (int32_t bit = 0; bits; ++bit, bits >>= 1) {
                if (bits & 1) roots[count++] = (int64_t)(base + word * 64 + bit + 1) << 1;
            }
        }
    }
    return count;
}

void gc_generation_promote(GcHeap *heap, int young) {
    GcGeneration *generation = &heap->generation;
    if (!generation->tracking_enabled) return;
    clear_remembered(heap);
    int32_t cursor = young ? generation->old_count : 0;
    while (cursor < heap->live_count) {
        GcIdentityPage *page = gc_heap_identity_page(heap, heap->live_objects[cursor]);
        int32_t promoted = page->live_count - (young ? page->old_live_count : 0);
        page->old_live_count = page->live_count;
        cursor += promoted;
    }
    generation->old_count = heap->live_count;
    generation->old_boundary = heap->object_count;
    generation->old_size = heap->size;
    if (young) generation->minors_since_major++;
    else {
        generation->last_major_size = heap->size;
        generation->minors_since_major = 0;
    }
}

static int generation_error(const char *message, int verbose) {
    if (verbose) fprintf(stderr, "[GC VERIFY] generation: %s\n", message);
    return 0;
}

int gc_generation_verify(GcHeap *heap, int verbose) {
    GcGeneration *generation = &heap->generation;
    if (!generation->tracking_enabled) return 1;
    if (generation->old_count < 0 || generation->old_count > heap->live_count ||
        generation->old_boundary < 0 || generation->old_boundary > heap->object_count ||
        generation->old_size > heap->size)
        return generation_error("invalid mature prefix bounds", verbose);
    // An aborted major deliberately leaves no established generation facts.
    if (generation->old_count == 0) {
        if (generation->old_size || generation->remembered_count || generation->remembered_pages)
            return generation_error("empty prefix retains remembered metadata", verbose);
        return 1;
    }
    int32_t last = heap->live_objects[generation->old_count - 1];
    GcHeader *last_header = (GcHeader *)(heap->data + gc_heap_identity_offset(heap, last));
    if (last > generation->old_boundary ||
        (size_t)gc_heap_identity_offset(heap, last) + last_header->size != generation->old_size)
        return generation_error("mature payload boundary does not match identities", verbose);
    if (generation->old_count < heap->live_count &&
        heap->live_objects[generation->old_count] <= generation->old_boundary)
        return generation_error("young suffix overlaps mature identities", verbose);
    for (int32_t cursor = 0; cursor < heap->live_count;) {
        GcIdentityPage *page = gc_heap_identity_page(heap, heap->live_objects[cursor]);
        int32_t expected = generation->old_count - cursor;
        if (expected < 0) expected = 0;
        if (expected > page->live_count) expected = page->live_count;
        if (page->old_live_count != expected)
            return generation_error("identity page has an invalid mature population", verbose);
        if (page->cards) {
            int32_t card_objects = 0;
            for (int32_t slot = 0; slot < GC_ID_PAGE_SIZE; ++slot) {
                GcCardSet *cards = page->cards[slot];
                if (!cards) continue;
                ++card_objects;
                if (page->offsets[slot] < 0)
                    return generation_error("dead identity retains card metadata", verbose);
                GcHeader *header = (GcHeader *)(heap->data + page->offsets[slot]);
                GcTypeLayout *layout = gc_object_layout(heap, header);
                int32_t count = header->kind == GC_KIND_ARRAY
                    ? *(int32_t *)(header + 1) : (int32_t)header->reserved;
                int32_t words = (int32_t)(((int64_t)count + GC_CARD_SIZE * 64 - 1) / (GC_CARD_SIZE * 64));
                if (!layout || !layout->reference_count || count < GC_CARD_MIN_FIELDS ||
                    cards->field_count != count || cards->word_count != words ||
                    (cards->all_dirty != 0 && cards->all_dirty != 1))
                    return generation_error("invalid remembered-card shape", verbose);
                uint64_t dirty = cards->all_dirty;
                for (int32_t word = 0; word < words; ++word) dirty |= cards->bits[word];
                if (dirty && !((page->remembered[slot >> 6] >> (slot & 63)) & 1))
                    return generation_error("dirty cards have no remembered owner", verbose);
                int32_t tail = (int32_t)(((int64_t)count + GC_CARD_SIZE - 1) / GC_CARD_SIZE) & 63;
                if (tail && (cards->bits[words - 1] >> tail))
                    return generation_error("dirty card exceeds its object", verbose);
            }
            if (card_objects != page->card_objects || card_objects == 0)
                return generation_error("invalid remembered-card population", verbose);
        } else if (page->card_objects) {
            return generation_error("missing remembered-card storage", verbose);
        }
        cursor += page->live_count;
    }
    int32_t pages = 0, remembered = 0;
    for (GcIdentityPage *page = generation->remembered_pages; page; page = page->remembered_next) {
        if (++pages > heap->identity_page_capacity || !page->remembered_linked ||
            page->page_index < 0 || page->page_index >= heap->identity_page_capacity ||
            heap->identity_pages[page->page_index] != page || page->old_live_count <= 0)
            return generation_error("invalid remembered page list", verbose);
        for (int32_t word = 0; word < GC_ID_PAGE_SIZE / 64; ++word) {
            uint64_t bits = page->remembered[word];
            for (int32_t bit = 0; bits; ++bit, bits >>= 1) {
                if (!(bits & 1)) continue;
                int32_t slot = word * 64 + bit;
                int32_t ref = page->page_index * GC_ID_PAGE_SIZE + slot + 1;
                if (ref > generation->old_boundary || page->offsets[slot] < 0)
                    return generation_error("remembered owner is not mature and live", verbose);
                ++remembered;
            }
        }
    }
    if (remembered != generation->remembered_count)
        return generation_error("remembered owner count mismatch", verbose);
    if (generation->has_untyped_allocations) return 1;
    // Verify the barrier proof before admitting a young collection, while
    // ordinary field writes also exercise it under WASMOON_GC_VERIFY.
    for (int32_t i = 0; i < generation->old_count; ++i) {
        int32_t owner = heap->live_objects[i];
        GcIdentityPage *page = gc_heap_identity_page(heap, owner);
        int32_t slot = (owner - 1) & (GC_ID_PAGE_SIZE - 1);
        int remembered_owner = (int)((page->remembered[slot >> 6] >> (slot & 63)) & 1);
        GcCardSet *cards = object_cards(page, owner);
        GcHeader *header = (GcHeader *)(heap->data + page->offsets[slot]);
        GcTypeLayout *layout = gc_object_layout(heap, header);
        if (!layout) return generation_error("typed prefix has no physical layout", verbose);
        if (!layout->reference_count) continue;
        int array = header->kind == GC_KIND_ARRAY;
        const uint8_t *data = (const uint8_t *)(header + 1);
        int32_t count = array ? *(const int32_t *)data : layout->count;
        for (int32_t field = 0; field < count; ++field) {
            GcFieldLayout *descriptor = &layout->fields[array ? 0 : field];
            if (!descriptor->reference) continue;
            GcSlot value = gc_layout_read(array ? data + GC_ARRAY_DATA_OFFSET + (size_t)field * layout->size : data, descriptor);
            int32_t child;
            if (gc_try_decode_heap_ref_candidate(heap, value.lo, &child) && child > generation->old_boundary) {
                if (!remembered_owner)
                    return generation_error("unremembered mature-to-young edge", verbose);
                int32_t card = field >> GC_CARD_SHIFT;
                if (cards && !cards->all_dirty &&
                    !((cards->bits[card >> 6] >> (card & 63)) & 1))
                    return generation_error("unremembered mature-to-young card edge", verbose);
            }
        }
    }
    return 1;
}
