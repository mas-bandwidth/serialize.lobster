/*
    fuzz/host.c -- TestDifferentialAgainstSerializeC.

    A fixed-seed generator writes 2000 random programs.  serialize.c v2.0.0
    (the oracle, compiled from .ref/serialize.c-v2.0.0) writes and reads each one, and
    the Lobster port is driven as a child process over files in this test's own
    temporary directory, one process per batch of 100 programs.  Every
    program ends with an end (STANDARD.md, end), and every float and double it
    writes is finite (STANDARD.md, "Finite values only").

    For every program the two writers' bytes must be equal; each side reads the
    other's bytes and every decoded value (floats by bit pattern) must match;
    one in four programs is mutated and both readers must agree on accept or
    refuse, on the refusing step, on the refusal REASON (STANDARD.md, Refusal
    reasons), and on every value decoded before it.  A mutant appending bytes
    reaches the end's trailing_data; targeted mutants write a ranged offset one
    past its span, an all-ones exponent into a float or double field, or a
    zero or 0xFF byte into a string payload.

    --negative-control makes the C side write one int range one bit wider,
    which must make the comparison red (the make target proves it does).

    The budget and the stream are knobs, with defaults that are the per-push
    gate exactly: --seed <u64> (default 0x9e3779b97f4a7c15, the fixed seed),
    --programs <n> (default 2000; 0 means no count limit) and --duration
    <seconds> (default 0, no time limit; when set, batches run until it is
    spent, or until --programs when that is also given).  The seed is printed
    first, so any run reproduces: the same --seed and a --programs that ends
    at the failing batch regenerate exactly the failing programs.  With
    --failures <dir>, a failing run copies the failing batch (the programs
    and their bytes as the Lobster child saw them), the child's output and a
    REPRODUCE.txt naming the seed and the command into <dir>.
*/

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <time.h>

#include "serialize.h"

#define PROGRAMS 2000
#define DEFAULT_SEED 0x9e3779b97f4a7c15ULL
#define BATCH 100
#define MAXOPS 24
#define BUFCAP 1024
#define MAXTOK 4
#define TOKLEN 192

enum {
    OP_BITS, OP_BITS64, OP_BOOL, OP_U8, OP_U16, OP_U32, OP_U64,
    OP_INT, OP_INT64, OP_INT_REL, OP_U128, OP_I128, OP_FLOAT, OP_DOUBLE,
    OP_FIXED32, OP_FIXED64, OP_FIXED128, OP_CFLOAT, OP_CFLOAT_PRE,
    OP_BYTES, OP_STRING, OP_ALIGN, OP_OBJECT, OP_KINDS,
    OP_END = OP_KINDS
};

typedef struct {
    int kind;
    int bits;
    uint64_t u, u2, u3;
    int64_t s, min, max;
    int32_t i1, i2, i3;
    float f1, f2, f3, f4;
    uint32_t cmax;
    int cbits;
    float cdelta;
    int len, bufsize;
    unsigned char buf[64];
} Op;

typedef struct {
    int id;
    int nops;
    Op ops[MAXOPS + 1];
    unsigned char bytes[BUFCAP];
    int nbytes;
    unsigned char mutant[BUFCAP + 8];
    int nmutant;
    int has_mutant;
    /* One entry per ranged field the writer emitted: where its offset bits
       live and an offset one past its span, which serialize.c's reader
       refuses (STANDARD.md, int; DESIGN.md (c)).  The targeted mutant writes
       that offset so the mutant leg reaches the range refusal itself. */
    int nranged;
    int rkind[MAXOPS + 1];
    int rstart[MAXOPS + 1];
    int rwidth[MAXOPS + 1];
    uint64_t rtarget[MAXOPS + 1];
} Program;

/* ---------------------------------------------------------------- RNG --- */

static uint64_t rng_state = DEFAULT_SEED;
static uint64_t rng_next(void) {
    uint64_t z = (rng_state += 0x9e3779b97f4a7c15ULL);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    return z ^ (z >> 31);
}
static uint32_t rnd(uint32_t n) { return (uint32_t)(rng_next() % n); }
static int32_t rnd_i32_range(int32_t lo, int32_t hi) {
    uint64_t span = (uint64_t)((int64_t)hi - (int64_t)lo) + 1;
    return (int32_t)((int64_t)lo + (int64_t)(rng_next() % span));
}
static int64_t rnd_i64_range(int64_t lo, int64_t hi) {
    uint64_t span = (uint64_t)hi - (uint64_t)lo + 1;
    if (span == 0) return (int64_t)rng_next();
    return (int64_t)((uint64_t)lo + rng_next() % span);
}
static void rnd_bytes(unsigned char *p, int n) { for (int i = 0; i < n; i++) p[i] = (unsigned char)rng_next(); }
static float f32_from_bits(uint32_t u) { float f; memcpy(&f, &u, 4); return f; }
static uint32_t f32_bits(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }
static double f64_from_bits(uint64_t u) { double d; memcpy(&d, &u, 8); return d; }

/* ---------------------------------------------------------- generator --- */

