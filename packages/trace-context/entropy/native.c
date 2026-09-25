// Native twin of the WebCrypto adapter. It reads one word from the same host
// primitives as Base's IO.random_u32: arc4random_buf on macOS, which cannot
// fail, and getrandom on Linux, whose errno is returned as a structured
// failure with its strerror text. It uses the C effect interface documented
// by the pinned compiler (guide/EFFECTS.md); a compiler update must
// requalify it.
#ifdef __linux__
#include <sys/random.h>
#endif

static void read_u32_call(IoWork* w) {
#ifdef __APPLE__
  arc4random_buf(&w->word, sizeof(w->word));
  w->code = 0;
#else
  io_sys_end(w, getrandom(&w->word, sizeof(w->word), 0));
#endif
}

static Term read_u32_pack(Env e, IoWork* w) {
  return w->code ? io_fail(e, w->code, NULL) : io_done(e, w->word);
}

Term read_u32_run(Env e, Term* f, IoWork* w) {
  return io_work(w, read_u32_call, read_u32_pack);
}

static void __attribute__((constructor)) read_u32_use(void) {
  io_eff(CID_READ_U32, read_u32_run, 0);
}