static void gen_op(Op *o) {
    memset(o, 0, sizeof(*o));
    o->kind = (int)rnd(OP_KINDS);
    switch (o->kind) {
    case OP_BITS:
        o->bits = 1 + (int)rnd(32);
        o->u = rng_next() & (o->bits == 32 ? 0xFFFFFFFFULL : ((1ULL << o->bits) - 1));
        break;
    case OP_BITS64:
        o->bits = 1 + (int)rnd(64);
        o->u = rng_next() & (o->bits == 64 ? ~0ULL : ((1ULL << o->bits) - 1));
        break;
    case OP_BOOL: o->u = rnd(2); break;
    case OP_U8: o->u = rnd(256); break;
    case OP_U16: o->u = rnd(65536); break;
    case OP_U32: o->u = (uint32_t)rng_next(); break;
    case OP_U64: o->u = rng_next(); break;
    case OP_INT: {
        int c = (int)rnd(5);
        if (c == 0) { o->min = o->max = rnd_i32_range(-100, 100); }
        else if (c == 1) { int32_t r = (int32_t)(1 + rnd(1000)); o->min = -r; o->max = r; }
        else if (c == 2) { o->min = INT32_MIN; o->max = INT32_MAX; }
        else if (c == 3) { o->min = 0; o->max = 7; }
        else { o->min = rnd_i32_range(-100000, 0); o->max = rnd_i32_range(1, 100000); }
        o->s = rnd_i32_range((int32_t)o->min, (int32_t)o->max);
        break;
    }
    case OP_INT64: {
        int c = (int)rnd(5);
        if (c == 0) { o->min = o->max = rnd_i64_range(-1000000, 1000000); }
        else if (c == 1) { int64_t r = (int64_t)(1 + rnd(1000000)); o->min = -r; o->max = r; }
        else if (c == 2) { o->min = INT64_MIN; o->max = INT64_MAX; }
        else if (c == 3) { o->min = 0; o->max = 7; }
        else { o->min = rnd_i64_range(-INT64_MAX / 2, 0); o->max = rnd_i64_range(1, INT64_MAX / 2); }
        o->s = rnd_i64_range(o->min, o->max);
        break;
    }
    case OP_INT_REL: {
        int64_t prev = rnd(5) == 0 ? (int64_t)(INT32_MAX - 1 - rnd(1000)) : (int64_t)rnd(1000000);
        int64_t cur = prev + 1 + (int64_t)rnd(200000);
        if (cur > INT32_MAX) cur = INT32_MAX;
        o->i1 = (int32_t)prev;
        o->i2 = (int32_t)cur;
        break;
    }
    case OP_U128:
        o->u = rng_next(); o->u2 = rng_next();
        if (rnd(4) == 0) o->u = (rnd(2) ? 0 : ~0ULL);
        if (rnd(4) == 0) o->u2 = (rnd(2) ? 0 : ~0ULL);
        break;
    case OP_I128: {
        int c = (int)rnd(5);
        int64_t lo, hi, v;
        if (c == 0) { lo = hi = rnd_i64_range(-1000, 1000); v = lo; }
        else if (c == 1) { int64_t r = (int64_t)(1 + rnd(1000000)); lo = -r; hi = r; v = rnd_i64_range(lo, hi); }
        else if (c == 2) { lo = INT64_MIN; hi = INT64_MAX; v = (int64_t)rng_next(); }
        else if (c == 3) { lo = INT64_MIN / 2; hi = INT64_MAX / 2; v = rnd_i64_range(lo, hi); }
        else { int64_t r = (int64_t)(1 + rnd(1000000)); lo = -r; hi = r; v = (rnd(2) ? lo : hi); }
        o->min = lo; o->max = hi;
        o->u = (uint64_t)v; o->u2 = (uint64_t)(v < 0 ? -1 : 0);
        break;
    }
    case OP_FLOAT: {
        /* finite patterns only: a writer is handed finite values, and
           serialize.c asserts it.  Random bits whose exponent is all ones
           have its top bit cleared. */
        int c = (int)rnd(6);
        uint32_t b;
        if (c == 0) b = (uint32_t)rng_next();
        else if (c == 1) b = (uint32_t)rng_next() & 0x807FFFFFu;
        else if (c == 2) b = 0x7f7fffffu - (uint32_t)rnd(4);
        else if (c == 3) b = 0xff7fffffu - (uint32_t)rnd(4);
        else if (c == 4) b = 0x80000000u;
        else b = f32_bits((float)rng_next() / (float)UINT32_MAX * 100.0f - 50.0f);
        if ((b & 0x7f800000u) == 0x7f800000u) b ^= 0x40000000u;
        o->u = b;
        break;
    }
    case OP_DOUBLE: {
        int c = (int)rnd(5);
        uint64_t b;
        if (c == 0) b = rng_next();
        else if (c == 1) b = rng_next() & 0x800FFFFFFFFFFFFFULL;
        else if (c == 2) b = 0x7fefffffffffffffULL - (rng_next() & 0xFFFFFFFFULL);
        else if (c == 3) b = 0x8000000000000000ULL;
        else b = (uint64_t)rng_next();
        if ((b & 0x7ff0000000000000ULL) == 0x7ff0000000000000ULL) b ^= 0x4000000000000000ULL;
        o->u = b;
        break;
    }
    case OP_FIXED32: {
        int32_t r = (int32_t)(1 + rnd(10000));
        o->bits = 32;
        o->min = rnd(3) == 0 ? 5 : -r;
        o->max = rnd(3) == 0 ? 5 : r;
        /* min 5 with max r < 5 is an empty range: swap it (the fixed seed
           never draws one; the nightly's first random seed did) */
        if (o->min > o->max) { int64_t t = o->min; o->min = o->max; o->max = t; }
        o->s = rnd_i32_range((int32_t)o->min, (int32_t)o->max);
        break;
    }
    case OP_FIXED64: {
        int64_t r = (int64_t)(1 + rnd(1000000));
        o->bits = 64;
        o->min = rnd(3) == 0 ? -3 : -r;
        o->max = rnd(3) == 0 ? -3 : r;
        /* min -r with max -3, r < 3, is an empty range: swap it */
        if (o->min > o->max) { int64_t t = o->min; o->min = o->max; o->max = t; }
        o->s = rnd_i64_range(o->min, o->max);
        break;
    }
    case OP_FIXED128: {
        int c = (int)rnd(5);
        int64_t r = (int64_t)(1 + rnd(1000000));
        o->bits = 128;
        if (c == 0) { o->min = o->max = rnd_i64_range(-1000, 1000); }
        else if (c == 1) { o->min = -r; o->max = r; }
        else if (c == 2) { o->min = INT64_MIN; o->max = INT64_MAX; }
        else if (c == 3) { o->min = INT64_MIN / 2; o->max = INT64_MAX / 2; }
        else { o->min = -r; o->max = r; }
        o->s = rnd_i64_range(o->min, o->max);
        break;
    }
    case OP_CFLOAT: {
        if (rnd(2) == 0) { o->f1 = -2.0f; o->f2 = 2.0f; o->f3 = 0.01f; }
        else { o->f1 = 0.0f; o->f2 = 100.0f; o->f3 = 0.5f; }
        o->f4 = o->f1 + (o->f2 - o->f1) * ((float)rnd(10000) / 10000.0f);
        break;
    }
    case OP_CFLOAT_PRE: {
        uint32_t mi; int bits; float delta;
        if (rnd(2) == 0) { o->f1 = -2.0f; o->f2 = 2.0f; o->f3 = 0.01f; }
        else { o->f1 = 0.0f; o->f2 = 100.0f; o->f3 = 0.5f; }
        serialize_compressed_float_params(o->f1, o->f2, o->f3, &mi, &bits, &delta);
        o->cmax = mi; o->cbits = bits; o->cdelta = delta;
        o->f4 = o->f1 + (o->f2 - o->f1) * ((float)rnd(10000) / 10000.0f);
        break;
    }
    case OP_BYTES:
        o->len = (int)rnd(17);
        rnd_bytes(o->buf, o->len);
        break;
    case OP_STRING:
        o->bufsize = 64;
        o->len = (int)rnd(21);
        for (int i = 0; i < o->len; i++) o->buf[i] = (unsigned char)('A' + rnd(26));
        break;
    case OP_ALIGN: break;
    case OP_OBJECT: break;
    }
}

static void gen_program(Program *p, int id) {
    memset(p, 0, sizeof(*p));
    p->id = id;
    p->nops = 1 + (int)rnd(MAXOPS - 1);
    for (int i = 0; i < p->nops; i++) gen_op(&p->ops[i]);
    /* a packet is one object and its end (STANDARD.md, Compatibility Notes) */
    memset(&p->ops[p->nops], 0, sizeof(Op));
    p->ops[p->nops].kind = OP_END;
    p->nops++;
    p->has_mutant = (rnd(4) == 0);
}

/* ------------------------------------------------------------- writer --- */

static int bit_length64(uint64_t v) {
    int b = 0;
    while (v) { b++; v >>= 1; }
    return b;
}

/* Record a ranged field: its offset starts at bit bstart and spans width
   bits.  Only fields with a representable out-of-range offset are recorded
   (a full-width or degenerate span has none). */
static void record_ranged(Program *p, int kind, uint64_t span, int64_t bstart) {
    int bits = bit_length64(span);
    if (bits == 0 || bits >= 64) return;
    if (span + 1 >= (1ULL << bits)) return;
    if (p->nranged >= MAXOPS) return;
    p->rkind[p->nranged] = kind;
    p->rstart[p->nranged] = (int)bstart;
    p->rwidth[p->nranged] = bits;
    p->rtarget[p->nranged] = span + 1;
    p->nranged++;
}

/* Record a field a targeted mutant rewrites to a value every reader refuses:
   a float or double exponent set all ones (non_finite_float, STANDARD.md,
   "Finite values only"), or a string payload byte set to 0x00 (embedded_nul)
   or 0xFF (invalid_utf8, STANDARD.md, string). */
static void record_field(Program *p, int kind, int64_t bstart, int width, uint64_t target) {
    if (p->nranged >= MAXOPS) return;
    p->rkind[p->nranged] = kind;
    p->rstart[p->nranged] = (int)bstart;
    p->rwidth[p->nranged] = width;
    p->rtarget[p->nranged] = target;
    p->nranged++;
}

static int write_program(Program *p, unsigned char *buf, int cap, int widen, int *widen_done) {
    serialize_write_stream_t w;
    serialize_write_stream_init(&w, buf, cap);
    p->nranged = 0;
    for (int i = 0; i < p->nops; i++) {
        Op *o = &p->ops[i];
        int64_t bstart = serialize_write_bits_processed(&w);
        switch (o->kind) {
        case OP_BITS: serialize_write_bits(&w, (uint32_t)o->u, o->bits); break;
        case OP_BITS64: serialize_write_bits64(&w, (uint64_t)o->u, o->bits); break;
        case OP_BOOL: serialize_write_bool(&w, (int)o->u); break;
        case OP_U8: serialize_write_uint8(&w, (uint8_t)o->u); break;
        case OP_U16: serialize_write_uint16(&w, (uint16_t)o->u); break;
        case OP_U32: serialize_write_uint32(&w, (uint32_t)o->u); break;
        case OP_U64: serialize_write_uint64(&w, (uint64_t)o->u); break;
        case OP_INT: {
            int32_t mx = (int32_t)o->max;
            if (widen && !*widen_done) {
                int wid = serialize_bits_required((int32_t)o->min, (int32_t)o->max);
                if (wid >= 1 && wid < 31 && o->max <= (int64_t)INT32_MAX - (1LL << wid)) {
                    mx = (int32_t)(o->max + (1LL << wid));
                    *widen_done = 1;
                }
            }
            serialize_write_int(&w, (int32_t)o->s, (int32_t)o->min, mx);
            break;
        }
        case OP_INT64: serialize_write_int64(&w, (int64_t)o->s, o->min, o->max); break;
        case OP_INT_REL: serialize_write_int_relative(&w, o->i1, o->i2); break;
        case OP_U128: serialize_write_uint128(&w, serialize_uint128_make(o->u2, o->u)); break;
        case OP_I128:
            serialize_write_int128(&w,
                serialize_int128_make((serialize_uint64_t)o->u2, (serialize_uint64_t)o->u),
                serialize_int128_make((serialize_uint64_t)(o->min < 0 ? ~0ULL : 0), (serialize_uint64_t)o->min),
                serialize_int128_make((serialize_uint64_t)(o->max < 0 ? ~0ULL : 0), (serialize_uint64_t)o->max));
            break;
        case OP_FLOAT: serialize_write_float(&w, f32_from_bits((uint32_t)o->u)); break;
        case OP_DOUBLE: serialize_write_double(&w, f64_from_bits(o->u)); break;
        case OP_FIXED32: serialize_write_fixed32(&w, (int32_t)o->s, o->bits, 0, (int32_t)o->min, (int32_t)o->max); break;
        case OP_FIXED64: serialize_write_fixed64(&w, (int64_t)o->s, o->bits, 0, o->min, o->max); break;
        case OP_FIXED128:
            serialize_write_fixed128(&w,
                serialize_int128_make((serialize_uint64_t)(o->s < 0 ? ~0ULL : 0), (serialize_uint64_t)o->s),
                o->bits, 0, o->min, o->max);
            break;
        case OP_CFLOAT: serialize_write_compressed_float(&w, o->f4, o->f1, o->f2, o->f3); break;
        case OP_CFLOAT_PRE: serialize_write_compressed_float_precomputed(&w, o->f4, o->cmax, o->cbits, o->cdelta, o->f1); break;
        case OP_BYTES: serialize_write_bytes(&w, o->buf, o->len); break;
        case OP_STRING: serialize_write_string(&w, (const char *)o->buf, o->bufsize); break;
        case OP_ALIGN: serialize_write_align(&w); break;
        case OP_END: serialize_write_end(&w); break;
        case OP_OBJECT:
            serialize_write_bool(&w, 1);
            serialize_write_int(&w, 3, 0, 7);
            serialize_write_uint16(&w, 42);
            break;
        }
        switch (o->kind) {
        case OP_INT:
            record_ranged(p, o->kind, (uint32_t)o->max - (uint32_t)o->min, bstart);
            break;
        case OP_INT64:
        case OP_FIXED32:
        case OP_FIXED64:
        case OP_FIXED128:
        case OP_I128:
            record_ranged(p, o->kind, (uint64_t)o->max - (uint64_t)o->min, bstart);
            break;
        case OP_FLOAT:
            record_field(p, o->kind, bstart + 23, 8, 0xFF);
            break;
        case OP_DOUBLE:
            record_field(p, o->kind, bstart + 52, 11, 0x7FF);
            break;
        case OP_STRING:
            if (o->len > 0) {
                /* the payload starts at the byte boundary after the length */
                int64_t payload = (bstart + serialize_bits_required(0, o->bufsize - 1) + 7) / 8 * 8;
                record_field(p, o->kind, payload + 8 * (p->id % o->len), 8, (p->id & 1) ? 0xFF : 0x00);
            }
            break;
        }
    }
    serialize_write_flush(&w);
    if (serialize_write_error(&w)) return -1;
    return (int)serialize_write_bytes_processed(&w);
}

/* ------------------------------------------------------------- reader --- */

typedef struct {
    int accept;
    int refstep;
    char reason[32];
    int ntok[MAXOPS + 1];
    char tok[MAXOPS + 1][MAXTOK][TOKLEN];
} ReadResult;

static void tok_u64(char *out, uint64_t v) { snprintf(out, TOKLEN, "%016" PRIx64, v); }
static void tok_i64(char *out, int64_t v) { tok_u64(out, (uint64_t)v); }
static void tok_u128(char *out, uint64_t hi, uint64_t lo) {
    snprintf(out, TOKLEN, "%016" PRIx64 "%016" PRIx64, hi, lo);
}
static void tok_hexbytes(char *out, const unsigned char *p, int n) {
    if (n == 0) { strcpy(out, "-"); return; }
    for (int i = 0; i < n; i++) sprintf(out + 2 * i, "%02x", p[i]);
    out[2 * n] = 0;
}

static int read_program(const unsigned char *bytes, int nbytes, Program *p, ReadResult *r) {
    unsigned char data[BUFCAP + 8];
    memset(data, 0, sizeof(data));
    if (nbytes > BUFCAP) return -1;
    memcpy(data, bytes, (size_t)nbytes);
    serialize_read_stream_t rd;
    serialize_read_stream_init_padded(&rd, data, (int)sizeof(data), data, nbytes);
    memset(r, 0, sizeof(*r));
    r->refstep = p->nops;
    for (int i = 0; i < p->nops; i++) {
        Op *o = &p->ops[i];
        int ok = 0;
        switch (o->kind) {
        case OP_BITS: { uint32_t v = 0; ok = serialize_read_bits(&rd, &v, o->bits); if (ok) tok_u64(r->tok[i][0], v); break; }
        case OP_BITS64: { uint64_t v = 0; ok = serialize_read_bits64(&rd, &v, o->bits); if (ok) tok_u64(r->tok[i][0], v); break; }
        case OP_BOOL: { int v = 0; ok = serialize_read_bool(&rd, &v); if (ok) strcpy(r->tok[i][0], v ? "1" : "0"); break; }
        case OP_U8: { uint8_t v = 0; ok = serialize_read_uint8(&rd, &v); if (ok) tok_u64(r->tok[i][0], v); break; }
        case OP_U16: { uint16_t v = 0; ok = serialize_read_uint16(&rd, &v); if (ok) tok_u64(r->tok[i][0], v); break; }
        case OP_U32: { uint32_t v = 0; ok = serialize_read_uint32(&rd, &v); if (ok) tok_u64(r->tok[i][0], v); break; }
        case OP_U64: { uint64_t v = 0; ok = serialize_read_uint64(&rd, &v); if (ok) tok_u64(r->tok[i][0], v); break; }
        case OP_INT: { int32_t v = 0; ok = serialize_read_int(&rd, &v, (int32_t)o->min, (int32_t)o->max); if (ok) tok_i64(r->tok[i][0], v); break; }
        case OP_INT64: { int64_t v = 0; ok = serialize_read_int64(&rd, &v, o->min, o->max); if (ok) tok_i64(r->tok[i][0], v); break; }
        case OP_INT_REL: { int32_t v = 0; ok = serialize_read_int_relative(&rd, o->i1, &v); if (ok) tok_i64(r->tok[i][0], v); break; }
        case OP_U128: { serialize_uint128_t v; ok = serialize_read_uint128(&rd, &v); if (ok) tok_u128(r->tok[i][0], v.hi, v.lo); break; }
        case OP_I128: {
            serialize_int128_t v;
            serialize_int128_t mn = serialize_int128_make((serialize_uint64_t)(o->min < 0 ? ~0ULL : 0), (serialize_uint64_t)o->min);
            serialize_int128_t mx = serialize_int128_make((serialize_uint64_t)(o->max < 0 ? ~0ULL : 0), (serialize_uint64_t)o->max);
            ok = serialize_read_int128(&rd, &v, mn, mx);
            if (ok) tok_u128(r->tok[i][0], v.hi, v.lo);
            break;
        }
        case OP_FLOAT: { float v = 0; ok = serialize_read_float(&rd, &v); if (ok) snprintf(r->tok[i][0], TOKLEN, "%08" PRIx32, f32_bits(v)); break; }
        case OP_DOUBLE: { double v = 0; ok = serialize_read_double(&rd, &v); if (ok) { uint64_t b; memcpy(&b, &v, 8); tok_u64(r->tok[i][0], b); } break; }
        case OP_FIXED32: { int32_t v = 0; ok = serialize_read_fixed32(&rd, &v, o->bits, 0, (int32_t)o->min, (int32_t)o->max); if (ok) tok_i64(r->tok[i][0], v); break; }
        case OP_FIXED64: { int64_t v = 0; ok = serialize_read_fixed64(&rd, &v, o->bits, 0, o->min, o->max); if (ok) tok_i64(r->tok[i][0], v); break; }
        case OP_FIXED128: {
            serialize_int128_t v;
            ok = serialize_read_fixed128(&rd, &v, o->bits, 0, o->min, o->max);
            if (ok) tok_u128(r->tok[i][0], v.hi, v.lo);
            break;
        }
        case OP_CFLOAT: { float v = 0; ok = serialize_read_compressed_float(&rd, &v, o->f1, o->f2, o->f3); if (ok) snprintf(r->tok[i][0], TOKLEN, "%08" PRIx32, f32_bits(v)); break; }
        case OP_CFLOAT_PRE: { float v = 0; ok = serialize_read_compressed_float_precomputed(&rd, &v, o->cmax, o->cbits, o->cdelta, o->f1); if (ok) snprintf(r->tok[i][0], TOKLEN, "%08" PRIx32, f32_bits(v)); break; }
        case OP_BYTES: {
            unsigned char tmp[64];
            memset(tmp, 0, sizeof(tmp));
            ok = serialize_read_bytes(&rd, tmp, o->len);
            if (ok) tok_hexbytes(r->tok[i][0], tmp, o->len);
            break;
        }
        case OP_STRING: {
            char tmp[128];
            memset(tmp, 0, sizeof(tmp));
            ok = serialize_read_string(&rd, tmp, o->bufsize);
            if (ok) tok_hexbytes(r->tok[i][0], (unsigned char *)tmp, (int)strlen(tmp));
            break;
        }
        case OP_ALIGN: ok = serialize_read_align(&rd); if (ok) r->ntok[i] = 0; break;
        case OP_END: ok = serialize_read_end(&rd); if (ok) r->ntok[i] = 0; break;
        case OP_OBJECT: {
            int b = 0, iv = 0; uint16_t uv = 0;
            ok = serialize_read_bool(&rd, &b);
            if (ok) ok = serialize_read_int(&rd, &iv, 0, 7);
            if (ok) ok = serialize_read_uint16(&rd, &uv);
            if (ok) {
                strcpy(r->tok[i][0], b ? "1" : "0");
                tok_i64(r->tok[i][1], iv);
                tok_u64(r->tok[i][2], uv);
            }
            break;
        }
        }
        if (!ok) {
            r->accept = 0;
            r->refstep = i;
            snprintf(r->reason, sizeof(r->reason), "%s", serialize_refusal_name(serialize_read_refusal(&rd)));
            return 1;
        }
        if (o->kind != OP_ALIGN && o->kind != OP_END) {
            r->ntok[i] = o->kind == OP_OBJECT ? 3 : 1;
        }
    }
    r->accept = 1;
    r->refstep = p->nops;
    snprintf(r->reason, sizeof(r->reason), "none");
    return 1;
}

/* ---------------------------------------------------------- mutations --- */

/* Targets are chosen independently of the base generator's stream, so adding
   them does not perturb the programs and mutants it already covers. */
static int targeted_kind[OP_KINDS + 1];

static void set_bits_le(unsigned char *buf, int bit, int width, uint64_t value) {
    for (int k = 0; k < width; k++) {
        int b = bit + k;
        unsigned char mask = (unsigned char)(1u << (b & 7));
        if ((value >> k) & 1) buf[b >> 3] |= mask;
        else buf[b >> 3] &= (unsigned char)~mask;
    }
}

/* Rewrite one ranged field's offset one past its span: serialize.c's reader
   refuses there, so the mutant exercises the reader's range check rather than
   only truncation and string framing (STANDARD.md, int; DESIGN.md (c)).
   Kinds are visited least-used first so every ranged kind is reached. */
static int make_targeted_mutant(Program *p) {
    int best = -1;
    for (int k = 0; k < p->nranged; k++) {
        if (best < 0 || targeted_kind[p->rkind[k]] < targeted_kind[p->rkind[best]])
            best = k;
    }
    if (best < 0) return 0;
    memcpy(p->mutant, p->bytes, (size_t)p->nbytes);
    p->nmutant = p->nbytes;
    set_bits_le(p->mutant, p->rstart[best], p->rwidth[best], p->rtarget[best]);
    targeted_kind[p->rkind[best]]++;
    return 1;
}

static int make_mutant(Program *p) {
    p->nmutant = p->nbytes;
    memcpy(p->mutant, p->bytes, (size_t)p->nbytes);
    int kind = (int)rnd(3);
    if (kind == 0) {
        int flips = 1 + (int)rnd(4);
        for (int k = 0; k < flips && p->nbytes > 0; k++) {
            int bit = (int)rnd((uint32_t)(p->nbytes * 8));
            p->mutant[bit >> 3] ^= (unsigned char)(1u << (bit & 7));
        }
    } else if (kind == 1) {
        p->nmutant = (int)rnd((uint32_t)(p->nbytes + 1));
    } else {
        int extra = 1 + (int)rnd(4);
        for (int k = 0; k < extra; k++) p->mutant[p->nmutant++] = (unsigned char)rng_next();
    }
    /* Half the mutants keep their random mutation (bit flips, truncation, or
       appended bytes that reach the end's trailing_data); the other half are
       targeted.  The split is by id, so the generator stream is untouched. */
    if (p->id & 2) return 0;
    return make_targeted_mutant(p);
}

/* ----------------------------------------------------------- encoding --- */

static void hex_encode(char *out, const unsigned char *p, int n) {
    if (n == 0) { strcpy(out, "-"); return; }
    for (int i = 0; i < n; i++) sprintf(out + 2 * i, "%02x", p[i]);
    out[2 * n] = 0;
}


static void write_op_line(FILE *f, const Op *o) {
    switch (o->kind) {
    case OP_BITS: fprintf(f, "bits %d %" PRIu64 "\n", o->bits, o->u); break;
    case OP_BITS64: fprintf(f, "bits64 %d %016" PRIx64 "\n", o->bits, o->u); break;
    case OP_BOOL: fprintf(f, "bool %" PRIu64 "\n", o->u); break;
    case OP_U8: fprintf(f, "uint8 %" PRIu64 "\n", o->u); break;
    case OP_U16: fprintf(f, "uint16 %" PRIu64 "\n", o->u); break;
    case OP_U32: fprintf(f, "uint32 %" PRIu64 "\n", o->u); break;
    case OP_U64: fprintf(f, "uint64 %016" PRIx64 "\n", o->u); break;
    case OP_INT: fprintf(f, "int %" PRId64 " %" PRId64 " %" PRId64 "\n", o->min, o->max, o->s); break;
    case OP_INT64: fprintf(f, "int64 %" PRId64 " %" PRId64 " %" PRId64 "\n", o->min, o->max, o->s); break;
    case OP_INT_REL: fprintf(f, "int_rel %d %d\n", o->i1, o->i2); break;
    case OP_U128: fprintf(f, "uint128 %016" PRIx64 " %016" PRIx64 "\n", o->u, o->u2); break;
    case OP_I128:
        fprintf(f, "int128 %016" PRIx64 " %016" PRIx64 " %016" PRIx64 " %016" PRIx64 " %016" PRIx64 " %016" PRIx64 "\n",
            (uint64_t)o->min, (uint64_t)(o->min < 0 ? ~0ULL : 0),
            (uint64_t)o->max, (uint64_t)(o->max < 0 ? ~0ULL : 0),
            o->u, o->u2);
        break;
    case OP_FLOAT: fprintf(f, "float %08" PRIx32 "\n", (uint32_t)o->u); break;
    case OP_DOUBLE: fprintf(f, "double %016" PRIx64 "\n", o->u); break;
    case OP_FIXED32: fprintf(f, "fixed32 %d 0 %" PRId64 " %" PRId64 " %" PRId64 "\n", o->bits, o->min, o->max, o->s); break;
    case OP_FIXED64: fprintf(f, "fixed64 %d 0 %" PRId64 " %" PRId64 " %" PRId64 "\n", o->bits, o->min, o->max, o->s); break;
    case OP_FIXED128:
        fprintf(f, "fixed128 %d 0 %" PRId64 " %" PRId64 " %016" PRIx64 " %016" PRIx64 "\n",
            o->bits, o->min, o->max, (uint64_t)o->s, (uint64_t)(o->s < 0 ? ~0ULL : 0));
        break;
    case OP_CFLOAT: fprintf(f, "cfloat %08" PRIx32 " %08" PRIx32 " %08" PRIx32 " %08" PRIx32 "\n",
        f32_bits(o->f1), f32_bits(o->f2), f32_bits(o->f3), f32_bits(o->f4)); break;
    case OP_CFLOAT_PRE: fprintf(f, "cfloat_pre %" PRIu32 " %d %08" PRIx32 " %08" PRIx32 " %08" PRIx32 "\n",
        o->cmax, o->cbits, f32_bits(o->cdelta), f32_bits(o->f1), f32_bits(o->f4)); break;
    case OP_BYTES: {
        char hx[256]; hex_encode(hx, o->buf, o->len);
        fprintf(f, "bytes %d %s\n", o->len, hx);
        break;
    }
    case OP_STRING: {
        char hx[256]; hex_encode(hx, o->buf, o->len);
        fprintf(f, "string %d %s\n", o->bufsize, hx);
        break;
    }
    case OP_ALIGN: fprintf(f, "align\n"); break;
    case OP_END: fprintf(f, "end\n"); break;
    case OP_OBJECT: fprintf(f, "object\n"); break;
    }
}

/* -------------------------------------------------- child process I/O --- */

static int run_lobster(const char *lobster, const char *driver, const char *batch, const char *out) {
    pid_t pid = fork();
    if (pid < 0) { perror("fork"); return -1; }
    if (pid == 0) {
        execl(lobster, lobster, driver, "--", batch, out, (char *)NULL);
        perror("execl lobster");
        _exit(127);
    }
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) { perror("waitpid"); return -1; }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "lobster child failed (status %d)\n", status);
        return -1;
    }
    return 0;
}

typedef struct {
    int seen;
    unsigned char wbytes[BUFCAP + 8];
    int nw;
    int wok;
    ReadResult c, m;
} LobOut;

static int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int hex_decode(const char *s, unsigned char *out, int cap) {
    if (strcmp(s, "-") == 0) return 0;
    int n = (int)strlen(s) / 2;
    if (n > cap) return -1;
    for (int i = 0; i < n; i++) {
        int hi = hex_digit(s[2 * i]), lo = hex_digit(s[2 * i + 1]);
        if (hi < 0 || lo < 0) return -1;
        out[i] = (unsigned char)((hi << 4) | lo);
    }
    return n;
}

static int parse_out(const char *path, LobOut *outs, int nprog, int base) {
    FILE *f = fopen(path, "r");
    if (!f) { perror("open lobster output"); return -1; }
    char line[8192];
    int rc = 0;
    while (fgets(line, sizeof(line), f)) {
        char *nl = strchr(line, '\n');
        if (nl) *nl = 0;
        char *save = NULL;
        char *tag = strtok_r(line, " ", &save);
        if (!tag) continue;
        if (strcmp(tag, "W") == 0) {
            char *ids = strtok_r(NULL, " ", &save);
            char *hex = strtok_r(NULL, " ", &save);
            char *ok = strtok_r(NULL, " ", &save);
            if (!ids || !hex || !ok) { rc = -1; break; }
            int id = atoi(ids) - base;
            if (id < 0 || id >= nprog) { rc = -1; break; }
            int n = hex_decode(hex, outs[id].wbytes, BUFCAP);
            if (n < 0) { rc = -1; break; }
            outs[id].nw = n;
            outs[id].wok = atoi(ok);
            outs[id].seen |= 1;
        } else if (strcmp(tag, "R") == 0) {
            char *ids = strtok_r(NULL, " ", &save);
            char *src = strtok_r(NULL, " ", &save);
            char *acc = strtok_r(NULL, " ", &save);
            char *st = strtok_r(NULL, " ", &save);
            char *why = strtok_r(NULL, " ", &save);
            if (!ids || !src || !acc || !st || !why) { rc = -1; break; }
            int id = atoi(ids) - base;
            if (id < 0 || id >= nprog) { rc = -1; break; }
            ReadResult *r = (src[0] == 'c') ? &outs[id].c : &outs[id].m;
            r->accept = atoi(acc);
            r->refstep = atoi(st);
            snprintf(r->reason, sizeof(r->reason), "%s", why);
            if (src[0] == 'c') outs[id].seen |= 2; else outs[id].seen |= 4;
        } else if (strcmp(tag, "V") == 0) {
            char *ids = strtok_r(NULL, " ", &save);
            char *src = strtok_r(NULL, " ", &save);
            char *idx = strtok_r(NULL, " ", &save);
            if (!ids || !src || !idx) { rc = -1; break; }
            int id = atoi(ids) - base;
            int i = atoi(idx);
            if (id < 0 || id >= nprog || i < 0 || i > MAXOPS) { rc = -1; break; }
            ReadResult *r = (src[0] == 'c') ? &outs[id].c : &outs[id].m;
            int k = 0;
            char *tok;
            while ((tok = strtok_r(NULL, " ", &save)) != NULL && k < MAXTOK) {
                snprintf(r->tok[i][k], TOKLEN, "%s", tok);
                k++;
            }
            r->ntok[i] = k;
        }
    }
    fclose(f);
    return rc;
}

/* ----------------------------------------------------------- compare --- */

static void print_program(FILE *f, Program *p, int widen) {
    (void)widen;
    fprintf(f, "program %d (%d ops)\n", p->id, p->nops);
    for (int i = 0; i < p->nops; i++) {
        /* write_op_line writes against a FILE; reuse via tmpfile-free approach */
        fprintf(f, "  op %d ", i);
        switch (p->ops[i].kind) {
        case OP_BITS: fprintf(f, "bits %d %" PRIu64, p->ops[i].bits, p->ops[i].u); break;
        case OP_BITS64: fprintf(f, "bits64 %d %016" PRIx64, p->ops[i].bits, p->ops[i].u); break;
        case OP_BOOL: fprintf(f, "bool %" PRIu64, p->ops[i].u); break;
        case OP_U8: fprintf(f, "uint8 %" PRIu64, p->ops[i].u); break;
        case OP_U16: fprintf(f, "uint16 %" PRIu64, p->ops[i].u); break;
        case OP_U32: fprintf(f, "uint32 %" PRIu64, p->ops[i].u); break;
        case OP_U64: fprintf(f, "uint64 %016" PRIx64, p->ops[i].u); break;
        case OP_INT: fprintf(f, "int %" PRId64 " %" PRId64 " %" PRId64, p->ops[i].min, p->ops[i].max, p->ops[i].s); break;
        case OP_INT64: fprintf(f, "int64 %" PRId64 " %" PRId64 " %" PRId64, p->ops[i].min, p->ops[i].max, p->ops[i].s); break;
        case OP_INT_REL: fprintf(f, "int_rel %d %d", p->ops[i].i1, p->ops[i].i2); break;
        case OP_U128: fprintf(f, "uint128 %016" PRIx64 " %016" PRIx64, p->ops[i].u, p->ops[i].u2); break;
        case OP_I128: fprintf(f, "int128 %" PRId64 " %" PRId64 " %" PRId64 " %016" PRIx64, p->ops[i].min, p->ops[i].max, p->ops[i].s, p->ops[i].u); break;
        case OP_FLOAT: fprintf(f, "float %08" PRIx32, (uint32_t)p->ops[i].u); break;
        case OP_DOUBLE: fprintf(f, "double %016" PRIx64, p->ops[i].u); break;
        case OP_FIXED32: fprintf(f, "fixed32 %d %" PRId64 " %" PRId64 " %" PRId64, p->ops[i].bits, p->ops[i].min, p->ops[i].max, p->ops[i].s); break;
        case OP_FIXED64: fprintf(f, "fixed64 %d %" PRId64 " %" PRId64 " %" PRId64, p->ops[i].bits, p->ops[i].min, p->ops[i].max, p->ops[i].s); break;
        case OP_FIXED128: fprintf(f, "fixed128 %d %" PRId64 " %" PRId64 " %" PRId64, p->ops[i].bits, p->ops[i].min, p->ops[i].max, p->ops[i].s); break;
        case OP_CFLOAT: fprintf(f, "cfloat %08" PRIx32 " %08" PRIx32 " %08" PRIx32 " %08" PRIx32, f32_bits(p->ops[i].f1), f32_bits(p->ops[i].f2), f32_bits(p->ops[i].f3), f32_bits(p->ops[i].f4)); break;
        case OP_CFLOAT_PRE: fprintf(f, "cfloat_pre %" PRIu32 " %d", p->ops[i].cmax, p->ops[i].cbits); break;
        case OP_BYTES: { char hx[256]; hex_encode(hx, p->ops[i].buf, p->ops[i].len); fprintf(f, "bytes %d %s", p->ops[i].len, hx); break; }
        case OP_STRING: { char hx[256]; hex_encode(hx, p->ops[i].buf, p->ops[i].len); fprintf(f, "string %d %s", p->ops[i].bufsize, hx); break; }
        case OP_ALIGN: fprintf(f, "align"); break;
        case OP_END: fprintf(f, "end"); break;
        case OP_OBJECT: fprintf(f, "object"); break;
        }
        fprintf(f, "\n");
    }
}

static int compare_read(const char *what, Program *p, ReadResult *exp, ReadResult *got, int *failed) {
    if (exp->accept != got->accept) {
        fprintf(stderr, "%s: accept mismatch (C %d, Lobster %d)\n", what, exp->accept, got->accept);
        *failed = 1;
        return 0;
    }
    if (!exp->accept && exp->refstep != got->refstep) {
        fprintf(stderr, "%s: refusal step mismatch (C %d, Lobster %d)\n", what, exp->refstep, got->refstep);
        *failed = 1;
        return 0;
    }
    if (strcmp(exp->reason, got->reason) != 0) {
        fprintf(stderr, "%s: refusal reason mismatch (C %s, Lobster %s)\n", what, exp->reason, got->reason);
        *failed = 1;
        return 0;
    }
    int upto = exp->accept ? p->nops : exp->refstep;
    for (int i = 0; i < upto; i++) {
        if (exp->ntok[i] != got->ntok[i]) {
            fprintf(stderr, "%s: op %d token count mismatch (C %d, Lobster %d)\n", what, i, exp->ntok[i], got->ntok[i]);
            *failed = 1;
            return 0;
        }
        for (int k = 0; k < exp->ntok[i]; k++) {
            if (strcmp(exp->tok[i][k], got->tok[i][k]) != 0) {
                fprintf(stderr, "%s: op %d value %d mismatch (C %s, Lobster %s)\n",
                    what, i, k, exp->tok[i][k], got->tok[i][k]);
                *failed = 1;
                return 0;
            }
        }
    }
    return 1;
}

/* How many mutants the oracle refused, per reason: the PASS line prints them,
   so a run that stops reaching a rule shows it. */
static int refused_by_reason[SERIALIZE_REFUSAL_NON_CANONICAL + 1];

static void count_reason(const char *reason) {
    for (int k = 1; k <= (int)SERIALIZE_REFUSAL_NON_CANONICAL; k++) {
        if (strcmp(reason, serialize_refusal_name((serialize_refusal_t)k)) == 0) refused_by_reason[k]++;
    }
}

static int run_batch(const char *lobster, const char *driver, const char *tmpdir,
                     Program *progs, int nprog, int widen, int *widen_done,
                     int *targeted) {
    char batch[4096], out[4096], hex[BUFCAP * 2 + 8];
    snprintf(batch, sizeof(batch), "%s/batch.txt", tmpdir);
    snprintf(out, sizeof(out), "%s/result.txt", tmpdir);

    FILE *f = fopen(batch, "w");
    if (!f) { perror("fopen batch"); return -1; }
    int total_mutants = 0;
    for (int i = 0; i < nprog; i++) {
        Program *p = &progs[i];
        p->nbytes = write_program(p, p->bytes, BUFCAP, widen, widen_done);
        if (p->nbytes < 0) {
            fprintf(stderr, "C writer failed on program %d (a generated program is invalid)\n", p->id);
            fclose(f);
            return -1;
        }
        if (p->has_mutant) { if (make_mutant(p)) (*targeted)++; total_mutants++; }
        hex_encode(hex, p->bytes, p->nbytes);
        char mh[BUFCAP * 2 + 8];
        hex_encode(mh, p->mutant, p->nmutant);
        fprintf(f, "P %d %d %d %s %s\n", p->id, p->nops, p->has_mutant ? 1 : 0, hex, p->has_mutant ? mh : "-");
        for (int k = 0; k < p->nops; k++) write_op_line(f, &p->ops[k]);
    }
    fclose(f);

    if (run_lobster(lobster, driver, batch, out) != 0) return -1;

    LobOut *outs = calloc((size_t)nprog, sizeof(LobOut));
    if (!outs) { fprintf(stderr, "out of memory\n"); return -1; }
    if (parse_out(out, outs, nprog, progs[0].id) != 0) {
        fprintf(stderr, "could not parse Lobster output\n");
        return -1;
    }

    int failed = 0;
    for (int i = 0; i < nprog; i++) {
        Program *p = &progs[i];
        LobOut *lo = &outs[i];
        if (!(lo->seen & 1) || !(lo->seen & 2) || (p->has_mutant && !(lo->seen & 4))) {
            fprintf(stderr, "program %d: missing Lobster output (seen %d)\n", p->id, lo->seen);
            failed = 1;
            continue;
        }
        if (lo->nw != p->nbytes || memcmp(lo->wbytes, p->bytes, (size_t)p->nbytes) != 0) {
            fprintf(stderr, "program %d: write bytes differ\n", p->id);
            print_program(stderr, p, widen);
            char a[BUFCAP * 2 + 8], b[BUFCAP * 2 + 8];
            hex_encode(a, p->bytes, p->nbytes);
            hex_encode(b, lo->wbytes, lo->nw);
            fprintf(stderr, "  C:       %s\n  Lobster: %s\n", a, b);
            failed = 1;
            continue;
        }
        ReadResult expc, expm;
        if (read_program(p->bytes, p->nbytes, p, &expc) != 1) { failed = 1; continue; }
        if (!compare_read("own bytes", p, &expc, &lo->c, &failed)) {
            print_program(stderr, p, widen);
        }
        if (p->has_mutant) {
            if (read_program(p->mutant, p->nmutant, p, &expm) != 1) { failed = 1; continue; }
            if (!expm.accept) count_reason(expm.reason);
            if (!compare_read("mutant", p, &expm, &lo->m, &failed)) {
                print_program(stderr, p, widen);
                char a[BUFCAP * 2 + 8];
                hex_encode(a, p->mutant, p->nmutant);
                fprintf(stderr, "  mutant: %s\n", a);
            }
        }
        if (failed) break;
    }
    free(outs);
    return failed ? -1 : total_mutants;
}

/* --------------------------------------------------------------- main --- */

static double now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static int parse_u64(const char *text, uint64_t *out) {
    char *end = NULL;
    if (!text || !*text || *text == '-') return 0;
    unsigned long long v = strtoull(text, &end, 0);
    if (!end || *end != '\0') return 0;
    *out = (uint64_t)v;
    return 1;
}

static int copy_file(const char *from, const char *to) {
    FILE *a = fopen(from, "rb");
    if (!a) return 0;
    FILE *b = fopen(to, "wb");
    if (!b) { fclose(a); return 0; }
    char buf[65536];
    size_t n;
    int ok = 1;
    while ((n = fread(buf, 1, sizeof(buf), a)) > 0) {
        if (fwrite(buf, 1, n, b) != n) { ok = 0; break; }
    }
    fclose(a);
    if (fclose(b) != 0) ok = 0;
    return ok;
}

/* save_failure keeps the failing batch, the child's output and how to
   reproduce them in dir (created if missing). */
static void save_failure(const char *dir, const char *work, uint64_t seed,
                         long long first, long long end, int negative) {
    char from[4096 + 64], to[4096 + 64]; /* work is a 4096-byte path; room for the file name */
    mkdir(dir, 0755);
    snprintf(from, sizeof(from), "%s/batch.txt", work);
    snprintf(to, sizeof(to), "%s/batch.txt", dir);
    if (!copy_file(from, to)) fprintf(stderr, "could not copy %s to %s\n", from, to);
    snprintf(from, sizeof(from), "%s/result.txt", work);
    snprintf(to, sizeof(to), "%s/result.txt", dir);
    copy_file(from, to); /* absent when the child itself failed */
    snprintf(to, sizeof(to), "%s/REPRODUCE.txt", dir);
    FILE *f = fopen(to, "w");
    if (!f) { perror("fopen REPRODUCE.txt"); return; }
    fprintf(f, "seed 0x%016" PRIx64 "\n", seed);
    fprintf(f, "failing batch: programs %lld..%lld\n", first, end - 1);
    fprintf(f, "reproduce: make fuzz-run FUZZ_SEED=0x%016" PRIx64 " FUZZ_PROGRAMS=%lld%s\n",
            seed, end, negative ? " (with --negative-control)" : "");
    fprintf(f, "batch.txt is the batch the Lobster child read; result.txt is what it wrote.\n");
    fclose(f);
    fprintf(stderr, "failing inputs saved in %s\n", dir);
}

int main(int argc, char **argv) {
    const char *lobster = NULL, *driver = NULL, *tmpbase = NULL, *failures = NULL;
    int negative = 0;
    uint64_t seed = DEFAULT_SEED, programs = PROGRAMS, duration = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--lobster") == 0 && i + 1 < argc) lobster = argv[++i];
        else if (strcmp(argv[i], "--driver") == 0 && i + 1 < argc) driver = argv[++i];
        else if (strcmp(argv[i], "--tmp") == 0 && i + 1 < argc) tmpbase = argv[++i];
        else if (strcmp(argv[i], "--failures") == 0 && i + 1 < argc) failures = argv[++i];
        else if (strcmp(argv[i], "--negative-control") == 0) negative = 1;
        else if (strcmp(argv[i], "--seed") == 0 && i + 1 < argc) {
            if (!parse_u64(argv[++i], &seed)) { fprintf(stderr, "--seed %s is not an unsigned 64-bit integer\n", argv[i]); return 2; }
        } else if (strcmp(argv[i], "--programs") == 0 && i + 1 < argc) {
            if (!parse_u64(argv[++i], &programs) || programs > 1000000000ULL) { fprintf(stderr, "--programs %s is not a count up to 1e9\n", argv[i]); return 2; }
        } else if (strcmp(argv[i], "--duration") == 0 && i + 1 < argc) {
            if (!parse_u64(argv[++i], &duration) || duration > 604800ULL) { fprintf(stderr, "--duration %s is not seconds up to a week\n", argv[i]); return 2; }
        }
        else { fprintf(stderr, "unknown argument %s\n", argv[i]); return 2; }
    }
    if (!lobster || !driver || !tmpbase) {
        fprintf(stderr, "usage: host --lobster <path> --driver <path> --tmp <dir> [--negative-control]\n"
                        "            [--seed <u64>] [--programs <n>] [--duration <seconds>] [--failures <dir>]\n");
        return 2;
    }
    if (programs == 0 && duration == 0) {
        fprintf(stderr, "--programs 0 needs a --duration: the run would never end\n");
        return 2;
    }
    char tmpl[4096];
    snprintf(tmpl, sizeof(tmpl), "%s/workXXXXXX", tmpbase);
    if (!mkdtemp(tmpl)) { perror("mkdtemp"); return 1; }

    rng_state = seed;
    printf("RUN TestDifferentialAgainstSerializeC\n");
    printf("seed 0x%016" PRIx64 " programs %s%" PRIu64 " duration %" PRIu64 "s\n",
           seed, programs == 0 ? "unlimited/" : "", programs, duration);
    fflush(stdout);

    int widen_done = 0;
    int fail = 0;
    long long mutant_count = 0, done = 0;
    int targeted_count = 0;
    double t0 = now_seconds(), last_report = t0;
    static Program progs[BATCH];
    for (long long start = 0; ; start += BATCH) {
        if (programs != 0 && (uint64_t)start >= programs) break;
        if (duration != 0 && now_seconds() - t0 >= (double)duration) break;
        if (start > (long long)INT32_MAX - BATCH) break; /* program ids are int */
        int n = BATCH;
        if (programs != 0 && (uint64_t)(programs - (uint64_t)start) < (uint64_t)BATCH) n = (int)(programs - (uint64_t)start);
        for (int i = 0; i < n; i++) {
            gen_program(&progs[i], (int)(start + i));
            /* keep the C oracle's expected bytes in the program */
        }
        int m = run_batch(lobster, driver, tmpl, progs, n, negative, &widen_done, &targeted_count);
        if (m < 0) {
            fail = 1;
            fprintf(stderr, "failing batch: programs %lld..%lld, seed 0x%016" PRIx64 "; reproduce with --seed 0x%016" PRIx64 " --programs %lld\n",
                    start, start + n - 1, seed, seed, start + n);
            if (failures) save_failure(failures, tmpl, seed, start, start + n, negative);
            break;
        }
        mutant_count += m;
        done = start + n;
        if (duration != 0 && now_seconds() - last_report >= 60.0) {
            last_report = now_seconds();
            printf("  %lld programs, %lld mutants, %.0fs\n", done, mutant_count, last_report - t0);
            fflush(stdout);
        }
    }

    if (fail) {
        printf("--- FAIL TestDifferentialAgainstSerializeC (seed 0x%016" PRIx64 ")\n", seed);
        return 1;
    }
    printf("--- PASS TestDifferentialAgainstSerializeC: %lld programs, %lld mutants (%d targeted at ranged offsets, float exponents and string bytes); mutants refused by reason:", done, mutant_count, targeted_count);
    for (int k = 1; k <= (int)SERIALIZE_REFUSAL_NON_CANONICAL; k++) {
        if (refused_by_reason[k] > 0) printf(" %s %d", serialize_refusal_name((serialize_refusal_t)k), refused_by_reason[k]);
    }
    printf("\n");
    return 0;
}
