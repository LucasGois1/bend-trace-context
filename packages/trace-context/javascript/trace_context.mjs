// Generated from trace_context.bend by scripts/build-js.sh with bend 2.0.34.
// Do not edit: change the Bend sources and run the script again.
function word_to_u32(w) {
  let x = 0;
  for (let i = 0; w.$ === "WCon"; i++) {
    x |= Number(w.head) << i;
    w = w.tail;
  }
  return x >>> 0;
}

function u32_to_word(x) {
  let w = {$: "WNil"};
  for (let i = 31; i >= 0; i--) {
    w = {$: "WCon", head: ((x >>> i) & 1) === 1, tail: w};
  }
  return w;
}

function cmp_new(a, b) {
  return {$: a < b ? "LT"
    : a === b ? "EQ" : "GT"};
}

function nat_divmod(a, b) {
  return b === 0 ? {$: "Tuple", fst: 0, snd: a}
    : {$: "Tuple", fst: Math.trunc(a / b), snd: a % b};
}

function nat_chk(n) {
  if (n > 281474976710655) {
    throw "bend: a Nat past the largest immediate 2^48-1";
  }
  return n;
}

function nat_host(n) {
  const int = typeof n === "bigint" || Number.isInteger(n);
  if (int && n >= 0 && n <= 2 ** 53) {
    return Number(n);
  }
  return { [Symbol.toPrimitive]() { throw "bend: a Nat past the largest immediate 2^48-1"; } };
}

function f32_show(x) {
  if (x !== x) {
    return "nan";
  }
  if (!Number.isFinite(x) || Object.is(x, -0)) {
    return x < 0 ? "-inf"
      : x === 0 ? "-0" : "inf";
  }
  let s = "x";
  for (let p = 1; p <= 9 && f32_round(s) !== x; p += 1) {
    s = String(Number(x.toExponential(p - 1)));
  }
  return s;
}

function f32_bits(x) {
  return new Uint32Array(new Float32Array([x]).buffer)[0];
}

function f32_from_bits(u) {
  return new Float32Array(new Uint32Array([u]).buffer)[0];
}

function f32_read(s) {
  const re = /^\s*[+-]?((\d+\.?\d*|\.\d+)(e[+-]?\d+)?|inf(inity)?|nan)$/i;
  const v = f32_round(s.replace(/inf\w*/i, "Infinity"));
  return re.test(s) ? {$: "Some", value: v} : {$: "None"};
}

const f32_round = function f32_round(s) {
  const d = Number(s);
  const a = Math.abs(d);
  const f = Math.fround(a);
  const g = 2 * a - Math.min(f, 2 ** 128);
  if (g === f || Math.fround(g) !== g || g === Infinity) {
    return Math.sign(d) * f;
  }
  let k = 0;
  while (a * 2 ** k % 1 !== 0) {
    k += 1;
  }
  const [, i, r, e] = /(\d*)\.?(\d*)(?:e([+-]?\d+))?$/i.exec(s);
  const n = Number(e ?? 0) - r.length;
  const x = BigInt(i + r) * 2n ** BigInt(k) * 10n ** BigInt(Math.max(n, 0));
  const y = BigInt(a * 2 ** k) * 10n ** BigInt(Math.max(-n, 0));
  return Math.sign(d) * (x === y || x > y !== g > f ? f : g);
};

function char_new(code) {
  if (code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) {
    throw "bend: " + code + " is not a Unicode scalar value";
  }
  return String.fromCodePoint(code);
}

// Array
// =====

function array_new(d, v) {
  if (d > 31) {
    throw "bend: an array past the deepest block class 31";
  }
  return Array(2 ** d).fill(v);
}

function array_node(a, b) {
  if (a.length !== b.length) {
    throw "bend: runtime fail-stop";
  }
  return a.concat(b);
}

function array_rmw(a, i, f) {
  const at = i % a.length;
  const old = a[at];
  a[at] = f(old);
  return {$: "Tuple", fst: a, snd: old};
}

// Run
// ===

function run_tail(f, x) {
  return {$: "$JMP", f: f.j?.f === f ? f.j : f, x: [x]};
}

function run_clo(j) {
  const f = (x) => run_loop(j(x));
  f.j = j;
  j.f = f;
  return f;
}

function run_loop(r) {
  while (r !== null && typeof r === "object" && r.$ === "$JMP") {
    r = r.f(...r.x);
  }
  return r;
}

function run_lib(f, n) {
  return (...a) => a.length < n ? run_lib((...b) => f(...a, ...b), n - a.length)
    : f(...a);
}

// Effect
// ======

const $0eff = Object.create(null);

function io_eff(k, run, need) {
  if (k in $0eff) {
    throw new Error("bend: two effects register " + k);
  }
  $0eff[k] = { run, need };
}
// Program
// =======

function $src$047hex$Digit$to_char$(_digit_0) {
  if (_digit_0.$ === "src/hex.H0") {
    return "0";
  } else if (_digit_0.$ === "src/hex.H1") {
    return "1";
  } else if (_digit_0.$ === "src/hex.H2") {
    return "2";
  } else if (_digit_0.$ === "src/hex.H3") {
    return "3";
  } else if (_digit_0.$ === "src/hex.H4") {
    return "4";
  } else if (_digit_0.$ === "src/hex.H5") {
    return "5";
  } else if (_digit_0.$ === "src/hex.H6") {
    return "6";
  } else if (_digit_0.$ === "src/hex.H7") {
    return "7";
  } else if (_digit_0.$ === "src/hex.H8") {
    return "8";
  } else if (_digit_0.$ === "src/hex.H9") {
    return "9";
  } else if (_digit_0.$ === "src/hex.Ha") {
    return "a";
  } else if (_digit_0.$ === "src/hex.Hb") {
    return "b";
  } else if (_digit_0.$ === "src/hex.Hc") {
    return "c";
  } else if (_digit_0.$ === "src/hex.Hd") {
    return "d";
  } else if (_digit_0.$ === "src/hex.He") {
    return "e";
  } else {
    return "f";
  }
}

function $src$047hex$Digit$to_u32$(_digit_0) {
  if (_digit_0.$ === "src/hex.H0") {
    return 0;
  } else if (_digit_0.$ === "src/hex.H1") {
    return 1;
  } else if (_digit_0.$ === "src/hex.H2") {
    return 2;
  } else if (_digit_0.$ === "src/hex.H3") {
    return 3;
  } else if (_digit_0.$ === "src/hex.H4") {
    return 4;
  } else if (_digit_0.$ === "src/hex.H5") {
    return 5;
  } else if (_digit_0.$ === "src/hex.H6") {
    return 6;
  } else if (_digit_0.$ === "src/hex.H7") {
    return 7;
  } else if (_digit_0.$ === "src/hex.H8") {
    return 8;
  } else if (_digit_0.$ === "src/hex.H9") {
    return 9;
  } else if (_digit_0.$ === "src/hex.Ha") {
    return 10;
  } else if (_digit_0.$ === "src/hex.Hb") {
    return 11;
  } else if (_digit_0.$ === "src/hex.Hc") {
    return 12;
  } else if (_digit_0.$ === "src/hex.Hd") {
    return 13;
  } else if (_digit_0.$ === "src/hex.He") {
    return 14;
  } else {
    return 15;
  }
}

function $src$047hex$Digit$is_zero$(_digit_0) {
  if (_digit_0.$ === "src/hex.H0") {
    return true;
  } else if (_digit_0.$ === "src/hex.H1") {
    return false;
  } else if (_digit_0.$ === "src/hex.H2") {
    return false;
  } else if (_digit_0.$ === "src/hex.H3") {
    return false;
  } else if (_digit_0.$ === "src/hex.H4") {
    return false;
  } else if (_digit_0.$ === "src/hex.H5") {
    return false;
  } else if (_digit_0.$ === "src/hex.H6") {
    return false;
  } else if (_digit_0.$ === "src/hex.H7") {
    return false;
  } else if (_digit_0.$ === "src/hex.H8") {
    return false;
  } else if (_digit_0.$ === "src/hex.H9") {
    return false;
  } else if (_digit_0.$ === "src/hex.Ha") {
    return false;
  } else if (_digit_0.$ === "src/hex.Hb") {
    return false;
  } else if (_digit_0.$ === "src/hex.Hc") {
    return false;
  } else if (_digit_0.$ === "src/hex.Hd") {
    return false;
  } else if (_digit_0.$ === "src/hex.He") {
    return false;
  } else {
    return false;
  }
}

function $src$047hex$Digit$is_odd$(_digit_0) {
  if (_digit_0.$ === "src/hex.H0") {
    return false;
  } else if (_digit_0.$ === "src/hex.H1") {
    return true;
  } else if (_digit_0.$ === "src/hex.H2") {
    return false;
  } else if (_digit_0.$ === "src/hex.H3") {
    return true;
  } else if (_digit_0.$ === "src/hex.H4") {
    return false;
  } else if (_digit_0.$ === "src/hex.H5") {
    return true;
  } else if (_digit_0.$ === "src/hex.H6") {
    return false;
  } else if (_digit_0.$ === "src/hex.H7") {
    return true;
  } else if (_digit_0.$ === "src/hex.H8") {
    return false;
  } else if (_digit_0.$ === "src/hex.H9") {
    return true;
  } else if (_digit_0.$ === "src/hex.Ha") {
    return false;
  } else if (_digit_0.$ === "src/hex.Hb") {
    return true;
  } else if (_digit_0.$ === "src/hex.Hc") {
    return false;
  } else if (_digit_0.$ === "src/hex.Hd") {
    return true;
  } else if (_digit_0.$ === "src/hex.He") {
    return false;
  } else {
    return true;
  }
}

function $src$047hex$Digit$has_bit1$(_digit_0) {
  if (_digit_0.$ === "src/hex.H0") {
    return false;
  } else if (_digit_0.$ === "src/hex.H1") {
    return false;
  } else if (_digit_0.$ === "src/hex.H2") {
    return true;
  } else if (_digit_0.$ === "src/hex.H3") {
    return true;
  } else if (_digit_0.$ === "src/hex.H4") {
    return false;
  } else if (_digit_0.$ === "src/hex.H5") {
    return false;
  } else if (_digit_0.$ === "src/hex.H6") {
    return true;
  } else if (_digit_0.$ === "src/hex.H7") {
    return true;
  } else if (_digit_0.$ === "src/hex.H8") {
    return false;
  } else if (_digit_0.$ === "src/hex.H9") {
    return false;
  } else if (_digit_0.$ === "src/hex.Ha") {
    return true;
  } else if (_digit_0.$ === "src/hex.Hb") {
    return true;
  } else if (_digit_0.$ === "src/hex.Hc") {
    return false;
  } else if (_digit_0.$ === "src/hex.Hd") {
    return false;
  } else if (_digit_0.$ === "src/hex.He") {
    return true;
  } else {
    return true;
  }
}

function $src$047hex$Digit$has_bit2$(_digit_0) {
  if (_digit_0.$ === "src/hex.H0") {
    return false;
  } else if (_digit_0.$ === "src/hex.H1") {
    return false;
  } else if (_digit_0.$ === "src/hex.H2") {
    return false;
  } else if (_digit_0.$ === "src/hex.H3") {
    return false;
  } else if (_digit_0.$ === "src/hex.H4") {
    return true;
  } else if (_digit_0.$ === "src/hex.H5") {
    return true;
  } else if (_digit_0.$ === "src/hex.H6") {
    return true;
  } else if (_digit_0.$ === "src/hex.H7") {
    return true;
  } else if (_digit_0.$ === "src/hex.H8") {
    return false;
  } else if (_digit_0.$ === "src/hex.H9") {
    return false;
  } else if (_digit_0.$ === "src/hex.Ha") {
    return false;
  } else if (_digit_0.$ === "src/hex.Hb") {
    return false;
  } else if (_digit_0.$ === "src/hex.Hc") {
    return true;
  } else if (_digit_0.$ === "src/hex.Hd") {
    return true;
  } else if (_digit_0.$ === "src/hex.He") {
    return true;
  } else {
    return true;
  }
}

function $src$047hex$Digit$has_bit3$(_digit_0) {
  if (_digit_0.$ === "src/hex.H0") {
    return false;
  } else if (_digit_0.$ === "src/hex.H1") {
    return false;
  } else if (_digit_0.$ === "src/hex.H2") {
    return false;
  } else if (_digit_0.$ === "src/hex.H3") {
    return false;
  } else if (_digit_0.$ === "src/hex.H4") {
    return false;
  } else if (_digit_0.$ === "src/hex.H5") {
    return false;
  } else if (_digit_0.$ === "src/hex.H6") {
    return false;
  } else if (_digit_0.$ === "src/hex.H7") {
    return false;
  } else if (_digit_0.$ === "src/hex.H8") {
    return true;
  } else if (_digit_0.$ === "src/hex.H9") {
    return true;
  } else if (_digit_0.$ === "src/hex.Ha") {
    return true;
  } else if (_digit_0.$ === "src/hex.Hb") {
    return true;
  } else if (_digit_0.$ === "src/hex.Hc") {
    return true;
  } else if (_digit_0.$ === "src/hex.Hd") {
    return true;
  } else if (_digit_0.$ === "src/hex.He") {
    return true;
  } else {
    return true;
  }
}

function $src$047hex$Digit$from_bits$(_bit0_0, _bit1_0, _bit2_0, _bit3_0) {
  if (!_bit0_0) {
    if (!_bit1_0) {
      if (!_bit2_0) {
        if (!_bit3_0) {
          return {$: "src/hex.H0"};
        } else {
          return {$: "src/hex.H8"};
        }
      } else {
        if (!_bit3_0) {
          return {$: "src/hex.H4"};
        } else {
          return {$: "src/hex.Hc"};
        }
      }
    } else {
      if (!_bit2_0) {
        if (!_bit3_0) {
          return {$: "src/hex.H2"};
        } else {
          return {$: "src/hex.Ha"};
        }
      } else {
        if (!_bit3_0) {
          return {$: "src/hex.H6"};
        } else {
          return {$: "src/hex.He"};
        }
      }
    }
  } else {
    if (!_bit1_0) {
      if (!_bit2_0) {
        if (!_bit3_0) {
          return {$: "src/hex.H1"};
        } else {
          return {$: "src/hex.H9"};
        }
      } else {
        if (!_bit3_0) {
          return {$: "src/hex.H5"};
        } else {
          return {$: "src/hex.Hd"};
        }
      }
    } else {
      if (!_bit2_0) {
        if (!_bit3_0) {
          return {$: "src/hex.H3"};
        } else {
          return {$: "src/hex.Hb"};
        }
      } else {
        if (!_bit3_0) {
          return {$: "src/hex.H7"};
        } else {
          return {$: "src/hex.Hf"};
        }
      }
    }
  }
}

function $src$047hex$Digit$all$() {
  return {$: "Con", "head": {$: "src/hex.H0"}, "tail": {$: "Con", "head": {$: "src/hex.H1"}, "tail": {$: "Con", "head": {$: "src/hex.H2"}, "tail": {$: "Con", "head": {$: "src/hex.H3"}, "tail": {$: "Con", "head": {$: "src/hex.H4"}, "tail": {$: "Con", "head": {$: "src/hex.H5"}, "tail": {$: "Con", "head": {$: "src/hex.H6"}, "tail": {$: "Con", "head": {$: "src/hex.H7"}, "tail": {$: "Con", "head": {$: "src/hex.H8"}, "tail": {$: "Con", "head": {$: "src/hex.H9"}, "tail": {$: "Con", "head": {$: "src/hex.Ha"}, "tail": {$: "Con", "head": {$: "src/hex.Hb"}, "tail": {$: "Con", "head": {$: "src/hex.Hc"}, "tail": {$: "Con", "head": {$: "src/hex.Hd"}, "tail": {$: "Con", "head": {$: "src/hex.He"}, "tail": {$: "Con", "head": {$: "src/hex.Hf"}, "tail": {$: "Nil"}}}}}}}}}}}}}}}}};
}

function $src$047hex$Digit$from_char$find$(_digits_0, _char_0) {
  if (_digits_0.$ === "Nil") {
    return {$: "None"};
  } else {
    const _digit_0 = _digits_0["head"];
    const _tail_0 = _digits_0["tail"];
    return $Bool$pick$(($Char$is_eq$(_char_0, ($src$047hex$Digit$to_char$(_digit_0)))), {$: "Some", "value": _digit_0}, ($src$047hex$Digit$from_char$find$(_tail_0, _char_0)));
  }
}

function $src$047hex$Digit$from_char$(_char_0) {
  return $src$047hex$Digit$from_char$find$(($src$047hex$Digit$all$()), _char_0);
}

function $src$047digits$Digits$(_n_0) {
  if (_n_0 === 0) {
    return null;
  } else {
    return null;
  }
}

function $src$047digits$Digits$to_string$(_n_0, _digits_0) {
  if (_n_0 === 0) {
    return "";
  } else {
    const _p_0 = (_n_0 - 1);
    const _head_0 = _digits_0["head"];
    const _tail_0 = _digits_0["tail"];
    return (($src$047hex$Digit$to_char$(_head_0)) + ($src$047digits$Digits$to_string$(_p_0, _tail_0)));
  }
}

function $src$047digits$Digits$is_zero$(_n_0, _digits_0) {
  if (_n_0 === 0) {
    return true;
  } else {
    const _p_0 = (_n_0 - 1);
    const _head_0 = _digits_0["head"];
    const _tail_0 = _digits_0["tail"];
    return $Bool$and$(($src$047hex$Digit$is_zero$(_head_0)), ($src$047digits$Digits$is_zero$(_p_0, _tail_0)));
  }
}

function $src$047digits$Digits$of_u32$(_word_0) {
  const _b0_0 = u32_to_word(_word_0)["head"];
  const _t_0 = u32_to_word(_word_0)["tail"];
  const _b1_0 = _t_0["head"];
  const _t_1 = _t_0["tail"];
  const _b2_0 = _t_1["head"];
  const _t_2 = _t_1["tail"];
  const _b3_0 = _t_2["head"];
  const _t_3 = _t_2["tail"];
  const _b4_0 = _t_3["head"];
  const _t_4 = _t_3["tail"];
  const _b5_0 = _t_4["head"];
  const _t_5 = _t_4["tail"];
  const _b6_0 = _t_5["head"];
  const _t_6 = _t_5["tail"];
  const _b7_0 = _t_6["head"];
  const _t_7 = _t_6["tail"];
  const _b8_0 = _t_7["head"];
  const _t_8 = _t_7["tail"];
  const _b9_0 = _t_8["head"];
  const _t_9 = _t_8["tail"];
  const _b10_0 = _t_9["head"];
  const _t_10 = _t_9["tail"];
  const _b11_0 = _t_10["head"];
  const _t_11 = _t_10["tail"];
  const _b12_0 = _t_11["head"];
  const _t_12 = _t_11["tail"];
  const _b13_0 = _t_12["head"];
  const _t_13 = _t_12["tail"];
  const _b14_0 = _t_13["head"];
  const _t_14 = _t_13["tail"];
  const _b15_0 = _t_14["head"];
  const _t_15 = _t_14["tail"];
  const _b16_0 = _t_15["head"];
  const _t_16 = _t_15["tail"];
  const _b17_0 = _t_16["head"];
  const _t_17 = _t_16["tail"];
  const _b18_0 = _t_17["head"];
  const _t_18 = _t_17["tail"];
  const _b19_0 = _t_18["head"];
  const _t_19 = _t_18["tail"];
  const _b20_0 = _t_19["head"];
  const _t_20 = _t_19["tail"];
  const _b21_0 = _t_20["head"];
  const _t_21 = _t_20["tail"];
  const _b22_0 = _t_21["head"];
  const _t_22 = _t_21["tail"];
  const _b23_0 = _t_22["head"];
  const _t_23 = _t_22["tail"];
  const _b24_0 = _t_23["head"];
  const _t_24 = _t_23["tail"];
  const _b25_0 = _t_24["head"];
  const _t_25 = _t_24["tail"];
  const _b26_0 = _t_25["head"];
  const _t_26 = _t_25["tail"];
  const _b27_0 = _t_26["head"];
  const _t_27 = _t_26["tail"];
  const _b28_0 = _t_27["head"];
  const _t_28 = _t_27["tail"];
  const _b29_0 = _t_28["head"];
  const _t_29 = _t_28["tail"];
  const _b30_0 = _t_29["head"];
  const _t_30 = _t_29["tail"];
  const _b31_0 = _t_30["head"];
  const _t_31 = _t_30["tail"];
  return {$: "src/digits.DCon", "head": ($src$047hex$Digit$from_bits$(_b28_0, _b29_0, _b30_0, _b31_0)), "tail": {$: "src/digits.DCon", "head": ($src$047hex$Digit$from_bits$(_b24_0, _b25_0, _b26_0, _b27_0)), "tail": {$: "src/digits.DCon", "head": ($src$047hex$Digit$from_bits$(_b20_0, _b21_0, _b22_0, _b23_0)), "tail": {$: "src/digits.DCon", "head": ($src$047hex$Digit$from_bits$(_b16_0, _b17_0, _b18_0, _b19_0)), "tail": {$: "src/digits.DCon", "head": ($src$047hex$Digit$from_bits$(_b12_0, _b13_0, _b14_0, _b15_0)), "tail": {$: "src/digits.DCon", "head": ($src$047hex$Digit$from_bits$(_b8_0, _b9_0, _b10_0, _b11_0)), "tail": {$: "src/digits.DCon", "head": ($src$047hex$Digit$from_bits$(_b4_0, _b5_0, _b6_0, _b7_0)), "tail": {$: "src/digits.DCon", "head": ($src$047hex$Digit$from_bits$(_b0_0, _b1_0, _b2_0, _b3_0)), "tail": {$: "src/digits.DNil"}}}}}}}}};
}

function $src$047digits$Digits$to_u32$(_digits_0) {
  const _d7_0 = _digits_0["head"];
  const _t_0 = _digits_0["tail"];
  const _d6_0 = _t_0["head"];
  const _t_1 = _t_0["tail"];
  const _d5_0 = _t_1["head"];
  const _t_2 = _t_1["tail"];
  const _d4_0 = _t_2["head"];
  const _t_3 = _t_2["tail"];
  const _d3_0 = _t_3["head"];
  const _t_4 = _t_3["tail"];
  const _d2_0 = _t_4["head"];
  const _t_5 = _t_4["tail"];
  const _d1_0 = _t_5["head"];
  const _t_6 = _t_5["tail"];
  const _d0_0 = _t_6["head"];
  const _t_7 = _t_6["tail"];
  return word_to_u32({$: "WCon", "head": ($src$047hex$Digit$is_odd$(_d0_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit1$(_d0_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit2$(_d0_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit3$(_d0_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$is_odd$(_d1_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit1$(_d1_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit2$(_d1_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit3$(_d1_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$is_odd$(_d2_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit1$(_d2_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit2$(_d2_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit3$(_d2_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$is_odd$(_d3_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit1$(_d3_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit2$(_d3_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit3$(_d3_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$is_odd$(_d4_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit1$(_d4_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit2$(_d4_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit3$(_d4_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$is_odd$(_d5_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit1$(_d5_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit2$(_d5_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit3$(_d5_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$is_odd$(_d6_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit1$(_d6_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit2$(_d6_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit3$(_d6_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$is_odd$(_d7_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit1$(_d7_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit2$(_d7_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit3$(_d7_0)), "tail": {$: "WNil"}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}});
}

function $src$047digits$Digits$to_byte$(_digits_0) {
  const _high_0 = _digits_0["head"];
  const _t_0 = _digits_0["tail"];
  const _low_0 = _t_0["head"];
  const _t_1 = _t_0["tail"];
  return word_to_u32({$: "WCon", "head": ($src$047hex$Digit$is_odd$(_low_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit1$(_low_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit2$(_low_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit3$(_low_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$is_odd$(_high_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit1$(_high_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit2$(_high_0)), "tail": {$: "WCon", "head": ($src$047hex$Digit$has_bit3$(_high_0)), "tail": ($Word$zero$(24))}}}}}}}});
}

function $src$047digits$Digits$of_byte$(_byte_0) {
  const _b0_0 = u32_to_word(_byte_0)["head"];
  const _t_0 = u32_to_word(_byte_0)["tail"];
  const _b1_0 = _t_0["head"];
  const _t_1 = _t_0["tail"];
  const _b2_0 = _t_1["head"];
  const _t_2 = _t_1["tail"];
  const _b3_0 = _t_2["head"];
  const _t_3 = _t_2["tail"];
  const _b4_0 = _t_3["head"];
  const _t_4 = _t_3["tail"];
  const _b5_0 = _t_4["head"];
  const _t_5 = _t_4["tail"];
  const _b6_0 = _t_5["head"];
  const _t_6 = _t_5["tail"];
  const _b7_0 = _t_6["head"];
  return {$: "src/digits.DCon", "head": ($src$047hex$Digit$from_bits$(_b4_0, _b5_0, _b6_0, _b7_0)), "tail": {$: "src/digits.DCon", "head": ($src$047hex$Digit$from_bits$(_b0_0, _b1_0, _b2_0, _b3_0)), "tail": {$: "src/digits.DNil"}}};
}

function $src$047digits$Digits$to_bytes$(_n_0, _digits_0) {
  if (_n_0 === 0) {
    return {$: "Nil"};
  } else {
    const _p_0 = (_n_0 - 1);
    const _high_0 = _digits_0["head"];
    const _t_0 = _digits_0["tail"];
    const _low_0 = _t_0["head"];
    const _rest_0 = _t_0["tail"];
    return {$: "Con", "head": ($src$047digits$Digits$to_byte$({$: "src/digits.DCon", "head": _high_0, "tail": {$: "src/digits.DCon", "head": _low_0, "tail": {$: "src/digits.DNil"}}})), "tail": ($src$047digits$Digits$to_bytes$(_p_0, _rest_0))};
  }
}

function $src$047digits$Digits$append$(_m_0, _left_0, _right_0) {
  if (_m_0 === 0) {
    return _right_0;
  } else {
    const _p_0 = (_m_0 - 1);
    const _head_0 = _left_0["head"];
    const _tail_0 = _left_0["tail"];
    return {$: "src/digits.DCon", "head": _head_0, "tail": ($src$047digits$Digits$append$(_p_0, _tail_0, _right_0))};
  }
}

function $src$047digits$NonZero$new$checked$(_digits_0, _status_0, _evidence_0) {
  if (_status_0) {
    return {$: "None"};
  } else {
    return {$: "Some", "value": {$: "src/digits.NonZero", "digits": _digits_0, "evidence": _evidence_0}};
  }
}

function $src$047digits$NonZero$new$(_n_0, _digits_0) {
  return $src$047digits$NonZero$new$checked$(_digits_0, ($src$047digits$Digits$is_zero$(_n_0, _digits_0)), null);
}

function $src$047digits$NonZero$digits$(_value_0) {
  const _digits_0 = _value_0["digits"];
  return _digits_0;
}

function $src$047digits$NonZero$to_string$(_n_0, _value_0) {
  return $src$047digits$Digits$to_string$(_n_0, ($src$047digits$NonZero$digits$(_value_0)));
}

function $Parsed$prepend$(_digit_0, _parsed_0) {
  const _digits_0 = _parsed_0["digits"];
  const _rest_0 = _parsed_0["rest"];
  return {$: "Parsed", "digits": {$: "src/digits.DCon", "head": _digit_0, "tail": _digits_0}, "rest": _rest_0};
}

function $Parse$digit_result$(_value_0, _offset_0) {
  if (_value_0.$ === "None") {
    return {$: "Fail", "error": {$: "InvalidHex", "offset": _offset_0}};
  } else {
    const _digit_0 = _value_0["value"];
    return {$: "Done", "value": _digit_0};
  }
}

function $Parse$digit$(_char_0, _offset_0) {
  return $Parse$digit_result$(($src$047hex$Digit$from_char$(_char_0)), _offset_0);
}

function $Parse$digits$(_n_0, _text_0, _offset_0) {
  if (_n_0 === 0) {
    return {$: "Done", "value": {$: "Parsed", "digits": {$: "src/digits.DNil"}, "rest": _text_0}};
  } else {
    const _p_0 = (_n_0 - 1);
    if (_text_0 === "") {
      return {$: "Fail", "error": {$: "UnexpectedEnd", "offset": _offset_0}};
    } else {
      const _char_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(0, 2) : _text_0[0]);
      const _tail_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(2) : _text_0.slice(1));
      const _at_0 = _offset_0;
      return $Result$bind$(($Parse$digit$(_char_0, _at_0)), run_clo((_x_0) => {
  return $Result$bind$(run_loop($Parse$digits$(_p_0, _tail_0, nat_chk(_at_0 + 1))), run_clo((_x_1) => {
  return $Result$pure$(($Parsed$prepend$(_x_0, _x_1)));
}));
}));
    }
  }
}

function $Parse$separator_result$(_tail_0, _ok_0, _offset_0) {
  if (!_ok_0) {
    return {$: "Fail", "error": {$: "ExpectedSeparator", "offset": _offset_0}};
  } else {
    return {$: "Done", "value": _tail_0};
  }
}

function $Parse$separator$(_text_0, _offset_0) {
  if (_text_0 === "") {
    return {$: "Fail", "error": {$: "UnexpectedEnd", "offset": _offset_0}};
  } else {
    const _char_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(0, 2) : _text_0[0]);
    const _tail_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(2) : _text_0.slice(1));
    return $Parse$separator_result$(_tail_0, ($Char$is_eq$(_char_0, "-")), _offset_0);
  }
}

function $Parse$end$(_text_0) {
  if (_text_0 === "") {
    return {$: "Done", "value": {$: "Unit"}};
  } else {
    return {$: "Fail", "error": {$: "TrailingInput"}};
  }
}

function $Parse$version$(_digits_0) {
  const _t_0 = _digits_0["head"];
  if (_t_0.$ === "src/hex.H0") {
    const _t_1 = _digits_0["tail"];
    const _t_2 = _t_1["head"];
    if (_t_2.$ === "src/hex.H0") {
      const _t_3 = _t_1["tail"];
      return {$: "Done", "value": {$: "Unit"}};
    } else {
      const _9_0 = _t_1["tail"];
      return {$: "Fail", "error": {$: "UnsupportedVersion", "version": ($src$047digits$Digits$to_string$(2, {$: "src/digits.DCon", "head": {$: "src/hex.H0"}, "tail": {$: "src/digits.DCon", "head": _t_2, "tail": _9_0}}))}};
    }
  } else if (_t_0.$ === "src/hex.Hf") {
    const _t_4 = _digits_0["tail"];
    const _t_5 = _t_4["head"];
    if (_t_5.$ === "src/hex.Hf") {
      const _t_6 = _t_4["tail"];
      return {$: "Fail", "error": {$: "ForbiddenVersion"}};
    } else {
      const _11_0 = _t_4["tail"];
      return {$: "Fail", "error": {$: "UnsupportedVersion", "version": ($src$047digits$Digits$to_string$(2, {$: "src/digits.DCon", "head": {$: "src/hex.Hf"}, "tail": {$: "src/digits.DCon", "head": _t_5, "tail": _11_0}}))}};
    }
  } else {
    const _7_0 = _digits_0["tail"];
    return {$: "Fail", "error": {$: "UnsupportedVersion", "version": ($src$047digits$Digits$to_string$(2, {$: "src/digits.DCon", "head": _t_0, "tail": _7_0}))}};
  }
}

function $Parse$nonzero_result$(_result_0, _field_0) {
  if (_result_0.$ === "None") {
    return {$: "Fail", "error": {$: "ZeroId", "field": _field_0}};
  } else {
    const _id_0 = _result_0["value"];
    return {$: "Done", "value": _id_0};
  }
}

function $Parse$nonzero$(_n_0, _digits_0, _field_0) {
  return $Parse$nonzero_result$(($src$047digits$NonZero$new$(_n_0, _digits_0)), _field_0);
}

function $Parse$flags$(_trace_id_0, _parent_id_0, _parsed_0) {
  const _flags_0 = _parsed_0["digits"];
  const _rest_0 = _parsed_0["rest"];
  return $Result$bind$(($Parse$end$(_rest_0)), run_clo((_x_0) => {
  return $Result$pure$({$: "TraceParentV00", "trace_id": _trace_id_0, "parent_id": _parent_id_0, "flags": _flags_0});
}));
}

function $Parse$parent$(_trace_id_0, _parsed_0) {
  const _parent_digits_0 = _parsed_0["digits"];
  const _rest_0 = _parsed_0["rest"];
  return $Result$bind$(($Parse$nonzero$(16, _parent_digits_0, {$: "ParentIdField"})), run_clo((_x_0) => {
  return $Result$bind$(($Parse$separator$(_rest_0, 52)), run_clo((_x_1) => {
  return $Result$bind$(run_loop($Parse$digits$(2, _x_1, 53)), run_clo((_x_2) => {
  return $Parse$flags$(_trace_id_0, _x_0, _x_2);
}));
}));
}));
}

function $Parse$trace$(_parsed_0) {
  const _trace_digits_0 = _parsed_0["digits"];
  const _rest_0 = _parsed_0["rest"];
  return $Result$bind$(($Parse$nonzero$(32, _trace_digits_0, {$: "TraceIdField"})), run_clo((_x_0) => {
  return $Result$bind$(($Parse$separator$(_rest_0, 35)), run_clo((_x_1) => {
  return $Result$bind$(run_loop($Parse$digits$(16, _x_1, 36)), run_clo((_x_2) => {
  return $Parse$parent$(_x_0, _x_2);
}));
}));
}));
}

function $Parse$start$(_parsed_0) {
  const _version_0 = _parsed_0["digits"];
  const _rest_0 = _parsed_0["rest"];
  return $Result$bind$(($Parse$version$(_version_0)), run_clo((_x_0) => {
  return $Result$bind$(($Parse$separator$(_rest_0, 2)), run_clo((_x_1) => {
  return $Result$bind$(run_loop($Parse$digits$(32, _x_1, 3)), run_clo((_x_2) => {
  return $Parse$trace$(_x_2);
}));
}));
}));
}

function $TraceParentV00$parse$(_text_0) {
  return $Result$bind$(run_loop($Parse$digits$(2, _text_0, 0)), run_clo((_x_0) => {
  return $Parse$start$(_x_0);
}));
}

function $TraceParentV00$format$(_context_0) {
  const _trace_id_0 = _context_0["trace_id"];
  const _parent_id_0 = _context_0["parent_id"];
  const _flags_0 = _context_0["flags"];
  const _x_0 = ($src$047digits$Digits$to_string$(2, _flags_0));
  const _x_1 = ($src$047digits$NonZero$to_string$(16, _parent_id_0));
  const _x_2 = ("-" + _x_0);
  const _x_3 = (_x_1 + _x_2);
  const _x_4 = ($src$047digits$NonZero$to_string$(32, _trace_id_0));
  const _x_5 = ("-" + _x_3);
  const _x_6 = (_x_4 + _x_5);
  return ("00-" + _x_6);
}

function $TraceParentV00$is_sampled$(_context_0) {
  const _t_0 = _context_0["flags"];
  const _t_1 = _t_0["tail"];
  const _low_0 = _t_1["head"];
  const _t_2 = _t_1["tail"];
  return $src$047hex$Digit$is_odd$(_low_0);
}

function $TraceParentV00$is_random$(_context_0) {
  const _t_0 = _context_0["flags"];
  const _t_1 = _t_0["tail"];
  const _low_0 = _t_1["head"];
  const _t_2 = _t_1["tail"];
  return $src$047hex$Digit$has_bit1$(_low_0);
}

function $Parse$id$finish$(_n_0, _parsed_0, _field_0) {
  const _digits_0 = _parsed_0["digits"];
  const _rest_0 = _parsed_0["rest"];
  return $Result$bind$(($Parse$end$(_rest_0)), run_clo((_x_0) => {
  return $Parse$nonzero$(_n_0, _digits_0, _field_0);
}));
}

function $Parse$id$(_n_0, _text_0, _field_0) {
  return $Result$bind$(run_loop($Parse$digits$(_n_0, _text_0, 0)), run_clo((_x_0) => {
  return $Parse$id$finish$(_n_0, _x_0, _field_0);
}));
}

function $TraceId$parse$(_text_0) {
  return $Result$bind$(run_loop($Parse$id$(32, _text_0, {$: "TraceIdField"})), run_clo((_x_0) => {
  return $Result$pure$({$: "TraceId", "value": _x_0, "random": false});
}));
}

function $TraceId$assert_random$(_id_0) {
  const _value_0 = _id_0["value"];
  return {$: "TraceId", "value": _value_0, "random": true};
}

function $TraceId$is_random$(_id_0) {
  const _random_0 = _id_0["random"];
  return _random_0;
}

function $TraceId$to_string$(_id_0) {
  const _value_0 = _id_0["value"];
  return $src$047digits$NonZero$to_string$(32, _value_0);
}

function $TraceId$is_eq$(_a_0, _b_0) {
  return $String$eq$(($TraceId$to_string$(_a_0)), ($TraceId$to_string$(_b_0)));
}

function $SpanId$parse$(_text_0) {
  return $Result$bind$(run_loop($Parse$id$(16, _text_0, {$: "SpanIdField"})), run_clo((_x_0) => {
  return $Result$pure$({$: "SpanId", "value": _x_0});
}));
}

function $SpanId$to_string$(_id_0) {
  const _value_0 = _id_0["value"];
  return $src$047digits$NonZero$to_string$(16, _value_0);
}

function $SpanId$is_eq$(_a_0, _b_0) {
  return $String$eq$(($SpanId$to_string$(_a_0)), ($SpanId$to_string$(_b_0)));
}

function $Sampling$resolve$(_sampling_0, _inherited_0) {
  if (_sampling_0.$ === "InheritSampled") {
    return _inherited_0;
  } else {
    const _sampled_0 = _sampling_0["sampled"];
    return _sampled_0;
  }
}

function $RemoteContext$from_traceparent$(_value_0) {
  const _trace_id_0 = _value_0["trace_id"];
  const _parent_id_0 = _value_0["parent_id"];
  const _t_0 = _value_0["flags"];
  const _t_1 = _t_0["tail"];
  const _low_0 = _t_1["head"];
  const _t_2 = _t_1["tail"];
  return {$: "RemoteContext", "trace_id": {$: "TraceId", "value": _trace_id_0, "random": ($src$047hex$Digit$has_bit1$(_low_0))}, "span_id": {$: "SpanId", "value": _parent_id_0}, "sampled": ($src$047hex$Digit$is_odd$(_low_0))};
}

function $RemoteContext$from_ids$(_trace_id_0, _span_id_0, _sampled_0) {
  return {$: "RemoteContext", "trace_id": _trace_id_0, "span_id": _span_id_0, "sampled": _sampled_0};
}

function $RemoteContext$trace_id$(_context_0) {
  const _trace_id_0 = _context_0["trace_id"];
  return _trace_id_0;
}

function $RemoteContext$span_id$(_context_0) {
  const _span_id_0 = _context_0["span_id"];
  return _span_id_0;
}

function $RemoteContext$is_sampled$(_context_0) {
  const _sampled_0 = _context_0["sampled"];
  return _sampled_0;
}

function $Flags$known$(_sampled_0, _random_0) {
  const _x_0 = ($Bool$to_u32$(_random_0));
  const _x_1 = ($Bool$to_u32$(_sampled_0));
  const _x_2 = ((_x_0 << 1) >>> 0);
  return ((_x_1 | _x_2) >>> 0);
}

function $RemoteContext$flags$(_context_0) {
  const _trace_id_0 = _context_0["trace_id"];
  const _sampled_0 = _context_0["sampled"];
  return $Flags$known$(_sampled_0, ($TraceId$is_random$(_trace_id_0)));
}

function $LocalContext$trace_id$(_context_0) {
  const _trace_id_0 = _context_0["trace_id"];
  return _trace_id_0;
}

function $LocalContext$span_id$(_context_0) {
  const _span_id_0 = _context_0["span_id"];
  return _span_id_0;
}

function $LocalContext$is_sampled$(_context_0) {
  const _sampled_0 = _context_0["sampled"];
  return _sampled_0;
}

function $LocalContext$to_traceparent$(_context_0) {
  const _t_0 = _context_0["trace_id"];
  const _trace_id_0 = _t_0["value"];
  const _random_0 = _t_0["random"];
  const _t_1 = _context_0["span_id"];
  const _span_id_0 = _t_1["value"];
  const _sampled_0 = _context_0["sampled"];
  return {$: "TraceParentV00", "trace_id": _trace_id_0, "parent_id": _span_id_0, "flags": {$: "src/digits.DCon", "head": {$: "src/hex.H0"}, "tail": {$: "src/digits.DCon", "head": ($src$047hex$Digit$from_bits$(_sampled_0, _random_0, false, false)), "tail": {$: "src/digits.DNil"}}}};
}

function $LocalContext$flags$(_context_0) {
  const _trace_id_0 = _context_0["trace_id"];
  const _sampled_0 = _context_0["sampled"];
  return $Flags$known$(_sampled_0, ($TraceId$is_random$(_trace_id_0)));
}

function $Parent$trace_id$(_parent_0) {
  if (_parent_0.$ === "RemoteParent") {
    const _context_0 = _parent_0["context"];
    return $RemoteContext$trace_id$(_context_0);
  } else {
    const _context_1 = _parent_0["context"];
    return $LocalContext$trace_id$(_context_1);
  }
}

function $Parent$span_id$(_parent_0) {
  if (_parent_0.$ === "RemoteParent") {
    const _context_0 = _parent_0["context"];
    return $RemoteContext$span_id$(_context_0);
  } else {
    const _context_1 = _parent_0["context"];
    return $LocalContext$span_id$(_context_1);
  }
}

function $Parent$is_sampled$(_parent_0) {
  if (_parent_0.$ === "RemoteParent") {
    const _context_0 = _parent_0["context"];
    return $RemoteContext$is_sampled$(_context_0);
  } else {
    const _context_1 = _parent_0["context"];
    return $LocalContext$is_sampled$(_context_1);
  }
}

function $Context$from_ids$(_trace_id_0, _span_id_0, _sampled_0) {
  return {$: "LocalContext", "trace_id": _trace_id_0, "span_id": _span_id_0, "sampled": _sampled_0};
}

function $Context$root_from_ids$(_trace_id_0, _span_id_0, _sampled_0) {
  return $Context$from_ids$(_trace_id_0, _span_id_0, _sampled_0);
}

function $Context$child_from_id$checked$(_trace_id_0, _span_id_0, _sampled_0, _reused_0) {
  if (_reused_0) {
    return {$: "Fail", "error": {$: "ReusedSpanId"}};
  } else {
    return {$: "Done", "value": ($Context$from_ids$(_trace_id_0, _span_id_0, _sampled_0))};
  }
}

function $Context$child_from_id$(_parent_0, _span_id_0, _sampling_0) {
  return $Context$child_from_id$checked$(($Parent$trace_id$(_parent_0)), _span_id_0, ($Sampling$resolve$(_sampling_0, ($Parent$is_sampled$(_parent_0)))), ($SpanId$is_eq$(_span_id_0, ($Parent$span_id$(_parent_0)))));
}

function $Context$restart_from_ids$checked$(_trace_id_0, _span_id_0, _sampled_0, _reused_0) {
  if (_reused_0) {
    return {$: "Fail", "error": {$: "ReusedTraceId"}};
  } else {
    return {$: "Done", "value": ($Context$root_from_ids$(_trace_id_0, _span_id_0, _sampled_0))};
  }
}

function $Context$restart_from_ids$(_previous_0, _trace_id_0, _span_id_0, _sampled_0) {
  return $Context$restart_from_ids$checked$(_trace_id_0, _span_id_0, _sampled_0, ($TraceId$is_eq$(_trace_id_0, ($RemoteContext$trace_id$(_previous_0)))));
}

function $U32$to_hex$(_word_0) {
  return $src$047digits$Digits$to_string$(8, ($src$047digits$Digits$of_u32$(_word_0)));
}

function $TraceId$from_digits$(_value_0) {
  if (_value_0.$ === "None") {
    return {$: "None"};
  } else {
    const _digits_0 = _value_0["value"];
    return {$: "Some", "value": {$: "TraceId", "value": _digits_0, "random": false}};
  }
}

function $TraceId$from_words$(_first_0, _second_0, _third_0, _fourth_0) {
  return $TraceId$from_digits$(($src$047digits$NonZero$new$(32, ($src$047digits$Digits$append$(8, ($src$047digits$Digits$of_u32$(_first_0)), ($src$047digits$Digits$append$(8, ($src$047digits$Digits$of_u32$(_second_0)), ($src$047digits$Digits$append$(8, ($src$047digits$Digits$of_u32$(_third_0)), ($src$047digits$Digits$of_u32$(_fourth_0)))))))))));
}

function $SpanId$from_digits$(_value_0) {
  if (_value_0.$ === "None") {
    return {$: "None"};
  } else {
    const _digits_0 = _value_0["value"];
    return {$: "Some", "value": {$: "SpanId", "value": _digits_0}};
  }
}

function $SpanId$from_words$(_first_0, _second_0) {
  return $SpanId$from_digits$(($src$047digits$NonZero$new$(16, ($src$047digits$Digits$append$(8, ($src$047digits$Digits$of_u32$(_first_0)), ($src$047digits$Digits$of_u32$(_second_0)))))));
}

function $ParsedBytes$prepend$(_digits_0, _parsed_0) {
  const _high_0 = _digits_0["head"];
  const _t_0 = _digits_0["tail"];
  const _low_0 = _t_0["head"];
  const _t_1 = _t_0["tail"];
  const _rest_digits_0 = _parsed_0["digits"];
  const _rest_0 = _parsed_0["rest"];
  return {$: "ParsedBytes", "digits": {$: "src/digits.DCon", "head": _high_0, "tail": {$: "src/digits.DCon", "head": _low_0, "tail": _rest_digits_0}}, "rest": _rest_0};
}

function $Parse$byte$checked$(_cell_0, _above_0, _offset_0) {
  if (_above_0) {
    return {$: "Fail", "error": {$: "InvalidByte", "offset": _offset_0}};
  } else {
    return {$: "Done", "value": ($src$047digits$Digits$of_byte$(_cell_0))};
  }
}

function $Parse$byte$(_cell_0, _offset_0) {
  return $Parse$byte$checked$(_cell_0, (_cell_0 > 255), _offset_0);
}

function $Parse$bytes$(_n_0, _bytes_0, _offset_0) {
  if (_n_0 === 0) {
    return {$: "Done", "value": {$: "ParsedBytes", "digits": {$: "src/digits.DNil"}, "rest": _bytes_0}};
  } else {
    const _p_0 = (_n_0 - 1);
    if (_bytes_0.$ === "Nil") {
      return {$: "Fail", "error": {$: "UnexpectedEnd", "offset": _offset_0}};
    } else {
      const _cell_0 = _bytes_0["head"];
      const _tail_0 = _bytes_0["tail"];
      const _at_0 = _offset_0;
      return $Result$bind$(($Parse$byte$(_cell_0, _at_0)), run_clo((_x_0) => {
  return $Result$bind$(run_loop($Parse$bytes$(_p_0, _tail_0, nat_chk(_at_0 + 1))), run_clo((_x_1) => {
  return $Result$pure$(($ParsedBytes$prepend$(_x_0, _x_1)));
}));
}));
    }
  }
}

function $Parse$bytes_end$(_bytes_0) {
  if (_bytes_0.$ === "Nil") {
    return {$: "Done", "value": {$: "Unit"}};
  } else {
    return {$: "Fail", "error": {$: "TrailingInput"}};
  }
}

function $Parse$id_bytes$finish$(_n_0, _parsed_0, _field_0) {
  const _digits_0 = _parsed_0["digits"];
  const _rest_0 = _parsed_0["rest"];
  return $Result$bind$(($Parse$bytes_end$(_rest_0)), run_clo((_x_0) => {
  return $Parse$nonzero$(nat_chk(_n_0 + _n_0), _digits_0, _field_0);
}));
}

function $Parse$id_bytes$(_n_0, _bytes_0, _field_0) {
  return $Result$bind$(run_loop($Parse$bytes$(_n_0, _bytes_0, 0)), run_clo((_x_0) => {
  return $Parse$id_bytes$finish$(_n_0, _x_0, _field_0);
}));
}

function $TraceId$to_bytes$(_id_0) {
  const _value_0 = _id_0["value"];
  return $src$047digits$Digits$to_bytes$(16, ($src$047digits$NonZero$digits$(_value_0)));
}

function $TraceId$from_bytes$(_bytes_0) {
  return $Result$bind$(run_loop($Parse$id_bytes$(16, _bytes_0, {$: "TraceIdField"})), run_clo((_x_0) => {
  return $Result$pure$({$: "TraceId", "value": _x_0, "random": false});
}));
}

function $SpanId$to_bytes$(_id_0) {
  const _value_0 = _id_0["value"];
  return $src$047digits$Digits$to_bytes$(8, ($src$047digits$NonZero$digits$(_value_0)));
}

function $SpanId$from_bytes$(_bytes_0) {
  return $Result$bind$(run_loop($Parse$id_bytes$(8, _bytes_0, {$: "SpanIdField"})), run_clo((_x_0) => {
  return $Result$pure$({$: "SpanId", "value": _x_0});
}));
}

function $Draw$asserted$(_candidate_0) {
  if (_candidate_0.$ === "None") {
    return {$: "None"};
  } else {
    const _id_0 = _candidate_0["value"];
    return {$: "Some", "value": ($TraceId$assert_random$(_id_0))};
  }
}

function $Tape$next$(_tape_0) {
  if (_tape_0.$ === "Nil") {
    return {$: "Tuple", "fst": {$: "Nil"}, "snd": {$: "Fail", "error": {$: "Tuple", "fst": 1, "snd": "tape-exhausted"}}};
  } else {
    const _word_0 = _tape_0["head"];
    const _rest_0 = _tape_0["tail"];
    return {$: "Tuple", "fst": _rest_0, "snd": _word_0};
  }
}

function $TraceDraw$start$(_excluded_0) {
  return {$: "NeedTraceWord", "draw": {$: "TraceDraw", "remaining": 7, "words": {$: "NoTraceWord"}, "excluded": _excluded_0}};
}

function $TraceDraw$retry$(_remaining_0, _excluded_0) {
  if (_remaining_0 === 0) {
    return {$: "TraceFailed", "error": {$: "ExhaustedTraceId"}};
  } else {
    const _p_0 = (_remaining_0 - 1);
    return {$: "NeedTraceWord", "draw": {$: "TraceDraw", "remaining": _p_0, "words": {$: "NoTraceWord"}, "excluded": _excluded_0}};
  }
}

function $TraceDraw$reuse$(_reused_0, _id_0, _excluded_0, _remaining_0) {
  if (_reused_0) {
    return $TraceDraw$retry$(_remaining_0, {$: "Some", "value": _excluded_0});
  } else {
    return {$: "DrawnTraceId", "id": _id_0};
  }
}

function $TraceDraw$check$(_candidate_0, _excluded_0, _remaining_0) {
  if (_candidate_0.$ === "None") {
    return $TraceDraw$retry$(_remaining_0, _excluded_0);
  } else {
    const _id_0 = _candidate_0["value"];
    if (_excluded_0.$ === "None") {
      return {$: "DrawnTraceId", "id": _id_0};
    } else {
      const _old_0 = _excluded_0["value"];
      return $TraceDraw$reuse$(($TraceId$is_eq$(_id_0, _old_0)), _id_0, _old_0, _remaining_0);
    }
  }
}

function $TraceDraw$take$(_word_0, _remaining_0, _words_0, _excluded_0) {
  if (_words_0.$ === "NoTraceWord") {
    return {$: "NeedTraceWord", "draw": {$: "TraceDraw", "remaining": _remaining_0, "words": {$: "OneTraceWord", "first": _word_0}, "excluded": _excluded_0}};
  } else if (_words_0.$ === "OneTraceWord") {
    const _first_0 = _words_0["first"];
    return {$: "NeedTraceWord", "draw": {$: "TraceDraw", "remaining": _remaining_0, "words": {$: "TwoTraceWords", "first": _first_0, "second": _word_0}, "excluded": _excluded_0}};
  } else if (_words_0.$ === "TwoTraceWords") {
    const _first_1 = _words_0["first"];
    const _second_0 = _words_0["second"];
    return {$: "NeedTraceWord", "draw": {$: "TraceDraw", "remaining": _remaining_0, "words": {$: "ThreeTraceWords", "first": _first_1, "second": _second_0, "third": _word_0}, "excluded": _excluded_0}};
  } else {
    const _first_2 = _words_0["first"];
    const _second_1 = _words_0["second"];
    const _third_0 = _words_0["third"];
    return $TraceDraw$check$(($Draw$asserted$(($TraceId$from_words$(_first_2, _second_1, _third_0, _word_0)))), _excluded_0, _remaining_0);
  }
}

function $TraceDraw$feed$(_word_0, _remaining_0, _words_0, _excluded_0) {
  if (_word_0.$ === "Fail") {
    const _t_0 = _word_0["error"];
    const _code_0 = _t_0["fst"];
    const _message_0 = _t_0["snd"];
    return {$: "TraceFailed", "error": {$: "SourceFailure", "code": _code_0, "message": _message_0}};
  } else {
    const _next_0 = _word_0["value"];
    return $TraceDraw$take$(_next_0, _remaining_0, _words_0, _excluded_0);
  }
}

function $TraceDraw$next$(_word_0, _draw_0) {
  const _remaining_0 = _draw_0["remaining"];
  const _words_0 = _draw_0["words"];
  const _excluded_0 = _draw_0["excluded"];
  return $TraceDraw$feed$(_word_0, _remaining_0, _words_0, _excluded_0);
}

function $TraceStep$waiting$(_step_0) {
  if (_step_0.$ === "NeedTraceWord") {
    const _draw_0 = _step_0["draw"];
    return {$: "Some", "value": _draw_0};
  } else if (_step_0.$ === "DrawnTraceId") {
    return {$: "None"};
  } else {
    return {$: "None"};
  }
}

function $TraceDraw$result$(_step_0) {
  if (_step_0.$ === "DrawnTraceId") {
    const _id_0 = _step_0["id"];
    return {$: "Done", "value": _id_0};
  } else if (_step_0.$ === "TraceFailed") {
    const _error_0 = _step_0["error"];
    return {$: "Fail", "error": _error_0};
  } else {
    return {$: "Fail", "error": {$: "ExhaustedTraceId"}};
  }
}

function $TraceDraw$run$(_fuel_0, _current_0) {
  const _tape_0 = _current_0["fst"];
  const _step_0 = _current_0["snd"];
  return $Drive$run$1260$(_fuel_0, {$: "Tuple", "fst": _tape_0, "snd": {$: "Tuple", "fst": _step_0, "snd": ($TraceStep$waiting$(_step_0))}});
}

function $TraceDraw$ended$(_result_0) {
  return $Drive$ended$1260$(_result_0);
}

function $TraceDraw$outcome$(_done_0) {
  return $Drive$outcome$1260$(_done_0);
}

function $SpanDraw$start$(_excluded_0) {
  return {$: "NeedSpanWord", "draw": {$: "SpanDraw", "remaining": 7, "words": {$: "NoSpanWord"}, "excluded": _excluded_0}};
}

function $SpanDraw$retry$(_remaining_0, _excluded_0) {
  if (_remaining_0 === 0) {
    return {$: "SpanFailed", "error": {$: "ExhaustedSpanId"}};
  } else {
    const _p_0 = (_remaining_0 - 1);
    return {$: "NeedSpanWord", "draw": {$: "SpanDraw", "remaining": _p_0, "words": {$: "NoSpanWord"}, "excluded": _excluded_0}};
  }
}

function $SpanDraw$reuse$(_reused_0, _id_0, _excluded_0, _remaining_0) {
  if (_reused_0) {
    return $SpanDraw$retry$(_remaining_0, {$: "Some", "value": _excluded_0});
  } else {
    return {$: "DrawnSpanId", "id": _id_0};
  }
}

function $SpanDraw$check$(_candidate_0, _excluded_0, _remaining_0) {
  if (_candidate_0.$ === "None") {
    return $SpanDraw$retry$(_remaining_0, _excluded_0);
  } else {
    const _id_0 = _candidate_0["value"];
    if (_excluded_0.$ === "None") {
      return {$: "DrawnSpanId", "id": _id_0};
    } else {
      const _old_0 = _excluded_0["value"];
      return $SpanDraw$reuse$(($SpanId$is_eq$(_id_0, _old_0)), _id_0, _old_0, _remaining_0);
    }
  }
}

function $SpanDraw$take$(_word_0, _remaining_0, _words_0, _excluded_0) {
  if (_words_0.$ === "NoSpanWord") {
    return {$: "NeedSpanWord", "draw": {$: "SpanDraw", "remaining": _remaining_0, "words": {$: "OneSpanWord", "first": _word_0}, "excluded": _excluded_0}};
  } else {
    const _first_0 = _words_0["first"];
    return $SpanDraw$check$(($SpanId$from_words$(_first_0, _word_0)), _excluded_0, _remaining_0);
  }
}

function $SpanDraw$feed$(_word_0, _remaining_0, _words_0, _excluded_0) {
  if (_word_0.$ === "Fail") {
    const _t_0 = _word_0["error"];
    const _code_0 = _t_0["fst"];
    const _message_0 = _t_0["snd"];
    return {$: "SpanFailed", "error": {$: "SourceFailure", "code": _code_0, "message": _message_0}};
  } else {
    const _next_0 = _word_0["value"];
    return $SpanDraw$take$(_next_0, _remaining_0, _words_0, _excluded_0);
  }
}

function $SpanDraw$next$(_word_0, _draw_0) {
  const _remaining_0 = _draw_0["remaining"];
  const _words_0 = _draw_0["words"];
  const _excluded_0 = _draw_0["excluded"];
  return $SpanDraw$feed$(_word_0, _remaining_0, _words_0, _excluded_0);
}

function $SpanStep$waiting$(_step_0) {
  if (_step_0.$ === "NeedSpanWord") {
    const _draw_0 = _step_0["draw"];
    return {$: "Some", "value": _draw_0};
  } else if (_step_0.$ === "DrawnSpanId") {
    return {$: "None"};
  } else {
    return {$: "None"};
  }
}

function $SpanDraw$result$(_step_0) {
  if (_step_0.$ === "DrawnSpanId") {
    const _id_0 = _step_0["id"];
    return {$: "Done", "value": _id_0};
  } else if (_step_0.$ === "SpanFailed") {
    const _error_0 = _step_0["error"];
    return {$: "Fail", "error": _error_0};
  } else {
    return {$: "Fail", "error": {$: "ExhaustedSpanId"}};
  }
}

function $SpanDraw$run$(_fuel_0, _current_0) {
  const _tape_0 = _current_0["fst"];
  const _step_0 = _current_0["snd"];
  return $Drive$run$1261$(_fuel_0, {$: "Tuple", "fst": _tape_0, "snd": {$: "Tuple", "fst": _step_0, "snd": ($SpanStep$waiting$(_step_0))}});
}

function $SpanDraw$ended$(_result_0) {
  return $Drive$ended$1261$(_result_0);
}

function $SpanDraw$outcome$(_done_0) {
  return $Drive$outcome$1261$(_done_0);
}

function $Step$of_span$(_step_0, _trace_id_0, _sampled_0) {
  if (_step_0.$ === "NeedSpanWord") {
    const _draw_0 = _step_0["draw"];
    return {$: "NeedWord", "draw": {$: "DrawSpan", "draw": _draw_0, "trace_id": _trace_id_0, "sampled": _sampled_0}};
  } else if (_step_0.$ === "DrawnSpanId") {
    const _id_0 = _step_0["id"];
    return {$: "Created", "context": ($Context$from_ids$(_trace_id_0, _id_0, _sampled_0))};
  } else {
    const _error_0 = _step_0["error"];
    return {$: "Failed", "error": _error_0};
  }
}

function $SpanPlan$root$(_trace_id_0, _sampled_0) {
  return {$: "SpanPlan", "excluded": {$: "None"}, "trace_id": _trace_id_0, "sampled": _sampled_0};
}

function $SpanPlan$child$(_parent_0, _sampling_0) {
  return {$: "SpanPlan", "excluded": {$: "Some", "value": ($Parent$span_id$(_parent_0))}, "trace_id": ($Parent$trace_id$(_parent_0)), "sampled": ($Sampling$resolve$(_sampling_0, ($Parent$is_sampled$(_parent_0))))};
}

function $SpanPlan$draw$(_plan_0) {
  const _excluded_0 = _plan_0["excluded"];
  const _trace_id_0 = _plan_0["trace_id"];
  const _sampled_0 = _plan_0["sampled"];
  return $Step$of_span$(($SpanDraw$start$(_excluded_0)), _trace_id_0, _sampled_0);
}

function $Step$of_trace$(_step_0, _sampled_0) {
  if (_step_0.$ === "NeedTraceWord") {
    const _draw_0 = _step_0["draw"];
    return {$: "NeedWord", "draw": {$: "DrawTrace", "draw": _draw_0, "sampled": _sampled_0}};
  } else if (_step_0.$ === "DrawnTraceId") {
    const _id_0 = _step_0["id"];
    return $SpanPlan$draw$(($SpanPlan$root$(_id_0, _sampled_0)));
  } else {
    const _error_0 = _step_0["error"];
    return {$: "Failed", "error": _error_0};
  }
}

function $Draw$restart_excluded$(_previous_0) {
  return {$: "Some", "value": ($RemoteContext$trace_id$(_previous_0))};
}

function $Draw$root$(_sampled_0) {
  return $Step$of_trace$(($TraceDraw$start$({$: "None"})), _sampled_0);
}

function $Draw$restart$(_previous_0, _sampled_0) {
  return $Step$of_trace$(($TraceDraw$start$(($Draw$restart_excluded$(_previous_0)))), _sampled_0);
}

function $Draw$child$(_parent_0, _sampling_0) {
  return $SpanPlan$draw$(($SpanPlan$child$(_parent_0, _sampling_0)));
}

function $Draw$feed$(_word_0, _draw_0) {
  if (_draw_0.$ === "DrawTrace") {
    const _trace_0 = _draw_0["draw"];
    const _sampled_0 = _draw_0["sampled"];
    return $Step$of_trace$(($TraceDraw$next$(_word_0, _trace_0)), _sampled_0);
  } else {
    const _span_0 = _draw_0["draw"];
    const _trace_id_0 = _draw_0["trace_id"];
    const _sampled_1 = _draw_0["sampled"];
    return $Step$of_span$(($SpanDraw$next$(_word_0, _span_0)), _trace_id_0, _sampled_1);
  }
}

function $Step$waiting$(_step_0) {
  if (_step_0.$ === "NeedWord") {
    const _draw_0 = _step_0["draw"];
    return {$: "Some", "value": _draw_0};
  } else if (_step_0.$ === "Created") {
    return {$: "None"};
  } else {
    return {$: "None"};
  }
}

function $Step$result$(_step_0) {
  if (_step_0.$ === "Created") {
    const _context_0 = _step_0["context"];
    return {$: "Done", "value": _context_0};
  } else if (_step_0.$ === "Failed") {
    const _error_0 = _step_0["error"];
    return {$: "Fail", "error": _error_0};
  } else {
    const _t_0 = _step_0["draw"];
    if (_t_0.$ === "DrawTrace") {
      return {$: "Fail", "error": {$: "ExhaustedTraceId"}};
    } else {
      return {$: "Fail", "error": {$: "ExhaustedSpanId"}};
    }
  }
}

function $Draw$run$(_fuel_0, _current_0) {
  const _tape_0 = _current_0["fst"];
  const _step_0 = _current_0["snd"];
  return $Drive$run$1262$(_fuel_0, {$: "Tuple", "fst": _tape_0, "snd": {$: "Tuple", "fst": _step_0, "snd": ($Step$waiting$(_step_0))}});
}

function $Draw$ended$(_result_0) {
  return $Drive$ended$1262$(_result_0);
}

function $Draw$outcome$(_done_0) {
  return $Drive$outcome$1262$(_done_0);
}

function $Generation$root$(_sampled_0) {
  return {$: "Generation", "fuel": 48, "step": ($Draw$root$(_sampled_0))};
}

function $Generation$restart$(_previous_0, _sampled_0) {
  return {$: "Generation", "fuel": 48, "step": ($Draw$restart$(_previous_0, _sampled_0))};
}

function $Generation$child$(_parent_0, _sampling_0) {
  return {$: "Generation", "fuel": 16, "step": ($Draw$child$(_parent_0, _sampling_0))};
}

function $Generation$needs$of$(_fuel_0, _step_0) {
  if (_fuel_0 === 0) {
    return false;
  } else {
    if (_step_0.$ === "NeedWord") {
      return true;
    } else if (_step_0.$ === "Created") {
      return false;
    } else {
      return false;
    }
  }
}

function $Generation$needs$(_generation_0) {
  const _fuel_0 = _generation_0["fuel"];
  const _step_0 = _generation_0["step"];
  return $Generation$needs$of$(_fuel_0, _step_0);
}

function $Generation$fed$(_fuel_0, _step_0, _word_0) {
  if (_fuel_0 === 0) {
    return {$: "Generation", "fuel": 0, "step": _step_0};
  } else {
    const _p_0 = (_fuel_0 - 1);
    if (_step_0.$ === "NeedWord") {
      const _draw_0 = _step_0["draw"];
      return {$: "Generation", "fuel": _p_0, "step": ($Draw$feed$(_word_0, _draw_0))};
    } else if (_step_0.$ === "Created") {
      const _context_0 = _step_0["context"];
      return {$: "Generation", "fuel": 0, "step": {$: "Created", "context": _context_0}};
    } else {
      const _error_0 = _step_0["error"];
      return {$: "Generation", "fuel": 0, "step": {$: "Failed", "error": _error_0}};
    }
  }
}

function $Generation$feed$(_generation_0, _word_0) {
  const _fuel_0 = _generation_0["fuel"];
  const _step_0 = _generation_0["step"];
  return $Generation$fed$(_fuel_0, _step_0, _word_0);
}

function $Generation$result$(_generation_0) {
  const _step_0 = _generation_0["step"];
  return $Step$result$(_step_0);
}

function $Draw$span_context$(_trace_id_0, _sampled_0, _done_0) {
  const _state_0 = _done_0["fst"];
  const _t_0 = _done_0["snd"];
  if (_t_0.$ === "Fail") {
    const _error_0 = _t_0["error"];
    return {$: "Tuple", "fst": _state_0, "snd": {$: "Fail", "error": _error_0}};
  } else {
    const _span_id_0 = _t_0["value"];
    return {$: "Tuple", "fst": _state_0, "snd": {$: "Done", "value": ($Context$from_ids$(_trace_id_0, _span_id_0, _sampled_0))}};
  }
}

function $Source$tape$(_tape_0) {
  return run_clo((_x_0) => {
  return $IO$pure$(($Tape$next$(_tape_0)), _x_0);
});
}

function $Error$show$(_error_0) {
  if (_error_0.$ === "UnexpectedEnd") {
    const _offset_0 = _error_0["offset"];
    const _x_0 = ($Nat$show$(_offset_0));
    return ("UnexpectedEnd at " + _x_0);
  } else if (_error_0.$ === "InvalidHex") {
    const _offset_1 = _error_0["offset"];
    const _x_1 = ($Nat$show$(_offset_1));
    return ("InvalidHex at " + _x_1);
  } else if (_error_0.$ === "InvalidByte") {
    const _offset_2 = _error_0["offset"];
    const _x_2 = ($Nat$show$(_offset_2));
    return ("InvalidByte at " + _x_2);
  } else if (_error_0.$ === "ExpectedSeparator") {
    const _offset_3 = _error_0["offset"];
    const _x_3 = ($Nat$show$(_offset_3));
    return ("ExpectedSeparator at " + _x_3);
  } else if (_error_0.$ === "TrailingInput") {
    return "TrailingInput";
  } else if (_error_0.$ === "ForbiddenVersion") {
    return "ForbiddenVersion";
  } else if (_error_0.$ === "UnsupportedVersion") {
    const _version_0 = _error_0["version"];
    return ("UnsupportedVersion " + _version_0);
  } else if (_error_0.$ === "ZeroId") {
    const _t_0 = _error_0["field"];
    if (_t_0.$ === "TraceIdField") {
      return "ZeroTraceId";
    } else if (_t_0.$ === "ParentIdField") {
      return "ZeroParentId";
    } else {
      return "ZeroSpanId";
    }
  } else {
    const _offset_4 = _error_0["offset"];
    const _x_4 = ($Nat$show$(_offset_4));
    return ("ControlCharacter at " + _x_4);
  }
}

function $ContextError$show$(_error_0) {
  if (_error_0.$ === "ReusedSpanId") {
    return "ReusedSpanId";
  } else {
    return "ReusedTraceId";
  }
}

function $GenerationError$show$(_error_0) {
  if (_error_0.$ === "SourceFailure") {
    const _code_0 = _error_0["code"];
    const _message_0 = _error_0["message"];
    const _x_0 = ($U32$show$(_code_0));
    const _x_1 = (" " + _message_0);
    const _x_2 = (_x_0 + _x_1);
    return ("SourceFailure " + _x_2);
  } else if (_error_0.$ === "ExhaustedTraceId") {
    return "ExhaustedTraceId";
  } else {
    return "ExhaustedSpanId";
  }
}

function $Limits$is_valid$(_traceparent_input_0, _tracestate_input_0, _tracestate_output_0) {
  return $Bool$and$(($Nat$is_ge$(_traceparent_input_0, 55)), ($Bool$and$(($Nat$is_ge$(_tracestate_output_0, 512)), ($Nat$is_ge$(_tracestate_input_0, _tracestate_output_0)))));
}

function $Limits$error$(_traceparent_input_0, _tracestate_output_0) {
  return $Bool$pick$((_traceparent_input_0 < 55), {$: "TraceParentInputTooSmall"}, ($Bool$pick$((_tracestate_output_0 < 512), {$: "TraceStateOutputTooSmall"}, {$: "TraceStateInputTooSmall"})));
}

function $Limits$new$checked$(_traceparent_input_0, _tracestate_input_0, _tracestate_output_0, _valid_0, _evidence_0) {
  if (_valid_0) {
    return {$: "Done", "value": {$: "Limits", "traceparent_input": _traceparent_input_0, "tracestate_input": _tracestate_input_0, "tracestate_output": _tracestate_output_0, "evidence": _evidence_0}};
  } else {
    return {$: "Fail", "error": ($Limits$error$(_traceparent_input_0, _tracestate_output_0))};
  }
}

function $Limits$new$(_traceparent_input_0, _tracestate_input_0, _tracestate_output_0) {
  return $Limits$new$checked$(_traceparent_input_0, _tracestate_input_0, _tracestate_output_0, ($Limits$is_valid$(_traceparent_input_0, _tracestate_input_0, _tracestate_output_0)), null);
}

function $Limits$default$() {
  return {$: "Limits", "traceparent_input": 32768, "tracestate_input": 32768, "tracestate_output": 512, "evidence": null};
}

function $Limits$traceparent_input$(_limits_0) {
  const _traceparent_input_0 = _limits_0["traceparent_input"];
  return _traceparent_input_0;
}

function $Limits$tracestate_input$(_limits_0) {
  const _tracestate_input_0 = _limits_0["tracestate_input"];
  return _tracestate_input_0;
}

function $Limits$tracestate_output$(_limits_0) {
  const _tracestate_output_0 = _limits_0["tracestate_output"];
  return _tracestate_output_0;
}

function $LimitsError$show$(_error_0) {
  if (_error_0.$ === "TraceParentInputTooSmall") {
    return "TraceParentInputTooSmall";
  } else if (_error_0.$ === "TraceStateOutputTooSmall") {
    return "TraceStateOutputTooSmall";
  } else {
    return "TraceStateInputTooSmall";
  }
}

function $StateChar$in_range$(_code_0, _low_0, _high_0) {
  return $Bool$and$((_code_0 >= _low_0), (_code_0 <= _high_0));
}

function $StateChar$is_key_start$(_char_0) {
  const _x_0 = ($StateChar$in_range$(_char_0.codePointAt(0), 97, 122));
  const _x_1 = ($StateChar$in_range$(_char_0.codePointAt(0), 48, 57));
  return (_x_0 || _x_1);
}

function $StateChar$is_key$(_char_0) {
  const _x_0 = ($Char$is_eq$(_char_0, "/"));
  const _x_1 = ($Char$is_eq$(_char_0, "@"));
  const _x_2 = ($Char$is_eq$(_char_0, "*"));
  const _x_3 = (_x_0 || _x_1);
  const _x_4 = ($Char$is_eq$(_char_0, "-"));
  const _x_5 = (_x_2 || _x_3);
  const _x_6 = ($Char$is_eq$(_char_0, "_"));
  const _x_7 = (_x_4 || _x_5);
  const _x_8 = ($StateChar$is_key_start$(_char_0));
  const _x_9 = (_x_6 || _x_7);
  return (_x_8 || _x_9);
}

function $StateChar$is_value_end$(_char_0) {
  const _x_0 = ($StateChar$in_range$(_char_0.codePointAt(0), 45, 60));
  const _x_1 = ($StateChar$in_range$(_char_0.codePointAt(0), 62, 126));
  const _x_2 = ($StateChar$in_range$(_char_0.codePointAt(0), 33, 43));
  const _x_3 = (_x_0 || _x_1);
  return (_x_2 || _x_3);
}

function $StateChar$is_value$(_char_0) {
  const _x_0 = ($Char$is_eq$(_char_0, " "));
  const _x_1 = ($StateChar$is_value_end$(_char_0));
  return (_x_0 || _x_1);
}

function $StateChar$is_ows$(_char_0) {
  const _x_0 = ($Char$is_eq$(_char_0, " "));
  const _x_1 = ($Char$is_eq$(_char_0, "\t"));
  return (_x_0 || _x_1);
}

function $StateKey$valid$rest$(_text_0, _room_0) {
  if (_text_0 === "") {
    return true;
  } else {
    const _char_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(0, 2) : _text_0[0]);
    const _tail_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(2) : _text_0.slice(1));
    if (_room_0 === 0) {
      return false;
    } else {
      const _left_0 = (_room_0 - 1);
      return $Bool$and$(($StateChar$is_key$(_char_0)), ($StateKey$valid$rest$(_tail_0, _left_0)));
    }
  }
}

function $StateKey$is_valid$(_text_0) {
  if (_text_0 === "") {
    return false;
  } else {
    const _char_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(0, 2) : _text_0[0]);
    const _tail_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(2) : _text_0.slice(1));
    return $Bool$and$(($StateChar$is_key_start$(_char_0)), ($StateKey$valid$rest$(_tail_0, 255)));
  }
}

function $StateValue$valid$go$(_tail_0, _char_0, _room_0) {
  if (_tail_0 === "") {
    return $StateChar$is_value_end$(_char_0);
  } else {
    const _next_0 = (_tail_0.codePointAt(0) > 0xFFFF ? _tail_0.slice(0, 2) : _tail_0[0]);
    const _rest_0 = (_tail_0.codePointAt(0) > 0xFFFF ? _tail_0.slice(2) : _tail_0.slice(1));
    if (_room_0 === 0) {
      return false;
    } else {
      const _left_0 = (_room_0 - 1);
      return $Bool$and$(($StateChar$is_value$(_char_0)), ($StateValue$valid$go$(_rest_0, _next_0, _left_0)));
    }
  }
}

function $StateValue$is_valid$(_text_0) {
  if (_text_0 === "") {
    return false;
  } else {
    const _char_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(0, 2) : _text_0[0]);
    const _tail_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(2) : _text_0.slice(1));
    return $StateValue$valid$go$(_tail_0, _char_0, 255);
  }
}

function $StateKey$parse$checked$(_text_0, _valid_0, _evidence_0) {
  if (_valid_0) {
    return {$: "Done", "value": {$: "StateKey", "text": _text_0, "evidence": _evidence_0}};
  } else {
    return {$: "Fail", "error": {$: "InvalidKey"}};
  }
}

function $StateKey$parse$(_text_0) {
  return $StateKey$parse$checked$(_text_0, ($StateKey$is_valid$(_text_0)), null);
}

function $StateKey$to_string$(_key_0) {
  const _text_0 = _key_0["text"];
  return _text_0;
}

function $StateValue$parse$checked$(_text_0, _valid_0, _evidence_0) {
  if (_valid_0) {
    return {$: "Done", "value": {$: "StateValue", "text": _text_0, "evidence": _evidence_0}};
  } else {
    return {$: "Fail", "error": {$: "InvalidValue"}};
  }
}

function $StateValue$parse$(_text_0) {
  return $StateValue$parse$checked$(_text_0, ($StateValue$is_valid$(_text_0)), null);
}

function $StateValue$to_string$(_value_0) {
  const _text_0 = _value_0["text"];
  return _text_0;
}

function $EntryError$show$(_error_0) {
  if (_error_0.$ === "MissingEquals") {
    return "MissingEquals";
  } else if (_error_0.$ === "InvalidKey") {
    return "InvalidKey";
  } else {
    return "InvalidValue";
  }
}

function $StateEntry$key$(_entry_0) {
  const _key_0 = _entry_0["key"];
  return _key_0;
}

function $StateEntry$value$(_entry_0) {
  const _value_0 = _entry_0["value"];
  return _value_0;
}

function $StateEntry$key_text$(_entry_0) {
  return $StateKey$to_string$(($StateEntry$key$(_entry_0)));
}

function $StateEntry$format$(_entry_0) {
  const _key_0 = _entry_0["key"];
  const _value_0 = _entry_0["value"];
  const _x_0 = ($StateValue$to_string$(_value_0));
  const _x_1 = ($StateKey$to_string$(_key_0));
  const _x_2 = ("=" + _x_0);
  return (_x_1 + _x_2);
}

function $Entries$has_key$(_entries_0, _key_0) {
  if (_entries_0.$ === "Nil") {
    return false;
  } else {
    const _entry_0 = _entries_0["head"];
    const _rest_0 = _entries_0["tail"];
    const _x_0 = ($String$eq$(($StateEntry$key_text$(_entry_0)), _key_0));
    const _x_1 = ($Entries$has_key$(_rest_0, _key_0));
    return (_x_0 || _x_1);
  }
}

function $Entries$unique$(_entries_0, _seen_0) {
  if (_entries_0.$ === "Nil") {
    return true;
  } else {
    const _entry_0 = _entries_0["head"];
    const _rest_0 = _entries_0["tail"];
    return $Bool$and$(($Bool$not$(($Entries$has_key$(_seen_0, ($StateEntry$key_text$(_entry_0)))))), ($Entries$unique$(_rest_0, ($List$append$(_seen_0, {$: "Con", "head": _entry_0, "tail": {$: "Nil"}})))));
  }
}

function $TraceState$is_valid$(_entries_0) {
  return $Bool$and$(($Entries$unique$(_entries_0, {$: "Nil"})), ($Nat$is_le$(($List$length$(_entries_0)), 32)));
}

function $TraceState$empty$() {
  return {$: "TraceState", "entries": {$: "Nil"}, "evidence": null};
}

function $TraceState$entries$(_state_0) {
  const _entries_0 = _state_0["entries"];
  return _entries_0;
}

function $TraceState$is_empty$(_state_0) {
  return $List$is_empty$(($TraceState$entries$(_state_0)));
}

function $Entries$get$put$(_entry_0, _rest_0, _hit_0) {
  if (_hit_0) {
    return {$: "Some", "value": ($StateEntry$value$(_entry_0))};
  } else {
    return _rest_0;
  }
}

function $Entries$get$(_entries_0, _key_0) {
  if (_entries_0.$ === "Nil") {
    return {$: "None"};
  } else {
    const _entry_0 = _entries_0["head"];
    const _rest_0 = _entries_0["tail"];
    return $Entries$get$put$(_entry_0, ($Entries$get$(_rest_0, _key_0)), ($String$eq$(($StateEntry$key_text$(_entry_0)), _key_0)));
  }
}

function $TraceState$get$(_state_0, _key_0) {
  return $Entries$get$(($TraceState$entries$(_state_0)), ($StateKey$to_string$(_key_0)));
}

function $Entries$format$rest$(_entries_0) {
  if (_entries_0.$ === "Nil") {
    return "";
  } else {
    const _entry_0 = _entries_0["head"];
    const _rest_0 = _entries_0["tail"];
    const _x_0 = ($StateEntry$format$(_entry_0));
    const _x_1 = ($Entries$format$rest$(_rest_0));
    const _x_2 = (_x_0 + _x_1);
    return ("," + _x_2);
  }
}

function $Entries$format$(_entries_0) {
  if (_entries_0.$ === "Nil") {
    return "";
  } else {
    const _entry_0 = _entries_0["head"];
    const _rest_0 = _entries_0["tail"];
    const _x_0 = ($StateEntry$format$(_entry_0));
    const _x_1 = ($Entries$format$rest$(_rest_0));
    return (_x_0 + _x_1);
  }
}

function $TraceState$format$(_state_0) {
  return $Entries$format$(($TraceState$entries$(_state_0)));
}

function $Utf8$width$(_char_0) {
  const _x_0 = _char_0.codePointAt(0);
  const _x_1 = _char_0.codePointAt(0);
  const _x_2 = _char_0.codePointAt(0);
  return $Bool$pick$((_x_0 < 128), 1, ($Bool$pick$((_x_1 < 2048), 2, ($Bool$pick$((_x_2 < 65536), 3, 4)))));
}

function $Utf8$length$(_text_0) {
  if (_text_0 === "") {
    return 0;
  } else {
    const _char_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(0, 2) : _text_0[0]);
    const _tail_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(2) : _text_0.slice(1));
    const _x_0 = ($Utf8$width$(_char_0));
    const _x_1 = ($Utf8$length$(_tail_0));
    return nat_chk(_x_0 + _x_1);
  }
}

function $Budget$take$($0, $1) {
  for (;;) {
    {
      const _need_0 = $0;
      const _budget_0 = $1;
      if (_need_0 === 0) {
        return {$: "Some", "value": _budget_0};
      } else {
        const _more_0 = (_need_0 - 1);
        if (_budget_0 === 0) {
          return {$: "None"};
        } else {
          const _left_0 = (_budget_0 - 1);
          $0 = _more_0;
          $1 = _left_0;
          continue;
        }
      }
    }
  }
}

function $Utf8$left$($0, $1) {
  for (;;) {
    {
      const _text_0 = $0;
      const _budget_0 = $1;
      if (_text_0 === "") {
        if (_budget_0.$ === "None") {
          return {$: "None"};
        } else {
          const _left_0 = _budget_0["value"];
          return {$: "Some", "value": _left_0};
        }
      } else {
        const _char_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(0, 2) : _text_0[0]);
        const _tail_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(2) : _text_0.slice(1));
        if (_budget_0.$ === "None") {
          return {$: "None"};
        } else {
          const _left_1 = _budget_0["value"];
          $0 = _tail_0;
          $1 = ($Budget$take$(($Utf8$width$(_char_0)), _left_1));
          continue;
        }
      }
    }
  }
}

function $Utf8$left_more$($0, $1) {
  for (;;) {
    {
      const _fields_0 = $0;
      const _budget_0 = $1;
      if (_fields_0.$ === "Nil") {
        return _budget_0;
      } else {
        const _field_0 = _fields_0["head"];
        const _rest_0 = _fields_0["tail"];
        if (_budget_0.$ === "None") {
          return {$: "None"};
        } else {
          const _left_0 = _budget_0["value"];
          $0 = _rest_0;
          $1 = ($Utf8$left$(_field_0, ($Utf8$left$(",", {$: "Some", "value": _left_0}))));
          continue;
        }
      }
    }
  }
}

function $Utf8$left_fields$(_fields_0, _budget_0) {
  if (_fields_0.$ === "Nil") {
    return _budget_0;
  } else {
    const _field_0 = _fields_0["head"];
    const _rest_0 = _fields_0["tail"];
    return $Utf8$left_more$(_rest_0, ($Utf8$left$(_field_0, _budget_0)));
  }
}

function $Value$restore$step$(_kept_0, _ows_0, _char_0, _value_0) {
  if (_kept_0) {
    return {$: "Tuple", "fst": true, "snd": (_char_0 + _value_0)};
  } else {
    if (_ows_0) {
      return {$: "Tuple", "fst": false, "snd": _value_0};
    } else {
      return {$: "Tuple", "fst": true, "snd": (_char_0 + _value_0)};
    }
  }
}

function $Value$restore$go$($0, $1) {
  for (;;) {
    {
      const _text_0 = $0;
      const _state_0 = $1;
      if (_text_0 === "") {
        const _value_0 = _state_0["snd"];
        return _value_0;
      } else {
        const _char_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(0, 2) : _text_0[0]);
        const _tail_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(2) : _text_0.slice(1));
        const _kept_1 = _state_0["fst"];
        const _value_1 = _state_0["snd"];
        $0 = _tail_0;
        $1 = ($Value$restore$step$(_kept_1, ($StateChar$is_ows$(_char_0)), _char_0, _value_1));
        continue;
      }
    }
  }
}

function $Value$restore$(_text_0) {
  return $Value$restore$go$(_text_0, {$: "Tuple", "fst": false, "snd": ""});
}

function $Member$start$(_ows_0, _equals_0, _char_0) {
  if (_ows_0) {
    return {$: "Blank"};
  } else {
    if (_equals_0) {
      return {$: "InValue", "key": "", "text": ""};
    } else {
      return {$: "InKey", "text": (_char_0 + "")};
    }
  }
}

function $Member$key$(_equals_0, _char_0, _text_0) {
  if (_equals_0) {
    return {$: "InValue", "key": ($String$reverse$(_text_0)), "text": ""};
  } else {
    return {$: "InKey", "text": (_char_0 + _text_0)};
  }
}

function $Member$push$(_char_0, _current_0) {
  if (_current_0.$ === "Blank") {
    return $Member$start$(($StateChar$is_ows$(_char_0)), ($Char$is_eq$(_char_0, "=")), _char_0);
  } else if (_current_0.$ === "InKey") {
    const _text_0 = _current_0["text"];
    return $Member$key$(($Char$is_eq$(_char_0, "=")), _char_0, _text_0);
  } else {
    const _key_0 = _current_0["key"];
    const _text_1 = _current_0["text"];
    return {$: "InValue", "key": _key_0, "text": (_char_0 + _text_1)};
  }
}

function $Scan$validate$(_key_0, _value_0) {
  return $Result$bind$(($StateKey$parse$(_key_0)), run_clo((_x_0) => {
  return $Result$bind$(($StateValue$parse$(_value_0)), run_clo((_x_1) => {
  return $Result$pure$({$: "StateEntry", "key": _x_0, "value": _x_1});
}));
}));
}

function $Entries$add$if$(_entries_0, _entry_0, _present_0) {
  if (_present_0) {
    return _entries_0;
  } else {
    return $List$append$(_entries_0, {$: "Con", "head": _entry_0, "tail": {$: "Nil"}});
  }
}

function $Entries$add$(_entries_0, _entry_0) {
  return $Entries$add$if$(_entries_0, _entry_0, ($Entries$has_key$(_entries_0, ($StateEntry$key_text$(_entry_0)))));
}

function $Scan$keep$(_room_0, _member_0, _entry_0, _entries_0) {
  if (_room_0 === 0) {
    return {$: "Stopped", "error": {$: "TooManyMembers"}};
  } else {
    const _left_0 = (_room_0 - 1);
    return {$: "Scanning", "member": nat_chk(_member_0 + 1), "room": _left_0, "current": {$: "Blank"}, "entries": ($Entries$add$(_entries_0, _entry_0))};
  }
}

function $Scan$entry$(_parsed_0, _member_0, _room_0, _entries_0) {
  if (_parsed_0.$ === "Fail") {
    const _error_0 = _parsed_0["error"];
    return {$: "Stopped", "error": {$: "InvalidEntry", "member": _member_0, "error": _error_0}};
  } else {
    const _entry_0 = _parsed_0["value"];
    return $Scan$keep$(_room_0, _member_0, _entry_0, _entries_0);
  }
}

function $Scan$close$(_member_0, _room_0, _current_0, _entries_0) {
  if (_current_0.$ === "Blank") {
    return {$: "Scanning", "member": nat_chk(_member_0 + 1), "room": _room_0, "current": {$: "Blank"}, "entries": _entries_0};
  } else if (_current_0.$ === "InKey") {
    return {$: "Stopped", "error": {$: "InvalidEntry", "member": _member_0, "error": {$: "MissingEquals"}}};
  } else {
    const _key_0 = _current_0["key"];
    const _text_1 = _current_0["text"];
    return $Scan$entry$(run_loop($Scan$validate$(_key_0, ($Value$restore$(_text_1)))), _member_0, _room_0, _entries_0);
  }
}

function $Scan$read$(_comma_0, _char_0, _member_0, _room_0, _current_0, _entries_0) {
  if (_comma_0) {
    return $Scan$close$(_member_0, _room_0, _current_0, _entries_0);
  } else {
    return {$: "Scanning", "member": _member_0, "room": _room_0, "current": ($Member$push$(_char_0, _current_0)), "entries": _entries_0};
  }
}

function $Scan$char$(_char_0, _scan_0) {
  if (_scan_0.$ === "Stopped") {
    const _error_0 = _scan_0["error"];
    return {$: "Stopped", "error": _error_0};
  } else {
    const _member_0 = _scan_0["member"];
    const _room_0 = _scan_0["room"];
    const _current_0 = _scan_0["current"];
    const _entries_0 = _scan_0["entries"];
    return $Scan$read$(($Char$is_eq$(_char_0, ",")), _char_0, _member_0, _room_0, _current_0, _entries_0);
  }
}

function $Scan$text$($0, $1) {
  for (;;) {
    {
      const _text_0 = $0;
      const _scan_0 = $1;
      if (_text_0 === "") {
        if (_scan_0.$ === "Stopped") {
          const _error_0 = _scan_0["error"];
          return {$: "Stopped", "error": _error_0};
        } else {
          const _member_0 = _scan_0["member"];
          const _room_0 = _scan_0["room"];
          const _current_0 = _scan_0["current"];
          const _entries_0 = _scan_0["entries"];
          return {$: "Scanning", "member": _member_0, "room": _room_0, "current": _current_0, "entries": _entries_0};
        }
      } else {
        const _char_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(0, 2) : _text_0[0]);
        const _tail_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(2) : _text_0.slice(1));
        if (_scan_0.$ === "Stopped") {
          const _error_1 = _scan_0["error"];
          return {$: "Stopped", "error": _error_1};
        } else {
          const _member_1 = _scan_0["member"];
          const _room_1 = _scan_0["room"];
          const _current_1 = _scan_0["current"];
          const _entries_1 = _scan_0["entries"];
          $0 = _tail_0;
          $1 = ($Scan$char$(_char_0, {$: "Scanning", "member": _member_1, "room": _room_1, "current": _current_1, "entries": _entries_1}));
          continue;
        }
      }
    }
  }
}

function $Scan$more$($0, $1) {
  for (;;) {
    {
      const _fields_0 = $0;
      const _scan_0 = $1;
      if (_fields_0.$ === "Nil") {
        return _scan_0;
      } else {
        const _field_0 = _fields_0["head"];
        const _rest_0 = _fields_0["tail"];
        $0 = _rest_0;
        $1 = ($Scan$text$(_field_0, ($Scan$char$(",", _scan_0))));
        continue;
      }
    }
  }
}

function $Scan$fields$(_fields_0, _scan_0) {
  if (_fields_0.$ === "Nil") {
    return _scan_0;
  } else {
    const _field_0 = _fields_0["head"];
    const _rest_0 = _fields_0["tail"];
    return $Scan$more$(_rest_0, ($Scan$text$(_field_0, _scan_0)));
  }
}

function $Scan$start$() {
  return {$: "Scanning", "member": 0, "room": 32, "current": {$: "Blank"}, "entries": {$: "Nil"}};
}

function $Scan$state$(_entries_0, _valid_0, _evidence_0) {
  if (_valid_0) {
    return {$: "Done", "value": {$: "TraceState", "entries": _entries_0, "evidence": _evidence_0}};
  } else {
    return {$: "Fail", "error": {$: "TooManyMembers"}};
  }
}

function $Scan$result$(_scan_0) {
  if (_scan_0.$ === "Stopped") {
    const _error_0 = _scan_0["error"];
    return {$: "Fail", "error": _error_0};
  } else {
    const _entries_0 = _scan_0["entries"];
    return $Scan$state$(_entries_0, ($TraceState$is_valid$(_entries_0)), null);
  }
}

function $Scan$finish$(_scan_0) {
  if (_scan_0.$ === "Stopped") {
    const _error_0 = _scan_0["error"];
    return {$: "Fail", "error": _error_0};
  } else {
    const _member_0 = _scan_0["member"];
    const _room_0 = _scan_0["room"];
    const _current_0 = _scan_0["current"];
    const _entries_0 = _scan_0["entries"];
    return $Scan$result$(($Scan$close$(_member_0, _room_0, _current_0, _entries_0)));
  }
}

function $Scan$within$(_fits_0, _fields_0) {
  if (_fits_0.$ === "None") {
    return {$: "Fail", "error": {$: "StateTooLarge"}};
  } else {
    return $Scan$finish$(($Scan$fields$(_fields_0, ($Scan$start$()))));
  }
}

function $TraceState$parse_fields$(_limits_0, _fields_0) {
  return $Scan$within$(($Utf8$left_fields$(_fields_0, {$: "Some", "value": ($Limits$tracestate_input$(_limits_0))})), _fields_0);
}

function $TraceState$parse$(_limits_0, _text_0) {
  return $TraceState$parse_fields$(_limits_0, {$: "Con", "head": _text_0, "tail": {$: "Nil"}});
}

function $StateError$show$(_error_0) {
  if (_error_0.$ === "StateTooLarge") {
    return "StateTooLarge";
  } else if (_error_0.$ === "TooManyMembers") {
    return "TooManyMembers";
  } else {
    const _member_0 = _error_0["member"];
    const _reason_0 = _error_0["error"];
    const _x_0 = ($EntryError$show$(_reason_0));
    const _x_1 = ($Nat$show$(_member_0));
    const _x_2 = (" " + _x_0);
    const _x_3 = (_x_1 + _x_2);
    return ("InvalidEntry " + _x_3);
  }
}

function $Entries$unless$(_skip_0, _item_0, _rest_0) {
  if (_skip_0) {
    return _rest_0;
  } else {
    return {$: "Con", "head": _item_0, "tail": _rest_0};
  }
}

function $Entries$without$(_entries_0, _key_0) {
  if (_entries_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _entry_0 = _entries_0["head"];
    const _rest_0 = _entries_0["tail"];
    return $Entries$unless$(($String$eq$(($StateEntry$key_text$(_entry_0)), _key_0)), _entry_0, ($Entries$without$(_rest_0, _key_0)));
  }
}

function $TraceState$from_entries$checked$(_entries_0, _fallback_0, _valid_0, _evidence_0) {
  if (_valid_0) {
    return {$: "TraceState", "entries": _entries_0, "evidence": _evidence_0};
  } else {
    return _fallback_0;
  }
}

function $TraceState$from_entries$(_entries_0, _fallback_0) {
  return $TraceState$from_entries$checked$(_entries_0, _fallback_0, ($TraceState$is_valid$(_entries_0)), null);
}

function $TraceState$set$(_state_0, _key_0, _value_0) {
  return $TraceState$from_entries$({$: "Con", "head": {$: "StateEntry", "key": _key_0, "value": _value_0}, "tail": ($List$take$(($Entries$without$(($TraceState$entries$(_state_0)), ($StateKey$to_string$(_key_0)))), 31))}, _state_0);
}

function $TraceState$remove$(_state_0, _key_0) {
  return $TraceState$from_entries$(($Entries$without$(($TraceState$entries$(_state_0)), ($StateKey$to_string$(_key_0)))), _state_0);
}

function $StateEntry$size$(_entry_0) {
  const _key_0 = _entry_0["key"];
  const _value_0 = _entry_0["value"];
  const _x_0 = ($Utf8$length$(($StateKey$to_string$(_key_0))));
  const _x_1 = nat_chk(($Utf8$length$(($StateValue$to_string$(_value_0)))) + 1);
  return nat_chk(_x_0 + _x_1);
}

function $Entries$size$rest$(_entries_0) {
  if (_entries_0.$ === "Nil") {
    return 0;
  } else {
    const _entry_0 = _entries_0["head"];
    const _rest_0 = _entries_0["tail"];
    const _x_0 = ($StateEntry$size$(_entry_0));
    const _x_1 = ($Entries$size$rest$(_rest_0));
    return nat_chk(nat_chk(_x_0 + _x_1) + 1);
  }
}

function $Entries$size$(_entries_0) {
  if (_entries_0.$ === "Nil") {
    return 0;
  } else {
    const _entry_0 = _entries_0["head"];
    const _rest_0 = _entries_0["tail"];
    const _x_0 = ($StateEntry$size$(_entry_0));
    const _x_1 = ($Entries$size$rest$(_rest_0));
    return nat_chk(_x_0 + _x_1);
  }
}

function $TraceState$size$(_state_0) {
  return $Entries$size$(($TraceState$entries$(_state_0)));
}

function $Truncation$kept$(_truncation_0) {
  const _kept_0 = _truncation_0["kept"];
  return _kept_0;
}

function $Truncation$dropped$(_truncation_0) {
  const _dropped_0 = _truncation_0["dropped"];
  return _dropped_0;
}

function $StateEntry$is_large$(_entry_0) {
  return $Nat$is_gt$(($StateEntry$size$(_entry_0)), 128);
}

function $Entries$has_large$(_entries_0) {
  if (_entries_0.$ === "Nil") {
    return false;
  } else {
    const _entry_0 = _entries_0["head"];
    const _rest_0 = _entries_0["tail"];
    const _x_0 = ($StateEntry$is_large$(_entry_0));
    const _x_1 = ($Entries$has_large$(_rest_0));
    return (_x_0 || _x_1);
  }
}

function $Entries$drop_last_large$(_entries_0) {
  if (_entries_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _entry_0 = _entries_0["head"];
    const _rest_0 = _entries_0["tail"];
    return $Bool$pick$(($Entries$has_large$(_rest_0)), {$: "Con", "head": _entry_0, "tail": ($Entries$drop_last_large$(_rest_0))}, ($Bool$pick$(($StateEntry$is_large$(_entry_0)), _rest_0, {$: "Con", "head": _entry_0, "tail": _rest_0})));
  }
}

function $Entries$drop_last$(_entries_0) {
  if (_entries_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _entry_0 = _entries_0["head"];
    const _rest_0 = _entries_0["tail"];
    return $Bool$pick$(($List$is_empty$(_rest_0)), {$: "Nil"}, {$: "Con", "head": _entry_0, "tail": ($Entries$drop_last$(_rest_0))});
  }
}

function $Entries$shrink$(_entries_0) {
  return $Bool$pick$(($Entries$has_large$(_entries_0)), ($Entries$drop_last_large$(_entries_0)), ($Entries$drop_last$(_entries_0)));
}

function $Entries$truncate$(_fuel_0, _budget_0, _entries_0) {
  if (_fuel_0 === 0) {
    return _entries_0;
  } else {
    const _more_0 = (_fuel_0 - 1);
    return $Bool$pick$(($Nat$is_le$(($Entries$size$(_entries_0)), _budget_0)), _entries_0, ($Entries$truncate$(_more_0, _budget_0, ($Entries$shrink$(_entries_0)))));
  }
}

function $Entries$dropped$(_entries_0, _kept_0) {
  if (_entries_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _entry_0 = _entries_0["head"];
    const _rest_0 = _entries_0["tail"];
    return $Entries$unless$(($Entries$has_key$(_kept_0, ($StateEntry$key_text$(_entry_0)))), ($StateEntry$key$(_entry_0)), ($Entries$dropped$(_rest_0, _kept_0)));
  }
}

function $TraceState$truncate$(_limits_0, _state_0) {
  const _entries_0 = ($TraceState$entries$(_state_0));
  const _kept_0 = ($Entries$truncate$(($List$length$(_entries_0)), ($Limits$tracestate_output$(_limits_0)), _entries_0));
  return {$: "Truncation", "kept": ($TraceState$from_entries$(_kept_0, ($TraceState$empty$()))), "dropped": ($Entries$dropped$(_entries_0, _kept_0))};
}

function $OutgoingContext$new$(_context_0) {
  return {$: "OutgoingContext", "context": _context_0, "state": ($TraceState$empty$())};
}

function $OutgoingContext$with_state$(_context_0, _state_0) {
  return {$: "OutgoingContext", "context": _context_0, "state": _state_0};
}

function $OutgoingContext$context$(_outgoing_0) {
  const _context_0 = _outgoing_0["context"];
  return _context_0;
}

function $OutgoingContext$state$(_outgoing_0) {
  const _state_0 = _outgoing_0["state"];
  return _state_0;
}

function $OutgoingContext$get$(_outgoing_0, _key_0) {
  return $TraceState$get$(($OutgoingContext$state$(_outgoing_0)), _key_0);
}

function $OutgoingContext$set$(_outgoing_0, _key_0, _value_0) {
  const _context_0 = _outgoing_0["context"];
  const _state_0 = _outgoing_0["state"];
  return {$: "OutgoingContext", "context": _context_0, "state": ($TraceState$set$(_state_0, _key_0, _value_0))};
}

function $OutgoingContext$remove$(_outgoing_0, _key_0) {
  const _context_0 = _outgoing_0["context"];
  const _state_0 = _outgoing_0["state"];
  return {$: "OutgoingContext", "context": _context_0, "state": ($TraceState$remove$(_state_0, _key_0))};
}

function $Emission$of$(_context_0, _truncation_0) {
  const _kept_0 = _truncation_0["kept"];
  const _dropped_0 = _truncation_0["dropped"];
  return {$: "Emission", "traceparent": ($TraceParentV00$format$(($LocalContext$to_traceparent$(_context_0)))), "tracestate": ($TraceState$format$(_kept_0)), "dropped": _dropped_0};
}

function $OutgoingContext$emit$(_limits_0, _outgoing_0) {
  const _context_0 = _outgoing_0["context"];
  const _state_0 = _outgoing_0["state"];
  return $Emission$of$(_context_0, ($TraceState$truncate$(_limits_0, _state_0)));
}

function $Emission$traceparent$(_emission_0) {
  const _traceparent_0 = _emission_0["traceparent"];
  return _traceparent_0;
}

function $Emission$tracestate$(_emission_0) {
  const _tracestate_0 = _emission_0["tracestate"];
  return _tracestate_0;
}

function $Emission$dropped$(_emission_0) {
  const _dropped_0 = _emission_0["dropped"];
  return _dropped_0;
}

function $Header$name$(_header_0) {
  const _name_0 = _header_0["name"];
  return _name_0;
}

function $Header$value$(_header_0) {
  const _value_0 = _header_0["value"];
  return _value_0;
}

function $Carrier$traceparent_name$() {
  return "traceparent";
}

function $Carrier$tracestate_name$() {
  return "tracestate";
}

function $Carrier$named$(_name_0, _text_0) {
  if (_name_0 === "") {
    if (_text_0 === "") {
      return true;
    } else {
      return false;
    }
  } else {
    const _expected_0 = (_name_0.codePointAt(0) > 0xFFFF ? _name_0.slice(0, 2) : _name_0[0]);
    const _more_0 = (_name_0.codePointAt(0) > 0xFFFF ? _name_0.slice(2) : _name_0.slice(1));
    if (_text_0 === "") {
      return false;
    } else {
      const _char_1 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(0, 2) : _text_0[0]);
      const _rest_1 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(2) : _text_0.slice(1));
      return $Bool$and$(($Char$is_eq$(($Char$to_lower$(_char_1)), _expected_0)), ($Carrier$named$(_more_0, _rest_1)));
    }
  }
}

function $Carrier$keep$(_hit_0, _value_0, _found_0) {
  if (_hit_0) {
    return {$: "Con", "head": _value_0, "tail": _found_0};
  } else {
    return _found_0;
  }
}

function $Carrier$values$go$($0, $1, $2) {
  for (;;) {
    {
      const _carrier_0 = $0;
      const _name_0 = $1;
      const _found_0 = $2;
      if (_carrier_0.$ === "Nil") {
        return _found_0;
      } else {
        const _header_0 = _carrier_0["head"];
        const _rest_0 = _carrier_0["tail"];
        $0 = _rest_0;
        $1 = _name_0;
        $2 = ($Carrier$keep$(($Carrier$named$(_name_0, ($Header$name$(_header_0)))), ($Header$value$(_header_0)), _found_0));
        continue;
      }
    }
  }
}

function $Carrier$values$(_carrier_0, _name_0) {
  return $List$reverse$(($Carrier$values$go$(_carrier_0, _name_0, {$: "Nil"})));
}

function $Text$drop_ows$go$($0, $1, $2) {
  for (;;) {
    {
      const _tail_0 = $0;
      const _head_0 = $1;
      const _ows_0 = $2;
      if (_tail_0 === "") {
        if (!_ows_0) {
          return (_head_0 + "");
        } else {
          return "";
        }
      } else {
        const _next_0 = (_tail_0.codePointAt(0) > 0xFFFF ? _tail_0.slice(0, 2) : _tail_0[0]);
        const _rest_0 = (_tail_0.codePointAt(0) > 0xFFFF ? _tail_0.slice(2) : _tail_0.slice(1));
        if (!_ows_0) {
          return (_head_0 + (_next_0 + _rest_0));
        } else {
          $0 = _rest_0;
          $1 = _next_0;
          $2 = ($StateChar$is_ows$(_next_0));
          continue;
        }
      }
    }
  }
}

function $Text$drop_ows$(_text_0) {
  if (_text_0 === "") {
    return "";
  } else {
    const _head_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(0, 2) : _text_0[0]);
    const _tail_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(2) : _text_0.slice(1));
    return $Text$drop_ows$go$(_tail_0, _head_0, ($StateChar$is_ows$(_head_0)));
  }
}

function $Text$trim_ows$(_text_0) {
  return $String$reverse$(($Text$drop_ows$(($String$reverse$(($Text$drop_ows$(_text_0)))))));
}

function $Text$has_comma$go$($0, $1) {
  for (;;) {
    {
      const _text_0 = $0;
      const _found_0 = $1;
      if (_text_0 === "") {
        if (_found_0) {
          return true;
        } else {
          return false;
        }
      } else {
        const _char_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(0, 2) : _text_0[0]);
        const _rest_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(2) : _text_0.slice(1));
        if (_found_0) {
          return true;
        } else {
          $0 = _rest_0;
          $1 = ($Char$is_eq$(_char_0, ","));
          continue;
        }
      }
    }
  }
}

function $Text$has_comma$(_text_0) {
  return $Text$has_comma$go$(_text_0, false);
}

function $Text$is_control$(_char_0) {
  const _x_0 = _char_0.codePointAt(0);
  const _x_1 = _char_0.codePointAt(0);
  const _x_2 = _char_0.codePointAt(0);
  const _x_3 = ($Bool$and$((_x_0 < 32), ($Bool$not$((_x_1 === 9)))));
  const _x_4 = (_x_2 === 127);
  return (_x_3 || _x_4);
}

function $Text$control$go$($0, $1, $2) {
  for (;;) {
    {
      const _text_0 = $0;
      const _offset_0 = $1;
      const _found_0 = $2;
      if (_text_0 === "") {
        if (_found_0.$ === "Some") {
          const _at_0 = _found_0["value"];
          return {$: "Some", "value": _at_0};
        } else {
          return {$: "None"};
        }
      } else {
        const _char_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(0, 2) : _text_0[0]);
        const _rest_0 = (_text_0.codePointAt(0) > 0xFFFF ? _text_0.slice(2) : _text_0.slice(1));
        if (_found_0.$ === "Some") {
          const _at_1 = _found_0["value"];
          return {$: "Some", "value": _at_1};
        } else {
          $0 = _rest_0;
          $1 = nat_chk(_offset_0 + 1);
          $2 = ($Bool$pick$(($Text$is_control$(_char_0)), {$: "Some", "value": _offset_0}, {$: "None"}));
          continue;
        }
      }
    }
  }
}

function $Read$is_later$(_digits_0) {
  const _t_0 = _digits_0["head"];
  if (_t_0.$ === "src/hex.H0") {
    const _t_1 = _digits_0["tail"];
    const _t_2 = _t_1["head"];
    if (_t_2.$ === "src/hex.H0") {
      const _t_3 = _t_1["tail"];
      return {$: "Done", "value": false};
    } else {
      return {$: "Done", "value": true};
    }
  } else if (_t_0.$ === "src/hex.Hf") {
    const _t_4 = _digits_0["tail"];
    const _t_5 = _t_4["head"];
    if (_t_5.$ === "src/hex.Hf") {
      const _t_6 = _t_4["tail"];
      return {$: "Fail", "error": {$: "ForbiddenVersion"}};
    } else {
      return {$: "Done", "value": true};
    }
  } else {
    return {$: "Done", "value": true};
  }
}

function $Read$is_later$parsed$(_parsed_0) {
  const _digits_0 = _parsed_0["digits"];
  return $Read$is_later$(_digits_0);
}

function $Read$clean$(_found_0) {
  if (_found_0.$ === "None") {
    return {$: "Done", "value": {$: "Unit"}};
  } else {
    const _offset_0 = _found_0["value"];
    return {$: "Fail", "error": {$: "ControlCharacter", "offset": _offset_0}};
  }
}

function $Read$extension$(_rest_0) {
  if (_rest_0 === "") {
    return {$: "Done", "value": {$: "Unit"}};
  } else {
    const _char_0 = (_rest_0.codePointAt(0) > 0xFFFF ? _rest_0.slice(0, 2) : _rest_0[0]);
    const _tail_0 = (_rest_0.codePointAt(0) > 0xFFFF ? _rest_0.slice(2) : _rest_0.slice(1));
    return $Result$bind$(($Parse$separator_result$(_tail_0, ($Char$is_eq$(_char_0, "-")), 55)), run_clo((_x_0) => {
  return $Read$clean$(($Text$control$go$(_x_0, 56, {$: "None"})));
}));
  }
}

function $Read$prefix$(_text_0) {
  const _x_0 = ($String$drop$(($String$take$(_text_0, 55)), 2));
  return $Result$bind$(run_loop($TraceParentV00$parse$(("00" + _x_0))), run_clo((_x_1) => {
  return $Result$bind$(run_loop($Read$extension$(($String$drop$(_text_0, 55)))), run_clo((_x_2) => {
  return $Result$pure$(_x_1);
}));
}));
}

function $Read$by_version$(_later_0, _text_0) {
  if (!_later_0) {
    return $TraceParentV00$parse$(_text_0);
  } else {
    return $Read$prefix$(_text_0);
  }
}

function $Read$known$(_text_0) {
  return $Result$bind$(run_loop($Parse$digits$(2, _text_0, 0)), run_clo((_x_0) => {
  return $Result$bind$(($Read$is_later$parsed$(_x_0)), run_clo((_x_1) => {
  return $Read$by_version$(_x_1, _text_0);
}));
}));
}

function $Read$invalid$(_result_0) {
  if (_result_0.$ === "Fail") {
    const _error_0 = _result_0["error"];
    return {$: "Fail", "error": {$: "InvalidTraceParent", "error": _error_0}};
  } else {
    const _value_0 = _result_0["value"];
    return {$: "Done", "value": _value_0};
  }
}

function $Read$single$(_combined_0, _text_0) {
  if (_combined_0) {
    return {$: "Fail", "error": {$: "RepeatedTraceParent"}};
  } else {
    return $Read$invalid$(run_loop($Read$known$(_text_0)));
  }
}

function $Read$trimmed$(_text_0) {
  return $Read$single$(($Text$has_comma$(_text_0)), _text_0);
}

function $Read$within$(_fits_0, _value_0) {
  if (_fits_0.$ === "None") {
    return {$: "Fail", "error": {$: "TraceParentTooLarge"}};
  } else {
    return $Read$trimmed$(($Text$trim_ows$(_value_0)));
  }
}

function $TraceParent$read$(_limits_0, _value_0) {
  return $Read$within$(($Utf8$left$(_value_0, {$: "Some", "value": ($Limits$traceparent_input$(_limits_0))})), _value_0);
}

function $Extract$ignored$(_states_0) {
  if (_states_0.$ === "Nil") {
    return {$: "StateAbsent"};
  } else {
    return {$: "StateIgnored"};
  }
}

function $Extract$kept$(_base_0, _parent_0, _states_0) {
  return {$: "Extraction", "context": _base_0, "parent": _parent_0, "state": ($Extract$ignored$(_states_0))};
}

function $Extract$incoming$(_remote_0, _state_0, _received_0) {
  return {$: "Some", "value": {$: "IncomingBase", "incoming": {$: "IncomingContext", "context": _remote_0, "state": _state_0, "received": _received_0}}};
}

function $Extract$parsed$(_parsed_0, _remote_0, _text_0, _states_0) {
  if (_parsed_0.$ === "Fail") {
    const _error_0 = _parsed_0["error"];
    return {$: "Extraction", "context": ($Extract$incoming$(_remote_0, ($TraceState$empty$()), {$: "None"})), "parent": {$: "TraceParentAccepted"}, "state": {$: "StateDiscarded", "error": _error_0}};
  } else {
    const _state_0 = _parsed_0["value"];
    return {$: "Extraction", "context": ($Extract$incoming$(_remote_0, _state_0, {$: "Some", "value": {$: "ReceivedPair", "traceparent": _text_0, "tracestate": _states_0}})), "parent": {$: "TraceParentAccepted"}, "state": {$: "StateAccepted"}};
  }
}

function $Extract$state$(_limits_0, _states_0, _remote_0, _text_0) {
  if (_states_0.$ === "Nil") {
    return {$: "Extraction", "context": ($Extract$incoming$(_remote_0, ($TraceState$empty$()), {$: "Some", "value": {$: "ReceivedPair", "traceparent": _text_0, "tracestate": {$: "Nil"}}})), "parent": {$: "TraceParentAccepted"}, "state": {$: "StateAbsent"}};
  } else {
    const _field_0 = _states_0["head"];
    const _rest_0 = _states_0["tail"];
    return $Extract$parsed$(($TraceState$parse_fields$(_limits_0, {$: "Con", "head": _field_0, "tail": _rest_0})), _remote_0, _text_0, {$: "Con", "head": _field_0, "tail": _rest_0});
  }
}

function $Extract$read$(_read_0, _value_0, _limits_0, _states_0, _base_0) {
  if (_read_0.$ === "Fail") {
    const _error_0 = _read_0["error"];
    return $Extract$kept$(_base_0, {$: "TraceParentRejected", "error": _error_0}, _states_0);
  } else {
    const _known_0 = _read_0["value"];
    return $Extract$state$(_limits_0, _states_0, ($RemoteContext$from_traceparent$(_known_0)), ($Text$trim_ows$(_value_0)));
  }
}

function $Extract$parents$(_limits_0, _parents_0, _states_0, _base_0) {
  if (_parents_0.$ === "Nil") {
    return $Extract$kept$(_base_0, {$: "TraceParentAbsent"}, _states_0);
  } else {
    const _value_0 = _parents_0["head"];
    const _t_0 = _parents_0["tail"];
    if (_t_0.$ === "Nil") {
      return $Extract$read$(($TraceParent$read$(_limits_0, _value_0)), _value_0, _limits_0, _states_0, _base_0);
    } else {
      return $Extract$kept$(_base_0, {$: "TraceParentRejected", "error": {$: "RepeatedTraceParent"}}, _states_0);
    }
  }
}

function $Context$extract$(_limits_0, _carrier_0, _base_0) {
  return $Extract$parents$(_limits_0, ($Carrier$values$(_carrier_0, ($Carrier$traceparent_name$()))), ($Carrier$values$(_carrier_0, ($Carrier$tracestate_name$()))), _base_0);
}

function $Extraction$context$(_extraction_0) {
  const _context_0 = _extraction_0["context"];
  return _context_0;
}

function $Extraction$parent$(_extraction_0) {
  const _parent_0 = _extraction_0["parent"];
  return _parent_0;
}

function $Extraction$state$(_extraction_0) {
  const _state_0 = _extraction_0["state"];
  return _state_0;
}

function $Extraction$incoming$base$(_context_0) {
  if (_context_0.$ === "Some") {
    const _t_0 = _context_0["value"];
    if (_t_0.$ === "IncomingBase") {
      const _incoming_0 = _t_0["incoming"];
      return {$: "Some", "value": _incoming_0};
    } else {
      return {$: "None"};
    }
  } else {
    return {$: "None"};
  }
}

function $Extraction$incoming$of$(_parent_0, _context_0) {
  if (_parent_0.$ === "TraceParentAccepted") {
    return $Extraction$incoming$base$(_context_0);
  } else if (_parent_0.$ === "TraceParentAbsent") {
    return {$: "None"};
  } else {
    return {$: "None"};
  }
}

function $Extraction$incoming$(_extraction_0) {
  const _context_0 = _extraction_0["context"];
  const _parent_0 = _extraction_0["parent"];
  return $Extraction$incoming$of$(_parent_0, _context_0);
}

function $IncomingContext$context$(_incoming_0) {
  const _context_0 = _incoming_0["context"];
  return _context_0;
}

function $IncomingContext$state$(_incoming_0) {
  const _state_0 = _incoming_0["state"];
  return _state_0;
}

function $IncomingContext$received$(_incoming_0) {
  const _received_0 = _incoming_0["received"];
  return _received_0;
}

function $IncomingContext$parent$(_incoming_0) {
  return {$: "RemoteParent", "context": ($IncomingContext$context$(_incoming_0))};
}

function $IncomingContext$from_remote$(_context_0, _state_0) {
  return {$: "IncomingContext", "context": _context_0, "state": _state_0, "received": {$: "None"}};
}

function $ReceivedPair$traceparent$(_pair_0) {
  const _traceparent_0 = _pair_0["traceparent"];
  return _traceparent_0;
}

function $ReceivedPair$tracestate$(_pair_0) {
  const _tracestate_0 = _pair_0["tracestate"];
  return _tracestate_0;
}

function $BaseContext$parent$(_base_0) {
  if (_base_0.$ === "IncomingBase") {
    const _incoming_0 = _base_0["incoming"];
    return $IncomingContext$parent$(_incoming_0);
  } else {
    const _outgoing_0 = _base_0["outgoing"];
    return {$: "LocalParent", "context": ($OutgoingContext$context$(_outgoing_0))};
  }
}

function $BaseContext$state$(_base_0) {
  if (_base_0.$ === "IncomingBase") {
    const _incoming_0 = _base_0["incoming"];
    return $IncomingContext$state$(_incoming_0);
  } else {
    const _outgoing_0 = _base_0["outgoing"];
    return $OutgoingContext$state$(_outgoing_0);
  }
}

function $TraceParentError$show$(_error_0) {
  if (_error_0.$ === "RepeatedTraceParent") {
    return "RepeatedTraceParent";
  } else if (_error_0.$ === "TraceParentTooLarge") {
    return "TraceParentTooLarge";
  } else {
    const _reason_0 = _error_0["error"];
    const _x_0 = ($Error$show$(_reason_0));
    return ("InvalidTraceParent " + _x_0);
  }
}

function $TraceParentOutcome$show$(_outcome_0) {
  if (_outcome_0.$ === "TraceParentAccepted") {
    return "TraceParentAccepted";
  } else if (_outcome_0.$ === "TraceParentAbsent") {
    return "TraceParentAbsent";
  } else {
    const _error_0 = _outcome_0["error"];
    const _x_0 = ($TraceParentError$show$(_error_0));
    return ("TraceParentRejected " + _x_0);
  }
}

function $StateOutcome$show$(_outcome_0) {
  if (_outcome_0.$ === "StateAbsent") {
    return "StateAbsent";
  } else if (_outcome_0.$ === "StateAccepted") {
    return "StateAccepted";
  } else if (_outcome_0.$ === "StateDiscarded") {
    const _error_0 = _outcome_0["error"];
    const _x_0 = ($StateError$show$(_error_0));
    return ("StateDiscarded " + _x_0);
  } else {
    return "StateIgnored";
  }
}

function $Extraction$show$(_extraction_0) {
  const _parent_0 = _extraction_0["parent"];
  const _state_0 = _extraction_0["state"];
  const _x_0 = ($StateOutcome$show$(_state_0));
  const _x_1 = ($TraceParentOutcome$show$(_parent_0));
  const _x_2 = (", " + _x_0);
  return (_x_1 + _x_2);
}

function $Carrier$is_context$(_name_0) {
  const _x_0 = ($Carrier$named$(($Carrier$traceparent_name$()), _name_0));
  const _x_1 = ($Carrier$named$(($Carrier$tracestate_name$()), _name_0));
  return (_x_0 || _x_1);
}

function $Carrier$keep_unrelated$(_context_field_0, _header_0, _kept_0) {
  if (_context_field_0) {
    return _kept_0;
  } else {
    return {$: "Con", "head": _header_0, "tail": _kept_0};
  }
}

function $Carrier$unrelated$go$($0, $1) {
  for (;;) {
    {
      const _carrier_0 = $0;
      const _kept_0 = $1;
      if (_carrier_0.$ === "Nil") {
        return _kept_0;
      } else {
        const _header_0 = _carrier_0["head"];
        const _rest_0 = _carrier_0["tail"];
        $0 = _rest_0;
        $1 = ($Carrier$keep_unrelated$(($Carrier$is_context$(($Header$name$(_header_0)))), _header_0, _kept_0));
        continue;
      }
    }
  }
}

function $Carrier$replace$(_carrier_0, _fields_0) {
  return $List$reverse$go$(($Carrier$unrelated$go$(_carrier_0, {$: "Nil"})), _fields_0);
}

function $Context$field_names$() {
  return {$: "Con", "head": ($Carrier$traceparent_name$()), "tail": {$: "Con", "head": ($Carrier$tracestate_name$()), "tail": {$: "Nil"}}};
}

function $Carrier$context_fields$(_traceparent_0, _tracestate_0) {
  return {$: "Con", "head": {$: "Header", "name": ($Carrier$traceparent_name$()), "value": _traceparent_0}, "tail": ($Bool$pick$(($String$is_empty$(_tracestate_0)), {$: "Nil"}, {$: "Con", "head": {$: "Header", "name": ($Carrier$tracestate_name$()), "value": _tracestate_0}, "tail": {$: "Nil"}}))};
}

function $Context$clear$(_carrier_0) {
  return $Carrier$replace$(_carrier_0, {$: "Nil"});
}

function $Injection$of$(_carrier_0, _emission_0) {
  const _traceparent_0 = _emission_0["traceparent"];
  const _tracestate_0 = _emission_0["tracestate"];
  const _dropped_0 = _emission_0["dropped"];
  return {$: "Injection", "carrier": ($Carrier$replace$(_carrier_0, ($Carrier$context_fields$(_traceparent_0, _tracestate_0)))), "dropped": _dropped_0};
}

function $Context$inject$(_limits_0, _outgoing_0, _carrier_0) {
  return $Injection$of$(_carrier_0, ($OutgoingContext$emit$(_limits_0, _outgoing_0)));
}

function $Injection$carrier$(_injection_0) {
  const _carrier_0 = _injection_0["carrier"];
  return _carrier_0;
}

function $Injection$dropped$(_injection_0) {
  const _dropped_0 = _injection_0["dropped"];
  return _dropped_0;
}

function $Text$joined$go$($0, $1) {
  for (;;) {
    {
      const _fields_0 = $0;
      const _done_0 = $1;
      if (_fields_0.$ === "Nil") {
        return _done_0;
      } else {
        const _field_0 = _fields_0["head"];
        const _rest_0 = _fields_0["tail"];
        $0 = _rest_0;
        $1 = ($String$reverse$go$(_field_0, ("," + _done_0)));
        continue;
      }
    }
  }
}

function $Text$joined$(_fields_0) {
  if (_fields_0.$ === "Nil") {
    return "";
  } else {
    const _field_0 = _fields_0["head"];
    const _rest_0 = _fields_0["tail"];
    return $String$reverse$(($Text$joined$go$(_rest_0, ($String$reverse$go$(_field_0, "")))));
  }
}

function $Forward$carrier$(_carrier_0, _traceparent_0, _tracestate_0) {
  return $Carrier$replace$(_carrier_0, ($Carrier$context_fields$(_traceparent_0, ($Text$joined$(_tracestate_0)))));
}

function $Forward$state$(_parsed_0, _carrier_0, _traceparent_0, _tracestate_0) {
  if (_parsed_0.$ === "Fail") {
    const _error_0 = _parsed_0["error"];
    return {$: "Fail", "error": {$: "InvalidForwardState", "error": _error_0}};
  } else {
    return {$: "Done", "value": ($Forward$carrier$(_carrier_0, _traceparent_0, _tracestate_0))};
  }
}

function $Forward$parent$(_read_0, _limits_0, _carrier_0, _traceparent_0, _tracestate_0) {
  if (_read_0.$ === "Fail") {
    const _error_0 = _read_0["error"];
    return {$: "Fail", "error": {$: "InvalidForwardParent", "error": _error_0}};
  } else {
    return $Forward$state$(($TraceState$parse_fields$(_limits_0, _tracestate_0)), _carrier_0, _traceparent_0, _tracestate_0);
  }
}

function $Forward$fits$(_fits_0, _limits_0, _carrier_0, _traceparent_0, _tracestate_0) {
  if (_fits_0.$ === "None") {
    return {$: "Fail", "error": {$: "ForwardTooLarge"}};
  } else {
    return $Forward$parent$(($TraceParent$read$(_limits_0, _traceparent_0)), _limits_0, _carrier_0, _traceparent_0, _tracestate_0);
  }
}

function $Forward$pair$(_limits_0, _received_0, _carrier_0) {
  if (_received_0.$ === "None") {
    return {$: "Fail", "error": {$: "NothingToForward"}};
  } else {
    const _t_0 = _received_0["value"];
    const _traceparent_0 = _t_0["traceparent"];
    const _tracestate_0 = _t_0["tracestate"];
    return $Forward$fits$(($Utf8$left_fields$(_tracestate_0, {$: "Some", "value": ($Limits$tracestate_output$(_limits_0))})), _limits_0, _carrier_0, _traceparent_0, _tracestate_0);
  }
}

function $Context$forward$(_limits_0, _incoming_0, _carrier_0) {
  return $Forward$pair$(_limits_0, ($IncomingContext$received$(_incoming_0)), _carrier_0);
}

function $ForwardError$show$(_error_0) {
  if (_error_0.$ === "NothingToForward") {
    return "NothingToForward";
  } else if (_error_0.$ === "ForwardTooLarge") {
    return "ForwardTooLarge";
  } else if (_error_0.$ === "InvalidForwardParent") {
    const _reason_0 = _error_0["error"];
    const _x_0 = ($TraceParentError$show$(_reason_0));
    return ("InvalidForwardParent " + _x_0);
  } else {
    const _reason_1 = _error_0["error"];
    const _x_1 = ($StateError$show$(_reason_1));
    return ("InvalidForwardState " + _x_1);
  }
}

function $FailurePolicy$result$(_policy_0, _A_0) {
  if (_policy_0.$ === "Lenient") {
    return _A_0;
  } else {
    return null;
  }
}

function $Policy$apply$(_policy_0, _strict_0, _value_0) {
  if (_policy_0.$ === "Lenient") {
    return _value_0;
  } else {
    return run_tail(_strict_0, _value_0);
  }
}

function $Policy$apply$done$(_policy_0, _strict_0, _done_0) {
  const _source_0 = _done_0["fst"];
  const _value_0 = _done_0["snd"];
  return {$: "Tuple", "fst": _source_0, "snd": run_loop($Policy$apply$(_policy_0, _strict_0, _value_0))};
}

function $Serve$sampled$(_sampling_0) {
  return $Sampling$resolve$(_sampling_0, false);
}

function $Serve$from_child$(_state_0, _received_0, _result_0) {
  if (_result_0.$ === "Fail") {
    const _error_0 = _result_0["error"];
    return {$: "Untraced", "error": _error_0, "received": _received_0};
  } else {
    const _context_0 = _result_0["value"];
    return {$: "Operating", "origin": {$: "Continued"}, "outgoing": ($OutgoingContext$with_state$(_context_0, _state_0)), "received": _received_0};
  }
}

function $Serve$from_start$(_origin_0, _result_0) {
  if (_result_0.$ === "Fail") {
    const _error_0 = _result_0["error"];
    return {$: "Untraced", "error": _error_0, "received": {$: "None"}};
  } else {
    const _context_0 = _result_0["value"];
    return {$: "Operating", "origin": _origin_0, "outgoing": ($OutgoingContext$new$(_context_0)), "received": {$: "None"}};
  }
}

function $Serve$replaced$(_base_0) {
  if (_base_0.$ === "IncomingBase") {
    const _incoming_0 = _base_0["incoming"];
    return $IncomingContext$context$(_incoming_0);
  } else {
    const _outgoing_0 = _base_0["outgoing"];
    return $RemoteContext$from_traceparent$(($LocalContext$to_traceparent$(($OutgoingContext$context$(_outgoing_0)))));
  }
}

function $Serve$usable$(_base_0, _received_0, _reception_0, _sampling_0) {
  if (_reception_0.$ === "Continue") {
    return {$: "ContinuePlan", "generation": ($Generation$child$(($BaseContext$parent$(_base_0)), _sampling_0)), "state": ($BaseContext$state$(_base_0)), "received": _received_0};
  } else {
    return {$: "StartPlan", "generation": ($Generation$restart$(($Serve$replaced$(_base_0)), ($Serve$sampled$(_sampling_0)))), "origin": {$: "Restarted"}};
  }
}

function $Serve$kept$(_context_0, _received_0, _reception_0, _sampling_0) {
  if (_context_0.$ === "None") {
    return {$: "StartPlan", "generation": ($Generation$root$(($Serve$sampled$(_sampling_0)))), "origin": {$: "Started"}};
  } else {
    const _base_0 = _context_0["value"];
    return $Serve$usable$(_base_0, _received_0, _reception_0, _sampling_0);
  }
}

function $ServicePlan$new$(_extraction_0, _reception_0, _sampling_0) {
  return $Serve$kept$(($Extraction$context$(_extraction_0)), ($Extraction$incoming$(_extraction_0)), _reception_0, _sampling_0);
}

function $ServicePlan$generation$(_plan_0) {
  if (_plan_0.$ === "ContinuePlan") {
    const _generation_0 = _plan_0["generation"];
    return _generation_0;
  } else {
    const _generation_1 = _plan_0["generation"];
    return _generation_1;
  }
}

function $ServicePlan$service$(_plan_0, _result_0) {
  if (_plan_0.$ === "ContinuePlan") {
    const _state_0 = _plan_0["state"];
    const _received_0 = _plan_0["received"];
    return $Serve$from_child$(_state_0, _received_0, _result_0);
  } else {
    const _origin_0 = _plan_0["origin"];
    return $Serve$from_start$(_origin_0, _result_0);
  }
}

function $Serve$finish$(_plan_0, _done_0) {
  const _source_0 = _done_0["fst"];
  const _result_0 = _done_0["snd"];
  return {$: "Tuple", "fst": _source_0, "snd": ($ServicePlan$service$(_plan_0, _result_0))};
}

function $Serve$strict$(_service_0) {
  if (_service_0.$ === "Operating") {
    const _origin_0 = _service_0["origin"];
    const _outgoing_0 = _service_0["outgoing"];
    const _received_0 = _service_0["received"];
    return {$: "Done", "value": {$: "Operating", "origin": _origin_0, "outgoing": _outgoing_0, "received": _received_0}};
  } else {
    const _error_0 = _service_0["error"];
    return {$: "Fail", "error": _error_0};
  }
}

function $Send$forwarded$(_result_0, _error_0, _carrier_0) {
  if (_result_0.$ === "Done") {
    const _forwarded_0 = _result_0["value"];
    return {$: "Forwarded", "carrier": _forwarded_0, "error": _error_0};
  } else {
    const _reason_0 = _result_0["error"];
    return {$: "NoContext", "carrier": ($Context$clear$(_carrier_0)), "error": _error_0, "reason": {$: "ForwardFailed", "error": _reason_0}};
  }
}

function $Send$fallback$(_limits_0, _received_0, _error_0, _carrier_0) {
  if (_received_0.$ === "None") {
    return {$: "NoContext", "carrier": ($Context$clear$(_carrier_0)), "error": _error_0, "reason": {$: "NothingKept"}};
  } else {
    const _incoming_0 = _received_0["value"];
    return $Send$forwarded$(($Context$forward$(_limits_0, _incoming_0, _carrier_0)), _error_0, _carrier_0);
  }
}

function $Send$of$(_limits_0, _outgoing_0, _received_0, _carrier_0, _result_0) {
  if (_result_0.$ === "Fail") {
    const _error_0 = _result_0["error"];
    return $Send$fallback$(_limits_0, _received_0, _error_0, _carrier_0);
  } else {
    const _operation_0 = _result_0["value"];
    return {$: "Fresh", "operation": _operation_0, "injection": ($Context$inject$(_limits_0, ($OutgoingContext$with_state$(_operation_0, ($OutgoingContext$state$(_outgoing_0)))), _carrier_0))};
  }
}

function $SendPlan$new$(_limits_0, _service_0, _sampling_0, _carrier_0) {
  if (_service_0.$ === "Operating") {
    const _outgoing_0 = _service_0["outgoing"];
    const _received_0 = _service_0["received"];
    return {$: "SendChild", "generation": ($Generation$child$({$: "LocalParent", "context": ($OutgoingContext$context$(_outgoing_0))}, _sampling_0)), "limits": _limits_0, "outgoing": _outgoing_0, "received": _received_0, "carrier": _carrier_0};
  } else {
    const _error_0 = _service_0["error"];
    const _received_1 = _service_0["received"];
    return {$: "SendFallback", "error": _error_0, "limits": _limits_0, "received": _received_1, "carrier": _carrier_0};
  }
}

function $SendPlan$generation$(_plan_0) {
  if (_plan_0.$ === "SendChild") {
    const _generation_0 = _plan_0["generation"];
    return _generation_0;
  } else {
    const _error_0 = _plan_0["error"];
    return {$: "Generation", "fuel": 0, "step": {$: "Failed", "error": _error_0}};
  }
}

function $SendPlan$sent$(_plan_0, _result_0) {
  if (_plan_0.$ === "SendChild") {
    const _limits_0 = _plan_0["limits"];
    const _outgoing_0 = _plan_0["outgoing"];
    const _received_0 = _plan_0["received"];
    const _carrier_0 = _plan_0["carrier"];
    return $Send$of$(_limits_0, _outgoing_0, _received_0, _carrier_0, _result_0);
  } else {
    const _error_0 = _plan_0["error"];
    const _limits_1 = _plan_0["limits"];
    const _received_1 = _plan_0["received"];
    const _carrier_1 = _plan_0["carrier"];
    return $Send$fallback$(_limits_1, _received_1, _error_0, _carrier_1);
  }
}

function $Send$finish$(_plan_0, _done_0) {
  const _source_0 = _done_0["fst"];
  const _result_0 = _done_0["snd"];
  return {$: "Tuple", "fst": _source_0, "snd": ($SendPlan$sent$(_plan_0, _result_0))};
}

function $Send$strict$(_sent_0) {
  if (_sent_0.$ === "Fresh") {
    const _operation_0 = _sent_0["operation"];
    const _injection_0 = _sent_0["injection"];
    return {$: "Done", "value": {$: "Fresh", "operation": _operation_0, "injection": _injection_0}};
  } else if (_sent_0.$ === "Forwarded") {
    const _error_0 = _sent_0["error"];
    return {$: "Fail", "error": _error_0};
  } else {
    const _error_1 = _sent_0["error"];
    return {$: "Fail", "error": _error_1};
  }
}

function $Origin$show$(_origin_0) {
  if (_origin_0.$ === "Continued") {
    return "Continued";
  } else if (_origin_0.$ === "Started") {
    return "Started";
  } else {
    return "Restarted";
  }
}

function $Service$origin$(_service_0) {
  if (_service_0.$ === "Operating") {
    const _origin_0 = _service_0["origin"];
    return {$: "Some", "value": _origin_0};
  } else {
    return {$: "None"};
  }
}

function $Service$outgoing$(_service_0) {
  if (_service_0.$ === "Operating") {
    const _outgoing_0 = _service_0["outgoing"];
    return {$: "Some", "value": _outgoing_0};
  } else {
    return {$: "None"};
  }
}

function $Service$error$(_service_0) {
  if (_service_0.$ === "Operating") {
    return {$: "None"};
  } else {
    const _error_0 = _service_0["error"];
    return {$: "Some", "value": _error_0};
  }
}

function $Service$set$(_service_0, _key_0, _value_0) {
  if (_service_0.$ === "Operating") {
    const _origin_0 = _service_0["origin"];
    const _outgoing_0 = _service_0["outgoing"];
    const _received_0 = _service_0["received"];
    return {$: "Operating", "origin": _origin_0, "outgoing": ($OutgoingContext$set$(_outgoing_0, _key_0, _value_0)), "received": _received_0};
  } else {
    const _error_0 = _service_0["error"];
    const _received_1 = _service_0["received"];
    return {$: "Untraced", "error": _error_0, "received": _received_1};
  }
}

function $Service$remove$(_service_0, _key_0) {
  if (_service_0.$ === "Operating") {
    const _origin_0 = _service_0["origin"];
    const _outgoing_0 = _service_0["outgoing"];
    const _received_0 = _service_0["received"];
    return {$: "Operating", "origin": _origin_0, "outgoing": ($OutgoingContext$remove$(_outgoing_0, _key_0)), "received": _received_0};
  } else {
    const _error_0 = _service_0["error"];
    const _received_1 = _service_0["received"];
    return {$: "Untraced", "error": _error_0, "received": _received_1};
  }
}

function $Service$show$(_service_0) {
  if (_service_0.$ === "Operating") {
    const _origin_0 = _service_0["origin"];
    return $Origin$show$(_origin_0);
  } else {
    const _error_0 = _service_0["error"];
    const _x_0 = ($GenerationError$show$(_error_0));
    return ("Untraced " + _x_0);
  }
}

function $Unforwarded$show$(_reason_0) {
  if (_reason_0.$ === "NothingKept") {
    return "NothingKept";
  } else {
    const _error_0 = _reason_0["error"];
    return $ForwardError$show$(_error_0);
  }
}

function $Sent$carrier$(_sent_0) {
  if (_sent_0.$ === "Fresh") {
    const _injection_0 = _sent_0["injection"];
    return $Injection$carrier$(_injection_0);
  } else if (_sent_0.$ === "Forwarded") {
    const _carrier_0 = _sent_0["carrier"];
    return _carrier_0;
  } else {
    const _carrier_1 = _sent_0["carrier"];
    return _carrier_1;
  }
}

function $Sent$operation$(_sent_0) {
  if (_sent_0.$ === "Fresh") {
    const _operation_0 = _sent_0["operation"];
    return {$: "Some", "value": _operation_0};
  } else if (_sent_0.$ === "Forwarded") {
    return {$: "None"};
  } else {
    return {$: "None"};
  }
}

function $Sent$error$(_sent_0) {
  if (_sent_0.$ === "Fresh") {
    return {$: "None"};
  } else if (_sent_0.$ === "Forwarded") {
    const _error_0 = _sent_0["error"];
    return {$: "Some", "value": _error_0};
  } else {
    const _error_1 = _sent_0["error"];
    return {$: "Some", "value": _error_1};
  }
}

function $Sent$dropped$(_sent_0) {
  if (_sent_0.$ === "Fresh") {
    const _injection_0 = _sent_0["injection"];
    return $Injection$dropped$(_injection_0);
  } else if (_sent_0.$ === "Forwarded") {
    return {$: "Nil"};
  } else {
    return {$: "Nil"};
  }
}

function $Send$fresh$(_dropped_0) {
  if (_dropped_0.$ === "Nil") {
    return "Fresh";
  } else {
    return "Fresh, truncated";
  }
}

function $Sent$show$(_sent_0) {
  if (_sent_0.$ === "Fresh") {
    const _injection_0 = _sent_0["injection"];
    return $Send$fresh$(($Injection$dropped$(_injection_0)));
  } else if (_sent_0.$ === "Forwarded") {
    const _error_0 = _sent_0["error"];
    const _x_0 = ($GenerationError$show$(_error_0));
    return ("Forwarded after " + _x_0);
  } else {
    const _error_1 = _sent_0["error"];
    const _reason_0 = _sent_0["reason"];
    const _x_1 = ($Unforwarded$show$(_reason_0));
    const _x_2 = ($GenerationError$show$(_error_1));
    const _x_3 = (", " + _x_1);
    const _x_4 = (_x_2 + _x_3);
    return ("NoContext after " + _x_4);
  }
}

function $Bool$pick$(_c_0, _a_0, _b_0) {
  if (!_c_0) {
    return _b_0;
  } else {
    return _a_0;
  }
}

function $Char$is_eq$(_a_0, _b_0) {
  const _x_0 = _a_0.codePointAt(0);
  const _x_1 = _b_0.codePointAt(0);
  return (_x_0 === _x_1);
}

function $Bool$and$(_a_0, _b_0) {
  if (!_a_0) {
    return false;
  } else {
    return _b_0;
  }
}

function $Word$zero$(_n_0) {
  if (_n_0 === 0) {
    return {$: "WNil"};
  } else {
    const _p_0 = (_n_0 - 1);
    return {$: "WCon", "head": false, "tail": ($Word$zero$(_p_0))};
  }
}

function $Result$bind$(_r_0, _f_0) {
  if (_r_0.$ === "Fail") {
    const _e_0 = _r_0["error"];
    return {$: "Fail", "error": _e_0};
  } else {
    const _x_0 = _r_0["value"];
    return run_tail(_f_0, _x_0);
  }
}

function $Result$pure$(_x_0) {
  return {$: "Done", "value": _x_0};
}

function $String$eq$(_a_0, _b_0) {
  return $Cmp$is_eq$(($String$order$(_a_0, _b_0)));
}

function $Bool$to_u32$(_b_0) {
  if (!_b_0) {
    return 0;
  } else {
    return 1;
  }
}

function $Drive$run$1260$($0, $1) {
  for (;;) {
    {
      const _fuel_0 = $0;
      const _current_0 = $1;
      if (_fuel_0 === 0) {
        const _tape_0 = _current_0["fst"];
        const _t_0 = _current_0["snd"];
        const _step_0 = _t_0["fst"];
        const _t_1 = _t_0["snd"];
        if (_t_1.$ === "None") {
          return {$: "Tuple", "fst": _tape_0, "snd": _step_0};
        } else {
          return {$: "Tuple", "fst": _tape_0, "snd": _step_0};
        }
      } else {
        const _p_0 = (_fuel_0 - 1);
        const _tape_1 = _current_0["fst"];
        const _t_2 = _current_0["snd"];
        const _step_1 = _t_2["fst"];
        const _t_3 = _t_2["snd"];
        if (_t_3.$ === "None") {
          return {$: "Tuple", "fst": _tape_1, "snd": _step_1};
        } else {
          const _draw_1 = _t_3["value"];
          $0 = _p_0;
          $1 = ($Drive$fed$1260$(($Tape$next$(_tape_1)), _draw_1));
          continue;
        }
      }
    }
  }
}

function $Drive$ended$1260$(_result_0) {
  const _step_0 = _result_0["snd"];
  return $Maybe$is_none$(($TraceStep$waiting$(_step_0)));
}

function $Drive$outcome$1260$(_done_0) {
  const _state_0 = _done_0["fst"];
  const _step_0 = _done_0["snd"];
  return {$: "Tuple", "fst": _state_0, "snd": ($TraceDraw$result$(_step_0))};
}

function $Drive$run$1261$($0, $1) {
  for (;;) {
    {
      const _fuel_0 = $0;
      const _current_0 = $1;
      if (_fuel_0 === 0) {
        const _tape_0 = _current_0["fst"];
        const _t_0 = _current_0["snd"];
        const _step_0 = _t_0["fst"];
        const _t_1 = _t_0["snd"];
        if (_t_1.$ === "None") {
          return {$: "Tuple", "fst": _tape_0, "snd": _step_0};
        } else {
          return {$: "Tuple", "fst": _tape_0, "snd": _step_0};
        }
      } else {
        const _p_0 = (_fuel_0 - 1);
        const _tape_1 = _current_0["fst"];
        const _t_2 = _current_0["snd"];
        const _step_1 = _t_2["fst"];
        const _t_3 = _t_2["snd"];
        if (_t_3.$ === "None") {
          return {$: "Tuple", "fst": _tape_1, "snd": _step_1};
        } else {
          const _draw_1 = _t_3["value"];
          $0 = _p_0;
          $1 = ($Drive$fed$1261$(($Tape$next$(_tape_1)), _draw_1));
          continue;
        }
      }
    }
  }
}

function $Drive$ended$1261$(_result_0) {
  const _step_0 = _result_0["snd"];
  return $Maybe$is_none$(($SpanStep$waiting$(_step_0)));
}

function $Drive$outcome$1261$(_done_0) {
  const _state_0 = _done_0["fst"];
  const _step_0 = _done_0["snd"];
  return {$: "Tuple", "fst": _state_0, "snd": ($SpanDraw$result$(_step_0))};
}

function $Drive$run$1262$($0, $1) {
  for (;;) {
    {
      const _fuel_0 = $0;
      const _current_0 = $1;
      if (_fuel_0 === 0) {
        const _tape_0 = _current_0["fst"];
        const _t_0 = _current_0["snd"];
        const _step_0 = _t_0["fst"];
        const _t_1 = _t_0["snd"];
        if (_t_1.$ === "None") {
          return {$: "Tuple", "fst": _tape_0, "snd": _step_0};
        } else {
          return {$: "Tuple", "fst": _tape_0, "snd": _step_0};
        }
      } else {
        const _p_0 = (_fuel_0 - 1);
        const _tape_1 = _current_0["fst"];
        const _t_2 = _current_0["snd"];
        const _step_1 = _t_2["fst"];
        const _t_3 = _t_2["snd"];
        if (_t_3.$ === "None") {
          return {$: "Tuple", "fst": _tape_1, "snd": _step_1};
        } else {
          const _draw_1 = _t_3["value"];
          $0 = _p_0;
          $1 = ($Drive$fed$1262$(($Tape$next$(_tape_1)), _draw_1));
          continue;
        }
      }
    }
  }
}

function $Drive$ended$1262$(_result_0) {
  const _step_0 = _result_0["snd"];
  return $Maybe$is_none$(($Step$waiting$(_step_0)));
}

function $Drive$outcome$1262$(_done_0) {
  const _state_0 = _done_0["fst"];
  const _step_0 = _done_0["snd"];
  return {$: "Tuple", "fst": _state_0, "snd": ($Step$result$(_step_0))};
}

function $IO$pure$(_x_0, _k_0) {
  return run_tail(_k_0, _x_0);
}

function $Nat$show$(_n_0) {
  const _m_0 = _n_0;
  return $Nat$show$fin$(_m_0, "", ($Nat$show$put$(nat_divmod(_m_0, 10))));
}

function $U32$show$(_a_0) {
  const _b_0 = _a_0;
  return $U32$show$if$(_b_0, (_b_0 === 0));
}

function $Nat$is_ge$(_a_0, _b_0) {
  return $Cmp$is_ge$(cmp_new(_a_0, _b_0));
}

function $Bool$not$(_b_0) {
  if (!_b_0) {
    return true;
  } else {
    return false;
  }
}

function $List$append$(_xs_0, _ys_0) {
  if (_xs_0.$ === "Nil") {
    return _ys_0;
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    return {$: "Con", "head": _h_0, "tail": ($List$append$(_t_0, _ys_0))};
  }
}

function $Nat$is_le$(_a_0, _b_0) {
  return $Cmp$is_le$(cmp_new(_a_0, _b_0));
}

function $List$length$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return 0;
  } else {
    const _t_0 = _xs_0["tail"];
    return nat_chk(($List$length$(_t_0)) + 1);
  }
}

function $List$is_empty$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return true;
  } else {
    return false;
  }
}

function $String$reverse$(_s_0) {
  return $String$reverse$go$(_s_0, "");
}

function $List$take$(_xs_0, _n_0) {
  if (_xs_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    if (_n_0 === 0) {
      return {$: "Nil"};
    } else {
      const _p_0 = (_n_0 - 1);
      return {$: "Con", "head": _h_0, "tail": ($List$take$(_t_0, _p_0))};
    }
  }
}

function $Nat$is_gt$(_a_0, _b_0) {
  return $Cmp$is_gt$(cmp_new(_a_0, _b_0));
}

function $Char$to_lower$(_c_0) {
  const _x_0 = ($Bool$to_u32$(($Char$is_upper$(_c_0))));
  const _x_1 = _c_0.codePointAt(0);
  const _x_2 = (Math.imul(_x_0, 32) >>> 0);
  return char_new(((_x_1 + _x_2) >>> 0));
}

function $List$reverse$(_xs_0) {
  return $List$reverse$go$(_xs_0, {$: "Nil"});
}

function $String$drop$($0, $1) {
  for (;;) {
    {
      const _s_0 = $0;
      const _n_0 = $1;
      if (_s_0 === "") {
        return "";
      } else {
        const _h_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
        const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
        if (_n_0 === 0) {
          return (_h_0 + _t_0);
        } else {
          const _p_0 = (_n_0 - 1);
          $0 = _t_0;
          $1 = _p_0;
          continue;
        }
      }
    }
  }
}

function $String$take$(_s_0, _n_0) {
  if (_s_0 === "") {
    return "";
  } else {
    const _h_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
    const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
    if (_n_0 === 0) {
      return "";
    } else {
      const _p_0 = (_n_0 - 1);
      return (_h_0 + ($String$take$(_t_0, _p_0)));
    }
  }
}

function $List$reverse$go$($0, $1) {
  for (;;) {
    {
      const _xs_0 = $0;
      const _acc_0 = $1;
      if (_xs_0.$ === "Nil") {
        return _acc_0;
      } else {
        const _h_0 = _xs_0["head"];
        const _t_0 = _xs_0["tail"];
        $0 = _t_0;
        $1 = {$: "Con", "head": _h_0, "tail": _acc_0};
        continue;
      }
    }
  }
}

function $String$is_empty$(_s_0) {
  if (_s_0 === "") {
    return true;
  } else {
    return false;
  }
}

function $String$reverse$go$($0, $1) {
  for (;;) {
    {
      const _s_0 = $0;
      const _acc_0 = $1;
      if (_s_0 === "") {
        return _acc_0;
      } else {
        const _h_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(0, 2) : _s_0[0]);
        const _t_0 = (_s_0.codePointAt(0) > 0xFFFF ? _s_0.slice(2) : _s_0.slice(1));
        $0 = _t_0;
        $1 = (_h_0 + _acc_0);
        continue;
      }
    }
  }
}

function $Cmp$is_eq$(_c_0) {
  if (_c_0.$ === "EQ") {
    return true;
  } else {
    return false;
  }
}

function $String$order$(_a_0, _b_0) {
  return $Pair$snd$(($String$cmp$(_a_0, _b_0)));
}

function $Drive$fed$1260$(_got_0, _draw_0) {
  const _state_0 = _got_0["fst"];
  const _word_0 = _got_0["snd"];
  const _next_0 = ($TraceDraw$next$(_word_0, _draw_0));
  return {$: "Tuple", "fst": _state_0, "snd": {$: "Tuple", "fst": _next_0, "snd": ($TraceStep$waiting$(_next_0))}};
}

function $Maybe$is_none$(_m_0) {
  return $Bool$not$(($Maybe$is_some$(_m_0)));
}

function $Drive$fed$1261$(_got_0, _draw_0) {
  const _state_0 = _got_0["fst"];
  const _word_0 = _got_0["snd"];
  const _next_0 = ($SpanDraw$next$(_word_0, _draw_0));
  return {$: "Tuple", "fst": _state_0, "snd": {$: "Tuple", "fst": _next_0, "snd": ($SpanStep$waiting$(_next_0))}};
}

function $Drive$fed$1262$(_got_0, _draw_0) {
  const _state_0 = _got_0["fst"];
  const _word_0 = _got_0["snd"];
  const _next_0 = ($Draw$feed$(_word_0, _draw_0));
  return {$: "Tuple", "fst": _state_0, "snd": {$: "Tuple", "fst": _next_0, "snd": ($Step$waiting$(_next_0))}};
}

function $Nat$show$fin$($0, $1, $2) {
  let $pc = 0;
  for (;;) switch ($pc) {
    case 0: {
      const _g_0 = $0;
      const _acc_0 = $1;
      const _dq_0 = $2;
      const _d_0 = _dq_0["fst"];
      const _t_0 = _dq_0["snd"];
      if (_t_0 === 0) {
        return (_d_0 + _acc_0);
      } else {
        const _p_0 = (_t_0 - 1);
        $0 = _g_0;
        $1 = nat_chk(_p_0 + 1);
        $2 = (_d_0 + _acc_0);
        $pc = 1; continue;
      }
    }
    case 1: {
      const _f_0 = $0;
      const _n_0 = $1;
      const _acc_0 = $2;
      if (_f_0 === 0) {
        return _acc_0;
      } else {
        const _g_0 = (_f_0 - 1);
        $0 = _g_0;
        $1 = _acc_0;
        $2 = ($Nat$show$put$(nat_divmod(_n_0, 10)));
        $pc = 0; continue;
      }
    }
  }
}

function $Nat$show$put$(_qr_0) {
  const _q_0 = _qr_0["fst"];
  const _r_0 = _qr_0["snd"];
  const _x_0 = nat_chk(48 + _r_0);
  return {$: "Tuple", "fst": char_new((_x_0 >>> 0)), "snd": _q_0};
}

function $U32$show$if$(_a_0, _z_0) {
  if (_z_0) {
    return "0";
  } else {
    return $U32$show$go$(10, _a_0, "");
  }
}

function $Cmp$is_ge$(_c_0) {
  if (_c_0.$ === "LT") {
    return false;
  } else {
    return true;
  }
}

function $Cmp$is_le$(_c_0) {
  if (_c_0.$ === "GT") {
    return false;
  } else {
    return true;
  }
}

function $Cmp$is_gt$(_c_0) {
  if (_c_0.$ === "GT") {
    return true;
  } else {
    return false;
  }
}

function $Char$is_upper$(_c_0) {
  const _x_0 = _c_0.codePointAt(0);
  const _x_1 = _c_0.codePointAt(0);
  return $Bool$and$((_x_0 >= 65), (_x_1 <= 90));
}

function $Pair$snd$(_p_0) {
  const _b_0 = _p_0["snd"];
  return _b_0;
}

function $String$cmp$(_a_0, _b_0) {
  if (_a_0 === "") {
    if (_b_0 === "") {
      return {$: "Tuple", "fst": {$: "Tuple", "fst": "", "snd": ""}, "snd": {$: "EQ"}};
    } else {
      const _h_0 = (_b_0.codePointAt(0) > 0xFFFF ? _b_0.slice(0, 2) : _b_0[0]);
      const _t_0 = (_b_0.codePointAt(0) > 0xFFFF ? _b_0.slice(2) : _b_0.slice(1));
      return {$: "Tuple", "fst": {$: "Tuple", "fst": "", "snd": (_h_0 + _t_0)}, "snd": {$: "LT"}};
    }
  } else {
    const _h_1 = (_a_0.codePointAt(0) > 0xFFFF ? _a_0.slice(0, 2) : _a_0[0]);
    const _t_1 = (_a_0.codePointAt(0) > 0xFFFF ? _a_0.slice(2) : _a_0.slice(1));
    if (_b_0 === "") {
      return {$: "Tuple", "fst": {$: "Tuple", "fst": (_h_1 + _t_1), "snd": ""}, "snd": {$: "GT"}};
    } else {
      const _h2_0 = (_b_0.codePointAt(0) > 0xFFFF ? _b_0.slice(0, 2) : _b_0[0]);
      const _t2_0 = (_b_0.codePointAt(0) > 0xFFFF ? _b_0.slice(2) : _b_0.slice(1));
      return $String$cmp$fin$(_t_1, _t2_0, ($Char$cmp$(_h_1, _h2_0)));
    }
  }
}

function $Maybe$is_some$(_m_0) {
  if (_m_0.$ === "None") {
    return false;
  } else {
    return true;
  }
}

function $Nat$show$go$($0, $1, $2) {
  let $pc = 1;
  for (;;) switch ($pc) {
    case 0: {
      const _g_0 = $0;
      const _acc_0 = $1;
      const _dq_0 = $2;
      const _d_0 = _dq_0["fst"];
      const _t_0 = _dq_0["snd"];
      if (_t_0 === 0) {
        return (_d_0 + _acc_0);
      } else {
        const _p_0 = (_t_0 - 1);
        $0 = _g_0;
        $1 = nat_chk(_p_0 + 1);
        $2 = (_d_0 + _acc_0);
        $pc = 1; continue;
      }
    }
    case 1: {
      const _f_0 = $0;
      const _n_0 = $1;
      const _acc_0 = $2;
      if (_f_0 === 0) {
        return _acc_0;
      } else {
        const _g_0 = (_f_0 - 1);
        $0 = _g_0;
        $1 = _acc_0;
        $2 = ($Nat$show$put$(nat_divmod(_n_0, 10)));
        $pc = 0; continue;
      }
    }
  }
}

function $U32$show$go$($0, $1, $2, $3) {
  let $pc = 0;
  for (;;) switch ($pc) {
    case 0: {
      const _f_0 = $0;
      const _n_0 = $1;
      const _acc_0 = $2;
      if (_f_0 === 0) {
        return _acc_0;
      } else {
        const _g_0 = (_f_0 - 1);
        $0 = _g_0;
        $1 = _acc_0;
        $2 = _n_0;
        $3 = (_n_0 === 0);
        $pc = 1; continue;
      }
    }
    case 1: {
      const _g_0 = $0;
      const _acc_0 = $1;
      const _n_0 = $2;
      const _z_0 = $3;
      if (_z_0) {
        return _acc_0;
      } else {
        const _x_0 = (10 === 0 ? _n_0 : _n_0 % 10);
        $0 = _g_0;
        $1 = (10 === 0 ? 0 : (_n_0 / 10) >>> 0);
        $2 = (char_new(((48 + _x_0) >>> 0)) + _acc_0);
        $pc = 0; continue;
      }
    }
  }
}

function $String$cmp$fin$(_t1_0, _t2_0, _hc_0) {
  const _t_0 = _hc_0["fst"];
  const _h1b_0 = _t_0["fst"];
  const _h2b_0 = _t_0["snd"];
  const _t_1 = _hc_0["snd"];
  if (_t_1.$ === "LT") {
    return {$: "Tuple", "fst": {$: "Tuple", "fst": (_h1b_0 + _t1_0), "snd": (_h2b_0 + _t2_0)}, "snd": {$: "LT"}};
  } else if (_t_1.$ === "EQ") {
    return $String$cmp$rec$(_h1b_0, _h2b_0, ($String$cmp$(_t1_0, _t2_0)));
  } else {
    return {$: "Tuple", "fst": {$: "Tuple", "fst": (_h1b_0 + _t1_0), "snd": (_h2b_0 + _t2_0)}, "snd": {$: "GT"}};
  }
}

function $Char$cmp$(_a_0, _b_0) {
  const _x_0 = _a_0.codePointAt(0);
  const _x_1 = _b_0.codePointAt(0);
  return {$: "Tuple", "fst": {$: "Tuple", "fst": _a_0, "snd": _b_0}, "snd": cmp_new(_x_0, _x_1)};
}

function $U32$show$fin$($0, $1, $2, $3) {
  let $pc = 1;
  for (;;) switch ($pc) {
    case 0: {
      const _f_0 = $0;
      const _n_0 = $1;
      const _acc_0 = $2;
      if (_f_0 === 0) {
        return _acc_0;
      } else {
        const _g_0 = (_f_0 - 1);
        $0 = _g_0;
        $1 = _acc_0;
        $2 = _n_0;
        $3 = (_n_0 === 0);
        $pc = 1; continue;
      }
    }
    case 1: {
      const _g_0 = $0;
      const _acc_0 = $1;
      const _n_0 = $2;
      const _z_0 = $3;
      if (_z_0) {
        return _acc_0;
      } else {
        const _x_0 = (10 === 0 ? _n_0 : _n_0 % 10);
        $0 = _g_0;
        $1 = (10 === 0 ? 0 : (_n_0 / 10) >>> 0);
        $2 = (char_new(((48 + _x_0) >>> 0)) + _acc_0);
        $pc = 0; continue;
      }
    }
  }
}

function $String$cmp$rec$(_h1b_0, _h2b_0, _rr_0) {
  const _t_0 = _rr_0["fst"];
  const _t1b_0 = _t_0["fst"];
  const _t2b_0 = _t_0["snd"];
  const _r_0 = _rr_0["snd"];
  return {$: "Tuple", "fst": {$: "Tuple", "fst": (_h1b_0 + _t1b_0), "snd": (_h2b_0 + _t2b_0)}, "snd": _r_0};
}

function $0m1(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "UnexpectedEnd": at = at[key] = {...v, "offset": BigInt(v["offset"])}; return top[0];
      case "InvalidHex": at = at[key] = {...v, "offset": BigInt(v["offset"])}; return top[0];
      case "InvalidByte": at = at[key] = {...v, "offset": BigInt(v["offset"])}; return top[0];
      case "ExpectedSeparator": at = at[key] = {...v, "offset": BigInt(v["offset"])}; return top[0];
      case "TrailingInput": at[key] = v; return top[0];
      case "ForbiddenVersion": at[key] = v; return top[0];
      case "UnsupportedVersion": at[key] = v; return top[0];
      case "ZeroId": at[key] = v; return top[0];
      case "ControlCharacter": at = at[key] = {...v, "offset": BigInt(v["offset"])}; return top[0];
      default: throw "bend: Error has no tag " + v?.$ + " (its tags: UnexpectedEnd, InvalidHex, InvalidByte, ExpectedSeparator, TrailingInput, ForbiddenVersion, UnsupportedVersion, ZeroId, ControlCharacter); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m0(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m1(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m2(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m1(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m3(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m1(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m4(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m1(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m5(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m1(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m6(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m1(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m7(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m1(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m8(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m1(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m9(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m1(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m10(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m1(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m11(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m1(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m13(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "TraceDraw": at = at[key] = {...v, "remaining": BigInt(v["remaining"])}; return top[0];
      default: throw "bend: TraceDraw has no tag " + v?.$ + " (its tags: TraceDraw); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m12(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "NeedTraceWord": at = at[key] = {...v, "draw": $0m13(v["draw"])}; return top[0];
      case "DrawnTraceId": at[key] = v; return top[0];
      case "TraceFailed": at[key] = v; return top[0];
      default: throw "bend: TraceStep has no tag " + v?.$ + " (its tags: NeedTraceWord, DrawnTraceId, TraceFailed); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m14(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "TraceDraw": at = at[key] = {...v, "remaining": nat_host(v["remaining"])}; return top[0];
      default: throw "bend: TraceDraw has no tag " + v?.$ + " (its tags: TraceDraw); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m15(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "NeedTraceWord": at = at[key] = {...v, "draw": $0m14(v["draw"])}; return top[0];
      case "DrawnTraceId": at[key] = v; return top[0];
      case "TraceFailed": at[key] = v; return top[0];
      default: throw "bend: TraceStep has no tag " + v?.$ + " (its tags: NeedTraceWord, DrawnTraceId, TraceFailed); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m16(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "None": at[key] = v; return top[0];
      case "Some": at = at[key] = {...v, "value": $0m13(v["value"])}; return top[0];
      default: throw "bend: Maybe has no tag " + v?.$ + " (its tags: None, Some); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m17(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Tuple": at = at[key] = {...v, "snd": $0m15(v["snd"])}; return top[0];
      default: throw "bend: Sigma has no tag " + v?.$ + " (its tags: Tuple); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m18(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Tuple": at = at[key] = {...v, "snd": $0m12(v["snd"])}; return top[0];
      default: throw "bend: Sigma has no tag " + v?.$ + " (its tags: Tuple); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m20(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "SpanDraw": at = at[key] = {...v, "remaining": BigInt(v["remaining"])}; return top[0];
      default: throw "bend: SpanDraw has no tag " + v?.$ + " (its tags: SpanDraw); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m19(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "NeedSpanWord": at = at[key] = {...v, "draw": $0m20(v["draw"])}; return top[0];
      case "DrawnSpanId": at[key] = v; return top[0];
      case "SpanFailed": at[key] = v; return top[0];
      default: throw "bend: SpanStep has no tag " + v?.$ + " (its tags: NeedSpanWord, DrawnSpanId, SpanFailed); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m21(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "SpanDraw": at = at[key] = {...v, "remaining": nat_host(v["remaining"])}; return top[0];
      default: throw "bend: SpanDraw has no tag " + v?.$ + " (its tags: SpanDraw); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m22(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "NeedSpanWord": at = at[key] = {...v, "draw": $0m21(v["draw"])}; return top[0];
      case "DrawnSpanId": at[key] = v; return top[0];
      case "SpanFailed": at[key] = v; return top[0];
      default: throw "bend: SpanStep has no tag " + v?.$ + " (its tags: NeedSpanWord, DrawnSpanId, SpanFailed); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m23(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "None": at[key] = v; return top[0];
      case "Some": at = at[key] = {...v, "value": $0m20(v["value"])}; return top[0];
      default: throw "bend: Maybe has no tag " + v?.$ + " (its tags: None, Some); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m24(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Tuple": at = at[key] = {...v, "snd": $0m22(v["snd"])}; return top[0];
      default: throw "bend: Sigma has no tag " + v?.$ + " (its tags: Tuple); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m25(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Tuple": at = at[key] = {...v, "snd": $0m19(v["snd"])}; return top[0];
      default: throw "bend: Sigma has no tag " + v?.$ + " (its tags: Tuple); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m27(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "DrawTrace": at = at[key] = {...v, "draw": $0m13(v["draw"])}; return top[0];
      case "DrawSpan": at = at[key] = {...v, "draw": $0m20(v["draw"])}; return top[0];
      default: throw "bend: Draw has no tag " + v?.$ + " (its tags: DrawTrace, DrawSpan); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m26(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "NeedWord": at = at[key] = {...v, "draw": $0m27(v["draw"])}; return top[0];
      case "Created": at[key] = v; return top[0];
      case "Failed": at[key] = v; return top[0];
      default: throw "bend: Step has no tag " + v?.$ + " (its tags: NeedWord, Created, Failed); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m28(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "DrawTrace": at = at[key] = {...v, "draw": $0m14(v["draw"])}; return top[0];
      case "DrawSpan": at = at[key] = {...v, "draw": $0m21(v["draw"])}; return top[0];
      default: throw "bend: Draw has no tag " + v?.$ + " (its tags: DrawTrace, DrawSpan); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m29(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "NeedWord": at = at[key] = {...v, "draw": $0m28(v["draw"])}; return top[0];
      case "Created": at[key] = v; return top[0];
      case "Failed": at[key] = v; return top[0];
      default: throw "bend: Step has no tag " + v?.$ + " (its tags: NeedWord, Created, Failed); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m30(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "None": at[key] = v; return top[0];
      case "Some": at = at[key] = {...v, "value": $0m27(v["value"])}; return top[0];
      default: throw "bend: Maybe has no tag " + v?.$ + " (its tags: None, Some); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m31(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Tuple": at = at[key] = {...v, "snd": $0m29(v["snd"])}; return top[0];
      default: throw "bend: Sigma has no tag " + v?.$ + " (its tags: Tuple); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m32(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Tuple": at = at[key] = {...v, "snd": $0m26(v["snd"])}; return top[0];
      default: throw "bend: Sigma has no tag " + v?.$ + " (its tags: Tuple); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m33(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Generation": at = at[key] = {...v, "fuel": BigInt(v["fuel"]), "step": $0m26(v["step"])}; return top[0];
      default: throw "bend: Generation has no tag " + v?.$ + " (its tags: Generation); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m34(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Generation": at = at[key] = {...v, "fuel": nat_host(v["fuel"]), "step": $0m29(v["step"])}; return top[0];
      default: throw "bend: Generation has no tag " + v?.$ + " (its tags: Generation); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m35(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "UnexpectedEnd": at = at[key] = {...v, "offset": nat_host(v["offset"])}; return top[0];
      case "InvalidHex": at = at[key] = {...v, "offset": nat_host(v["offset"])}; return top[0];
      case "InvalidByte": at = at[key] = {...v, "offset": nat_host(v["offset"])}; return top[0];
      case "ExpectedSeparator": at = at[key] = {...v, "offset": nat_host(v["offset"])}; return top[0];
      case "TrailingInput": at[key] = v; return top[0];
      case "ForbiddenVersion": at[key] = v; return top[0];
      case "UnsupportedVersion": at[key] = v; return top[0];
      case "ZeroId": at[key] = v; return top[0];
      case "ControlCharacter": at = at[key] = {...v, "offset": nat_host(v["offset"])}; return top[0];
      default: throw "bend: Error has no tag " + v?.$ + " (its tags: UnexpectedEnd, InvalidHex, InvalidByte, ExpectedSeparator, TrailingInput, ForbiddenVersion, UnsupportedVersion, ZeroId, ControlCharacter); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m37(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Limits": at = at[key] = {...v, "traceparent_input": BigInt(v["traceparent_input"]), "tracestate_input": BigInt(v["tracestate_input"]), "tracestate_output": BigInt(v["tracestate_output"])}; return top[0];
      default: throw "bend: Limits has no tag " + v?.$ + " (its tags: Limits); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m36(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at[key] = v; return top[0];
      case "Done": at = at[key] = {...v, "value": $0m37(v["value"])}; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m38(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Limits": at = at[key] = {...v, "traceparent_input": nat_host(v["traceparent_input"]), "tracestate_input": nat_host(v["tracestate_input"]), "tracestate_output": nat_host(v["tracestate_output"])}; return top[0];
      default: throw "bend: Limits has no tag " + v?.$ + " (its tags: Limits); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m39(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "None": at[key] = v; return top[0];
      case "Some": at = at[key] = {...v, "value": BigInt(v["value"])}; return top[0];
      default: throw "bend: Maybe has no tag " + v?.$ + " (its tags: None, Some); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m40(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "None": at[key] = v; return top[0];
      case "Some": at = at[key] = {...v, "value": nat_host(v["value"])}; return top[0];
      default: throw "bend: Maybe has no tag " + v?.$ + " (its tags: None, Some); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m42(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "StateTooLarge": at[key] = v; return top[0];
      case "TooManyMembers": at[key] = v; return top[0];
      case "InvalidEntry": at = at[key] = {...v, "member": BigInt(v["member"])}; return top[0];
      default: throw "bend: StateError has no tag " + v?.$ + " (its tags: StateTooLarge, TooManyMembers, InvalidEntry); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m41(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Scanning": at = at[key] = {...v, "member": BigInt(v["member"]), "room": BigInt(v["room"])}; return top[0];
      case "Stopped": at = at[key] = {...v, "error": $0m42(v["error"])}; return top[0];
      default: throw "bend: Scan has no tag " + v?.$ + " (its tags: Scanning, Stopped); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m44(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "StateTooLarge": at[key] = v; return top[0];
      case "TooManyMembers": at[key] = v; return top[0];
      case "InvalidEntry": at = at[key] = {...v, "member": nat_host(v["member"])}; return top[0];
      default: throw "bend: StateError has no tag " + v?.$ + " (its tags: StateTooLarge, TooManyMembers, InvalidEntry); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m43(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Scanning": at = at[key] = {...v, "member": nat_host(v["member"]), "room": nat_host(v["room"])}; return top[0];
      case "Stopped": at = at[key] = {...v, "error": $0m44(v["error"])}; return top[0];
      default: throw "bend: Scan has no tag " + v?.$ + " (its tags: Scanning, Stopped); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m45(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m42(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m46(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m1(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m47(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m35(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m49(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "RepeatedTraceParent": at[key] = v; return top[0];
      case "TraceParentTooLarge": at[key] = v; return top[0];
      case "InvalidTraceParent": at = at[key] = {...v, "error": $0m1(v["error"])}; return top[0];
      default: throw "bend: TraceParentError has no tag " + v?.$ + " (its tags: RepeatedTraceParent, TraceParentTooLarge, InvalidTraceParent); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m48(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m49(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m50(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "StateAbsent": at[key] = v; return top[0];
      case "StateAccepted": at[key] = v; return top[0];
      case "StateDiscarded": at = at[key] = {...v, "error": $0m42(v["error"])}; return top[0];
      case "StateIgnored": at[key] = v; return top[0];
      default: throw "bend: StateOutcome has no tag " + v?.$ + " (its tags: StateAbsent, StateAccepted, StateDiscarded, StateIgnored); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m52(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "RepeatedTraceParent": at[key] = v; return top[0];
      case "TraceParentTooLarge": at[key] = v; return top[0];
      case "InvalidTraceParent": at = at[key] = {...v, "error": $0m35(v["error"])}; return top[0];
      default: throw "bend: TraceParentError has no tag " + v?.$ + " (its tags: RepeatedTraceParent, TraceParentTooLarge, InvalidTraceParent); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m51(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "TraceParentAccepted": at[key] = v; return top[0];
      case "TraceParentAbsent": at[key] = v; return top[0];
      case "TraceParentRejected": at = at[key] = {...v, "error": $0m52(v["error"])}; return top[0];
      default: throw "bend: TraceParentOutcome has no tag " + v?.$ + " (its tags: TraceParentAccepted, TraceParentAbsent, TraceParentRejected); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m53(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "TraceParentAccepted": at[key] = v; return top[0];
      case "TraceParentAbsent": at[key] = v; return top[0];
      case "TraceParentRejected": at = at[key] = {...v, "error": $0m49(v["error"])}; return top[0];
      default: throw "bend: TraceParentOutcome has no tag " + v?.$ + " (its tags: TraceParentAccepted, TraceParentAbsent, TraceParentRejected); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m54(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Extraction": at = at[key] = {...v, "parent": $0m53(v["parent"]), "state": $0m50(v["state"])}; return top[0];
      default: throw "bend: Extraction has no tag " + v?.$ + " (its tags: Extraction); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m55(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m44(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m56(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m52(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m58(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "StateAbsent": at[key] = v; return top[0];
      case "StateAccepted": at[key] = v; return top[0];
      case "StateDiscarded": at = at[key] = {...v, "error": $0m44(v["error"])}; return top[0];
      case "StateIgnored": at[key] = v; return top[0];
      default: throw "bend: StateOutcome has no tag " + v?.$ + " (its tags: StateAbsent, StateAccepted, StateDiscarded, StateIgnored); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m57(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Extraction": at = at[key] = {...v, "parent": $0m51(v["parent"]), "state": $0m58(v["state"])}; return top[0];
      default: throw "bend: Extraction has no tag " + v?.$ + " (its tags: Extraction); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m60(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "NothingToForward": at[key] = v; return top[0];
      case "ForwardTooLarge": at[key] = v; return top[0];
      case "InvalidForwardParent": at = at[key] = {...v, "error": $0m49(v["error"])}; return top[0];
      case "InvalidForwardState": at = at[key] = {...v, "error": $0m42(v["error"])}; return top[0];
      default: throw "bend: ForwardError has no tag " + v?.$ + " (its tags: NothingToForward, ForwardTooLarge, InvalidForwardParent, InvalidForwardState); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m59(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m60(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m61(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "NothingToForward": at[key] = v; return top[0];
      case "ForwardTooLarge": at[key] = v; return top[0];
      case "InvalidForwardParent": at = at[key] = {...v, "error": $0m52(v["error"])}; return top[0];
      case "InvalidForwardState": at = at[key] = {...v, "error": $0m44(v["error"])}; return top[0];
      default: throw "bend: ForwardError has no tag " + v?.$ + " (its tags: NothingToForward, ForwardTooLarge, InvalidForwardParent, InvalidForwardState); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m62(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "ContinuePlan": at = at[key] = {...v, "generation": $0m33(v["generation"])}; return top[0];
      case "StartPlan": at = at[key] = {...v, "generation": $0m33(v["generation"])}; return top[0];
      default: throw "bend: ServicePlan has no tag " + v?.$ + " (its tags: ContinuePlan, StartPlan); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m63(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "ContinuePlan": at = at[key] = {...v, "generation": $0m34(v["generation"])}; return top[0];
      case "StartPlan": at = at[key] = {...v, "generation": $0m34(v["generation"])}; return top[0];
      default: throw "bend: ServicePlan has no tag " + v?.$ + " (its tags: ContinuePlan, StartPlan); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m64(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at = at[key] = {...v, "error": $0m61(v["error"])}; return top[0];
      case "Done": at[key] = v; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m66(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "NothingKept": at[key] = v; return top[0];
      case "ForwardFailed": at = at[key] = {...v, "error": $0m60(v["error"])}; return top[0];
      default: throw "bend: Unforwarded has no tag " + v?.$ + " (its tags: NothingKept, ForwardFailed); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m65(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fresh": at[key] = v; return top[0];
      case "Forwarded": at[key] = v; return top[0];
      case "NoContext": at = at[key] = {...v, "reason": $0m66(v["reason"])}; return top[0];
      default: throw "bend: Sent has no tag " + v?.$ + " (its tags: Fresh, Forwarded, NoContext); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m67(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "SendChild": at = at[key] = {...v, "generation": $0m33(v["generation"]), "limits": $0m37(v["limits"])}; return top[0];
      case "SendFallback": at = at[key] = {...v, "limits": $0m37(v["limits"])}; return top[0];
      default: throw "bend: SendPlan has no tag " + v?.$ + " (its tags: SendChild, SendFallback); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m68(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "SendChild": at = at[key] = {...v, "generation": $0m34(v["generation"]), "limits": $0m38(v["limits"])}; return top[0];
      case "SendFallback": at = at[key] = {...v, "limits": $0m38(v["limits"])}; return top[0];
      default: throw "bend: SendPlan has no tag " + v?.$ + " (its tags: SendChild, SendFallback); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m69(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Tuple": at = at[key] = {...v, "snd": $0m65(v["snd"])}; return top[0];
      default: throw "bend: Sigma has no tag " + v?.$ + " (its tags: Tuple); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m71(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "NothingKept": at[key] = v; return top[0];
      case "ForwardFailed": at = at[key] = {...v, "error": $0m61(v["error"])}; return top[0];
      default: throw "bend: Unforwarded has no tag " + v?.$ + " (its tags: NothingKept, ForwardFailed); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m70(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fresh": at[key] = v; return top[0];
      case "Forwarded": at[key] = v; return top[0];
      case "NoContext": at = at[key] = {...v, "reason": $0m71(v["reason"])}; return top[0];
      default: throw "bend: Sent has no tag " + v?.$ + " (its tags: Fresh, Forwarded, NoContext); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}

function $0m72(v) {
  const top = [v];
  for (let at = top, key = 0;;) {
    switch (v.$) {
      case "Fail": at[key] = v; return top[0];
      case "Done": at = at[key] = {...v, "value": $0m65(v["value"])}; return top[0];
      default: throw "bend: Result has no tag " + v?.$ + " (its tags: Fail, Done); a tag names its constructor as the"
      + " loading file sees it, which a later version will make the same"
      + " everywhere (#1105)";
    }
  }
}
export default {
  "src/hex.Digit.to_char": run_lib((a0) => { const r = (run_loop($src$047hex$Digit$to_char$((a0)))); (a0); return r; }, 1),
  "src/hex.Digit.to_u32": run_lib((a0) => { const r = (run_loop($src$047hex$Digit$to_u32$((a0)))); (a0); return r; }, 1),
  "src/hex.Digit.is_zero": run_lib((a0) => { const r = (run_loop($src$047hex$Digit$is_zero$((a0)))); (a0); return r; }, 1),
  "src/hex.Digit.is_odd": run_lib((a0) => { const r = (run_loop($src$047hex$Digit$is_odd$((a0)))); (a0); return r; }, 1),
  "src/hex.Digit.has_bit1": run_lib((a0) => { const r = (run_loop($src$047hex$Digit$has_bit1$((a0)))); (a0); return r; }, 1),
  "src/hex.Digit.has_bit2": run_lib((a0) => { const r = (run_loop($src$047hex$Digit$has_bit2$((a0)))); (a0); return r; }, 1),
  "src/hex.Digit.has_bit3": run_lib((a0) => { const r = (run_loop($src$047hex$Digit$has_bit3$((a0)))); (a0); return r; }, 1),
  "src/hex.Digit.from_bits": run_lib((a0, a1, a2, a3) => { const r = (run_loop($src$047hex$Digit$from_bits$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "src/hex.Digit.all": run_lib(() => { const r = (run_loop($src$047hex$Digit$all$()));  return r; }, 0),
  "src/hex.Digit.from_char.find": run_lib((a0, a1) => { const r = (run_loop($src$047hex$Digit$from_char$find$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "src/hex.Digit.from_char": run_lib((a0) => { const r = (run_loop($src$047hex$Digit$from_char$((a0)))); (a0); return r; }, 1),
  "src/digits.Digits": run_lib((a0) => { const r = (run_loop($src$047digits$Digits$(nat_host(a0)))); BigInt(a0); return r; }, 1),
  "src/digits.Digits.to_string": run_lib((a0, a1) => { const r = (run_loop($src$047digits$Digits$to_string$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "src/digits.Digits.is_zero": run_lib((a0, a1) => { const r = (run_loop($src$047digits$Digits$is_zero$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "src/digits.Digits.of_u32": run_lib((a0) => { const r = (run_loop($src$047digits$Digits$of_u32$((a0)))); (a0); return r; }, 1),
  "src/digits.Digits.to_u32": run_lib((a0) => { const r = (run_loop($src$047digits$Digits$to_u32$((a0)))); (a0); return r; }, 1),
  "src/digits.Digits.to_byte": run_lib((a0) => { const r = (run_loop($src$047digits$Digits$to_byte$((a0)))); (a0); return r; }, 1),
  "src/digits.Digits.of_byte": run_lib((a0) => { const r = (run_loop($src$047digits$Digits$of_byte$((a0)))); (a0); return r; }, 1),
  "src/digits.Digits.to_bytes": run_lib((a0, a1) => { const r = (run_loop($src$047digits$Digits$to_bytes$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "src/digits.Digits.append": run_lib((a0, a1, a2) => { const r = (run_loop($src$047digits$Digits$append$(nat_host(a0), (a1), (a2)))); BigInt(a0); (a1); (a2); return r; }, 3),
  "src/digits.NonZero.new.checked": run_lib((a0, a1, a2) => { const r = (run_loop($src$047digits$NonZero$new$checked$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "src/digits.NonZero.new": run_lib((a0, a1) => { const r = (run_loop($src$047digits$NonZero$new$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "src/digits.NonZero.digits": run_lib((a0) => { const r = (run_loop($src$047digits$NonZero$digits$((a0)))); (a0); return r; }, 1),
  "src/digits.NonZero.to_string": run_lib((a0, a1) => { const r = (run_loop($src$047digits$NonZero$to_string$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "Parsed.prepend": run_lib((a0, a1) => { const r = (run_loop($Parsed$prepend$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Parse.digit_result": run_lib((a0, a1) => { const r = $0m0(run_loop($Parse$digit_result$((a0), nat_host(a1)))); (a0); BigInt(a1); return r; }, 2),
  "Parse.digit": run_lib((a0, a1) => { const r = $0m0(run_loop($Parse$digit$((a0), nat_host(a1)))); (a0); BigInt(a1); return r; }, 2),
  "Parse.digits": run_lib((a0, a1, a2) => { const r = $0m2(run_loop($Parse$digits$(nat_host(a0), (a1), nat_host(a2)))); BigInt(a0); (a1); BigInt(a2); return r; }, 3),
  "Parse.separator_result": run_lib((a0, a1, a2) => { const r = $0m3(run_loop($Parse$separator_result$((a0), (a1), nat_host(a2)))); (a0); (a1); BigInt(a2); return r; }, 3),
  "Parse.separator": run_lib((a0, a1) => { const r = $0m3(run_loop($Parse$separator$((a0), nat_host(a1)))); (a0); BigInt(a1); return r; }, 2),
  "Parse.end": run_lib((a0) => { const r = $0m4(run_loop($Parse$end$((a0)))); (a0); return r; }, 1),
  "Parse.version": run_lib((a0) => { const r = $0m4(run_loop($Parse$version$((a0)))); (a0); return r; }, 1),
  "Parse.nonzero_result": run_lib((a0, a1) => { const r = $0m5(run_loop($Parse$nonzero_result$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Parse.nonzero": run_lib((a0, a1, a2) => { const r = $0m5(run_loop($Parse$nonzero$(nat_host(a0), (a1), (a2)))); BigInt(a0); (a1); (a2); return r; }, 3),
  "Parse.flags": run_lib((a0, a1, a2) => { const r = $0m6(run_loop($Parse$flags$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Parse.parent": run_lib((a0, a1) => { const r = $0m6(run_loop($Parse$parent$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Parse.trace": run_lib((a0) => { const r = $0m6(run_loop($Parse$trace$((a0)))); (a0); return r; }, 1),
  "Parse.start": run_lib((a0) => { const r = $0m6(run_loop($Parse$start$((a0)))); (a0); return r; }, 1),
  "TraceParentV00.parse": run_lib((a0) => { const r = $0m6(run_loop($TraceParentV00$parse$((a0)))); (a0); return r; }, 1),
  "TraceParentV00.format": run_lib((a0) => { const r = (run_loop($TraceParentV00$format$((a0)))); (a0); return r; }, 1),
  "TraceParentV00.is_sampled": run_lib((a0) => { const r = (run_loop($TraceParentV00$is_sampled$((a0)))); (a0); return r; }, 1),
  "TraceParentV00.is_random": run_lib((a0) => { const r = (run_loop($TraceParentV00$is_random$((a0)))); (a0); return r; }, 1),
  "Parse.id.finish": run_lib((a0, a1, a2) => { const r = $0m5(run_loop($Parse$id$finish$(nat_host(a0), (a1), (a2)))); BigInt(a0); (a1); (a2); return r; }, 3),
  "Parse.id": run_lib((a0, a1, a2) => { const r = $0m5(run_loop($Parse$id$(nat_host(a0), (a1), (a2)))); BigInt(a0); (a1); (a2); return r; }, 3),
  "TraceId.parse": run_lib((a0) => { const r = $0m7(run_loop($TraceId$parse$((a0)))); (a0); return r; }, 1),
  "TraceId.assert_random": run_lib((a0) => { const r = (run_loop($TraceId$assert_random$((a0)))); (a0); return r; }, 1),
  "TraceId.is_random": run_lib((a0) => { const r = (run_loop($TraceId$is_random$((a0)))); (a0); return r; }, 1),
  "TraceId.to_string": run_lib((a0) => { const r = (run_loop($TraceId$to_string$((a0)))); (a0); return r; }, 1),
  "TraceId.is_eq": run_lib((a0, a1) => { const r = (run_loop($TraceId$is_eq$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "SpanId.parse": run_lib((a0) => { const r = $0m8(run_loop($SpanId$parse$((a0)))); (a0); return r; }, 1),
  "SpanId.to_string": run_lib((a0) => { const r = (run_loop($SpanId$to_string$((a0)))); (a0); return r; }, 1),
  "SpanId.is_eq": run_lib((a0, a1) => { const r = (run_loop($SpanId$is_eq$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Sampling.resolve": run_lib((a0, a1) => { const r = (run_loop($Sampling$resolve$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "RemoteContext.from_traceparent": run_lib((a0) => { const r = (run_loop($RemoteContext$from_traceparent$((a0)))); (a0); return r; }, 1),
  "RemoteContext.from_ids": run_lib((a0, a1, a2) => { const r = (run_loop($RemoteContext$from_ids$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "RemoteContext.trace_id": run_lib((a0) => { const r = (run_loop($RemoteContext$trace_id$((a0)))); (a0); return r; }, 1),
  "RemoteContext.span_id": run_lib((a0) => { const r = (run_loop($RemoteContext$span_id$((a0)))); (a0); return r; }, 1),
  "RemoteContext.is_sampled": run_lib((a0) => { const r = (run_loop($RemoteContext$is_sampled$((a0)))); (a0); return r; }, 1),
  "Flags.known": run_lib((a0, a1) => { const r = (run_loop($Flags$known$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "RemoteContext.flags": run_lib((a0) => { const r = (run_loop($RemoteContext$flags$((a0)))); (a0); return r; }, 1),
  "LocalContext.trace_id": run_lib((a0) => { const r = (run_loop($LocalContext$trace_id$((a0)))); (a0); return r; }, 1),
  "LocalContext.span_id": run_lib((a0) => { const r = (run_loop($LocalContext$span_id$((a0)))); (a0); return r; }, 1),
  "LocalContext.is_sampled": run_lib((a0) => { const r = (run_loop($LocalContext$is_sampled$((a0)))); (a0); return r; }, 1),
  "LocalContext.to_traceparent": run_lib((a0) => { const r = (run_loop($LocalContext$to_traceparent$((a0)))); (a0); return r; }, 1),
  "LocalContext.flags": run_lib((a0) => { const r = (run_loop($LocalContext$flags$((a0)))); (a0); return r; }, 1),
  "Parent.trace_id": run_lib((a0) => { const r = (run_loop($Parent$trace_id$((a0)))); (a0); return r; }, 1),
  "Parent.span_id": run_lib((a0) => { const r = (run_loop($Parent$span_id$((a0)))); (a0); return r; }, 1),
  "Parent.is_sampled": run_lib((a0) => { const r = (run_loop($Parent$is_sampled$((a0)))); (a0); return r; }, 1),
  "Context.from_ids": run_lib((a0, a1, a2) => { const r = (run_loop($Context$from_ids$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Context.root_from_ids": run_lib((a0, a1, a2) => { const r = (run_loop($Context$root_from_ids$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Context.child_from_id.checked": run_lib((a0, a1, a2, a3) => { const r = (run_loop($Context$child_from_id$checked$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "Context.child_from_id": run_lib((a0, a1, a2) => { const r = (run_loop($Context$child_from_id$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Context.restart_from_ids.checked": run_lib((a0, a1, a2, a3) => { const r = (run_loop($Context$restart_from_ids$checked$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "Context.restart_from_ids": run_lib((a0, a1, a2, a3) => { const r = (run_loop($Context$restart_from_ids$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "U32.to_hex": run_lib((a0) => { const r = (run_loop($U32$to_hex$((a0)))); (a0); return r; }, 1),
  "TraceId.from_digits": run_lib((a0) => { const r = (run_loop($TraceId$from_digits$((a0)))); (a0); return r; }, 1),
  "TraceId.from_words": run_lib((a0, a1, a2, a3) => { const r = (run_loop($TraceId$from_words$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "SpanId.from_digits": run_lib((a0) => { const r = (run_loop($SpanId$from_digits$((a0)))); (a0); return r; }, 1),
  "SpanId.from_words": run_lib((a0, a1) => { const r = (run_loop($SpanId$from_words$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "ParsedBytes.prepend": run_lib((a0, a1) => { const r = (run_loop($ParsedBytes$prepend$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Parse.byte.checked": run_lib((a0, a1, a2) => { const r = $0m9(run_loop($Parse$byte$checked$((a0), (a1), nat_host(a2)))); (a0); (a1); BigInt(a2); return r; }, 3),
  "Parse.byte": run_lib((a0, a1) => { const r = $0m9(run_loop($Parse$byte$((a0), nat_host(a1)))); (a0); BigInt(a1); return r; }, 2),
  "Parse.bytes": run_lib((a0, a1, a2) => { const r = $0m10(run_loop($Parse$bytes$(nat_host(a0), (a1), nat_host(a2)))); BigInt(a0); (a1); BigInt(a2); return r; }, 3),
  "Parse.bytes_end": run_lib((a0) => { const r = $0m4(run_loop($Parse$bytes_end$((a0)))); (a0); return r; }, 1),
  "Parse.id_bytes.finish": run_lib((a0, a1, a2) => { const r = $0m11(run_loop($Parse$id_bytes$finish$(nat_host(a0), (a1), (a2)))); BigInt(a0); (a1); (a2); return r; }, 3),
  "Parse.id_bytes": run_lib((a0, a1, a2) => { const r = $0m11(run_loop($Parse$id_bytes$(nat_host(a0), (a1), (a2)))); BigInt(a0); (a1); (a2); return r; }, 3),
  "TraceId.to_bytes": run_lib((a0) => { const r = (run_loop($TraceId$to_bytes$((a0)))); (a0); return r; }, 1),
  "TraceId.from_bytes": run_lib((a0) => { const r = $0m7(run_loop($TraceId$from_bytes$((a0)))); (a0); return r; }, 1),
  "SpanId.to_bytes": run_lib((a0) => { const r = (run_loop($SpanId$to_bytes$((a0)))); (a0); return r; }, 1),
  "SpanId.from_bytes": run_lib((a0) => { const r = $0m8(run_loop($SpanId$from_bytes$((a0)))); (a0); return r; }, 1),
  "Draw.asserted": run_lib((a0) => { const r = (run_loop($Draw$asserted$((a0)))); (a0); return r; }, 1),
  "Tape.next": run_lib((a0) => { const r = (run_loop($Tape$next$((a0)))); (a0); return r; }, 1),
  "TraceDraw.start": run_lib((a0) => { const r = $0m12(run_loop($TraceDraw$start$((a0)))); (a0); return r; }, 1),
  "TraceDraw.retry": run_lib((a0, a1) => { const r = $0m12(run_loop($TraceDraw$retry$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "TraceDraw.reuse": run_lib((a0, a1, a2, a3) => { const r = $0m12(run_loop($TraceDraw$reuse$((a0), (a1), (a2), nat_host(a3)))); (a0); (a1); (a2); BigInt(a3); return r; }, 4),
  "TraceDraw.check": run_lib((a0, a1, a2) => { const r = $0m12(run_loop($TraceDraw$check$((a0), (a1), nat_host(a2)))); (a0); (a1); BigInt(a2); return r; }, 3),
  "TraceDraw.take": run_lib((a0, a1, a2, a3) => { const r = $0m12(run_loop($TraceDraw$take$((a0), nat_host(a1), (a2), (a3)))); (a0); BigInt(a1); (a2); (a3); return r; }, 4),
  "TraceDraw.feed": run_lib((a0, a1, a2, a3) => { const r = $0m12(run_loop($TraceDraw$feed$((a0), nat_host(a1), (a2), (a3)))); (a0); BigInt(a1); (a2); (a3); return r; }, 4),
  "TraceDraw.next": run_lib((a0, a1) => { const r = $0m12(run_loop($TraceDraw$next$((a0), $0m14(a1)))); (a0); $0m13(a1); return r; }, 2),
  "TraceStep.waiting": run_lib((a0) => { const r = $0m16(run_loop($TraceStep$waiting$($0m15(a0)))); $0m12(a0); return r; }, 1),
  "TraceDraw.result": run_lib((a0) => { const r = (run_loop($TraceDraw$result$($0m15(a0)))); $0m12(a0); return r; }, 1),
  "TraceDraw.run": run_lib((a0, a1) => { const r = (run_loop($TraceDraw$run$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "TraceDraw.ended": run_lib((a0) => { const r = (run_loop($TraceDraw$ended$((a0)))); (a0); return r; }, 1),
  "TraceDraw.outcome": run_lib((a0) => { const r = (run_loop($TraceDraw$outcome$($0m17(a0)))); $0m18(a0); return r; }, 1),
  "SpanDraw.start": run_lib((a0) => { const r = $0m19(run_loop($SpanDraw$start$((a0)))); (a0); return r; }, 1),
  "SpanDraw.retry": run_lib((a0, a1) => { const r = $0m19(run_loop($SpanDraw$retry$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "SpanDraw.reuse": run_lib((a0, a1, a2, a3) => { const r = $0m19(run_loop($SpanDraw$reuse$((a0), (a1), (a2), nat_host(a3)))); (a0); (a1); (a2); BigInt(a3); return r; }, 4),
  "SpanDraw.check": run_lib((a0, a1, a2) => { const r = $0m19(run_loop($SpanDraw$check$((a0), (a1), nat_host(a2)))); (a0); (a1); BigInt(a2); return r; }, 3),
  "SpanDraw.take": run_lib((a0, a1, a2, a3) => { const r = $0m19(run_loop($SpanDraw$take$((a0), nat_host(a1), (a2), (a3)))); (a0); BigInt(a1); (a2); (a3); return r; }, 4),
  "SpanDraw.feed": run_lib((a0, a1, a2, a3) => { const r = $0m19(run_loop($SpanDraw$feed$((a0), nat_host(a1), (a2), (a3)))); (a0); BigInt(a1); (a2); (a3); return r; }, 4),
  "SpanDraw.next": run_lib((a0, a1) => { const r = $0m19(run_loop($SpanDraw$next$((a0), $0m21(a1)))); (a0); $0m20(a1); return r; }, 2),
  "SpanStep.waiting": run_lib((a0) => { const r = $0m23(run_loop($SpanStep$waiting$($0m22(a0)))); $0m19(a0); return r; }, 1),
  "SpanDraw.result": run_lib((a0) => { const r = (run_loop($SpanDraw$result$($0m22(a0)))); $0m19(a0); return r; }, 1),
  "SpanDraw.run": run_lib((a0, a1) => { const r = (run_loop($SpanDraw$run$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "SpanDraw.ended": run_lib((a0) => { const r = (run_loop($SpanDraw$ended$((a0)))); (a0); return r; }, 1),
  "SpanDraw.outcome": run_lib((a0) => { const r = (run_loop($SpanDraw$outcome$($0m24(a0)))); $0m25(a0); return r; }, 1),
  "Step.of_span": run_lib((a0, a1, a2) => { const r = $0m26(run_loop($Step$of_span$($0m22(a0), (a1), (a2)))); $0m19(a0); (a1); (a2); return r; }, 3),
  "SpanPlan.root": run_lib((a0, a1) => { const r = (run_loop($SpanPlan$root$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "SpanPlan.child": run_lib((a0, a1) => { const r = (run_loop($SpanPlan$child$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "SpanPlan.draw": run_lib((a0) => { const r = $0m26(run_loop($SpanPlan$draw$((a0)))); (a0); return r; }, 1),
  "Step.of_trace": run_lib((a0, a1) => { const r = $0m26(run_loop($Step$of_trace$($0m15(a0), (a1)))); $0m12(a0); (a1); return r; }, 2),
  "Draw.restart_excluded": run_lib((a0) => { const r = (run_loop($Draw$restart_excluded$((a0)))); (a0); return r; }, 1),
  "Draw.root": run_lib((a0) => { const r = $0m26(run_loop($Draw$root$((a0)))); (a0); return r; }, 1),
  "Draw.restart": run_lib((a0, a1) => { const r = $0m26(run_loop($Draw$restart$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Draw.child": run_lib((a0, a1) => { const r = $0m26(run_loop($Draw$child$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Draw.feed": run_lib((a0, a1) => { const r = $0m26(run_loop($Draw$feed$((a0), $0m28(a1)))); (a0); $0m27(a1); return r; }, 2),
  "Step.waiting": run_lib((a0) => { const r = $0m30(run_loop($Step$waiting$($0m29(a0)))); $0m26(a0); return r; }, 1),
  "Step.result": run_lib((a0) => { const r = (run_loop($Step$result$($0m29(a0)))); $0m26(a0); return r; }, 1),
  "Draw.run": run_lib((a0, a1) => { const r = (run_loop($Draw$run$(nat_host(a0), (a1)))); BigInt(a0); (a1); return r; }, 2),
  "Draw.ended": run_lib((a0) => { const r = (run_loop($Draw$ended$((a0)))); (a0); return r; }, 1),
  "Draw.outcome": run_lib((a0) => { const r = (run_loop($Draw$outcome$($0m31(a0)))); $0m32(a0); return r; }, 1),
  "Generation.root": run_lib((a0) => { const r = $0m33(run_loop($Generation$root$((a0)))); (a0); return r; }, 1),
  "Generation.restart": run_lib((a0, a1) => { const r = $0m33(run_loop($Generation$restart$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Generation.child": run_lib((a0, a1) => { const r = $0m33(run_loop($Generation$child$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Generation.needs.of": run_lib((a0, a1) => { const r = (run_loop($Generation$needs$of$(nat_host(a0), $0m29(a1)))); BigInt(a0); $0m26(a1); return r; }, 2),
  "Generation.needs": run_lib((a0) => { const r = (run_loop($Generation$needs$($0m34(a0)))); $0m33(a0); return r; }, 1),
  "Generation.fed": run_lib((a0, a1, a2) => { const r = $0m33(run_loop($Generation$fed$(nat_host(a0), $0m29(a1), (a2)))); BigInt(a0); $0m26(a1); (a2); return r; }, 3),
  "Generation.feed": run_lib((a0, a1) => { const r = $0m33(run_loop($Generation$feed$($0m34(a0), (a1)))); $0m33(a0); (a1); return r; }, 2),
  "Generation.result": run_lib((a0) => { const r = (run_loop($Generation$result$($0m34(a0)))); $0m33(a0); return r; }, 1),
  "Draw.span_context": run_lib((a0, a1, a2) => { const r = (run_loop($Draw$span_context$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Source.tape": run_lib((a0) => { const r = (run_loop($Source$tape$((a0)))); (a0); return r; }, 1),
  "Error.show": run_lib((a0) => { const r = (run_loop($Error$show$($0m35(a0)))); $0m1(a0); return r; }, 1),
  "ContextError.show": run_lib((a0) => { const r = (run_loop($ContextError$show$((a0)))); (a0); return r; }, 1),
  "GenerationError.show": run_lib((a0) => { const r = (run_loop($GenerationError$show$((a0)))); (a0); return r; }, 1),
  "Limits.is_valid": run_lib((a0, a1, a2) => { const r = (run_loop($Limits$is_valid$(nat_host(a0), nat_host(a1), nat_host(a2)))); BigInt(a0); BigInt(a1); BigInt(a2); return r; }, 3),
  "Limits.error": run_lib((a0, a1) => { const r = (run_loop($Limits$error$(nat_host(a0), nat_host(a1)))); BigInt(a0); BigInt(a1); return r; }, 2),
  "Limits.new.checked": run_lib((a0, a1, a2, a3, a4) => { const r = $0m36(run_loop($Limits$new$checked$(nat_host(a0), nat_host(a1), nat_host(a2), (a3), (a4)))); BigInt(a0); BigInt(a1); BigInt(a2); (a3); (a4); return r; }, 5),
  "Limits.new": run_lib((a0, a1, a2) => { const r = $0m36(run_loop($Limits$new$(nat_host(a0), nat_host(a1), nat_host(a2)))); BigInt(a0); BigInt(a1); BigInt(a2); return r; }, 3),
  "Limits.default": run_lib(() => { const r = $0m37(run_loop($Limits$default$()));  return r; }, 0),
  "Limits.traceparent_input": run_lib((a0) => { const r = BigInt(run_loop($Limits$traceparent_input$($0m38(a0)))); $0m37(a0); return r; }, 1),
  "Limits.tracestate_input": run_lib((a0) => { const r = BigInt(run_loop($Limits$tracestate_input$($0m38(a0)))); $0m37(a0); return r; }, 1),
  "Limits.tracestate_output": run_lib((a0) => { const r = BigInt(run_loop($Limits$tracestate_output$($0m38(a0)))); $0m37(a0); return r; }, 1),
  "LimitsError.show": run_lib((a0) => { const r = (run_loop($LimitsError$show$((a0)))); (a0); return r; }, 1),
  "StateChar.in_range": run_lib((a0, a1, a2) => { const r = (run_loop($StateChar$in_range$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "StateChar.is_key_start": run_lib((a0) => { const r = (run_loop($StateChar$is_key_start$((a0)))); (a0); return r; }, 1),
  "StateChar.is_key": run_lib((a0) => { const r = (run_loop($StateChar$is_key$((a0)))); (a0); return r; }, 1),
  "StateChar.is_value_end": run_lib((a0) => { const r = (run_loop($StateChar$is_value_end$((a0)))); (a0); return r; }, 1),
  "StateChar.is_value": run_lib((a0) => { const r = (run_loop($StateChar$is_value$((a0)))); (a0); return r; }, 1),
  "StateChar.is_ows": run_lib((a0) => { const r = (run_loop($StateChar$is_ows$((a0)))); (a0); return r; }, 1),
  "StateKey.valid.rest": run_lib((a0, a1) => { const r = (run_loop($StateKey$valid$rest$((a0), nat_host(a1)))); (a0); BigInt(a1); return r; }, 2),
  "StateKey.is_valid": run_lib((a0) => { const r = (run_loop($StateKey$is_valid$((a0)))); (a0); return r; }, 1),
  "StateValue.valid.go": run_lib((a0, a1, a2) => { const r = (run_loop($StateValue$valid$go$((a0), (a1), nat_host(a2)))); (a0); (a1); BigInt(a2); return r; }, 3),
  "StateValue.is_valid": run_lib((a0) => { const r = (run_loop($StateValue$is_valid$((a0)))); (a0); return r; }, 1),
  "StateKey.parse.checked": run_lib((a0, a1, a2) => { const r = (run_loop($StateKey$parse$checked$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "StateKey.parse": run_lib((a0) => { const r = (run_loop($StateKey$parse$((a0)))); (a0); return r; }, 1),
  "StateKey.to_string": run_lib((a0) => { const r = (run_loop($StateKey$to_string$((a0)))); (a0); return r; }, 1),
  "StateValue.parse.checked": run_lib((a0, a1, a2) => { const r = (run_loop($StateValue$parse$checked$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "StateValue.parse": run_lib((a0) => { const r = (run_loop($StateValue$parse$((a0)))); (a0); return r; }, 1),
  "StateValue.to_string": run_lib((a0) => { const r = (run_loop($StateValue$to_string$((a0)))); (a0); return r; }, 1),
  "EntryError.show": run_lib((a0) => { const r = (run_loop($EntryError$show$((a0)))); (a0); return r; }, 1),
  "StateEntry.key": run_lib((a0) => { const r = (run_loop($StateEntry$key$((a0)))); (a0); return r; }, 1),
  "StateEntry.value": run_lib((a0) => { const r = (run_loop($StateEntry$value$((a0)))); (a0); return r; }, 1),
  "StateEntry.key_text": run_lib((a0) => { const r = (run_loop($StateEntry$key_text$((a0)))); (a0); return r; }, 1),
  "StateEntry.format": run_lib((a0) => { const r = (run_loop($StateEntry$format$((a0)))); (a0); return r; }, 1),
  "Entries.has_key": run_lib((a0, a1) => { const r = (run_loop($Entries$has_key$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Entries.unique": run_lib((a0, a1) => { const r = (run_loop($Entries$unique$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "TraceState.is_valid": run_lib((a0) => { const r = (run_loop($TraceState$is_valid$((a0)))); (a0); return r; }, 1),
  "TraceState.empty": run_lib(() => { const r = (run_loop($TraceState$empty$()));  return r; }, 0),
  "TraceState.entries": run_lib((a0) => { const r = (run_loop($TraceState$entries$((a0)))); (a0); return r; }, 1),
  "TraceState.is_empty": run_lib((a0) => { const r = (run_loop($TraceState$is_empty$((a0)))); (a0); return r; }, 1),
  "Entries.get.put": run_lib((a0, a1, a2) => { const r = (run_loop($Entries$get$put$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Entries.get": run_lib((a0, a1) => { const r = (run_loop($Entries$get$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "TraceState.get": run_lib((a0, a1) => { const r = (run_loop($TraceState$get$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Entries.format.rest": run_lib((a0) => { const r = (run_loop($Entries$format$rest$((a0)))); (a0); return r; }, 1),
  "Entries.format": run_lib((a0) => { const r = (run_loop($Entries$format$((a0)))); (a0); return r; }, 1),
  "TraceState.format": run_lib((a0) => { const r = (run_loop($TraceState$format$((a0)))); (a0); return r; }, 1),
  "Utf8.width": run_lib((a0) => { const r = BigInt(run_loop($Utf8$width$((a0)))); (a0); return r; }, 1),
  "Utf8.length": run_lib((a0) => { const r = BigInt(run_loop($Utf8$length$((a0)))); (a0); return r; }, 1),
  "Budget.take": run_lib((a0, a1) => { const r = $0m39(run_loop($Budget$take$(nat_host(a0), nat_host(a1)))); BigInt(a0); BigInt(a1); return r; }, 2),
  "Utf8.left": run_lib((a0, a1) => { const r = $0m39(run_loop($Utf8$left$((a0), $0m40(a1)))); (a0); $0m39(a1); return r; }, 2),
  "Utf8.left_more": run_lib((a0, a1) => { const r = $0m39(run_loop($Utf8$left_more$((a0), $0m40(a1)))); (a0); $0m39(a1); return r; }, 2),
  "Utf8.left_fields": run_lib((a0, a1) => { const r = $0m39(run_loop($Utf8$left_fields$((a0), $0m40(a1)))); (a0); $0m39(a1); return r; }, 2),
  "Value.restore.step": run_lib((a0, a1, a2, a3) => { const r = (run_loop($Value$restore$step$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "Value.restore.go": run_lib((a0, a1) => { const r = (run_loop($Value$restore$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Value.restore": run_lib((a0) => { const r = (run_loop($Value$restore$((a0)))); (a0); return r; }, 1),
  "Member.start": run_lib((a0, a1, a2) => { const r = (run_loop($Member$start$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Member.key": run_lib((a0, a1, a2) => { const r = (run_loop($Member$key$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Member.push": run_lib((a0, a1) => { const r = (run_loop($Member$push$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Scan.validate": run_lib((a0, a1) => { const r = (run_loop($Scan$validate$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Entries.add.if": run_lib((a0, a1, a2) => { const r = (run_loop($Entries$add$if$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Entries.add": run_lib((a0, a1) => { const r = (run_loop($Entries$add$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Scan.keep": run_lib((a0, a1, a2, a3) => { const r = $0m41(run_loop($Scan$keep$(nat_host(a0), nat_host(a1), (a2), (a3)))); BigInt(a0); BigInt(a1); (a2); (a3); return r; }, 4),
  "Scan.entry": run_lib((a0, a1, a2, a3) => { const r = $0m41(run_loop($Scan$entry$((a0), nat_host(a1), nat_host(a2), (a3)))); (a0); BigInt(a1); BigInt(a2); (a3); return r; }, 4),
  "Scan.close": run_lib((a0, a1, a2, a3) => { const r = $0m41(run_loop($Scan$close$(nat_host(a0), nat_host(a1), (a2), (a3)))); BigInt(a0); BigInt(a1); (a2); (a3); return r; }, 4),
  "Scan.read": run_lib((a0, a1, a2, a3, a4, a5) => { const r = $0m41(run_loop($Scan$read$((a0), (a1), nat_host(a2), nat_host(a3), (a4), (a5)))); (a0); (a1); BigInt(a2); BigInt(a3); (a4); (a5); return r; }, 6),
  "Scan.char": run_lib((a0, a1) => { const r = $0m41(run_loop($Scan$char$((a0), $0m43(a1)))); (a0); $0m41(a1); return r; }, 2),
  "Scan.text": run_lib((a0, a1) => { const r = $0m41(run_loop($Scan$text$((a0), $0m43(a1)))); (a0); $0m41(a1); return r; }, 2),
  "Scan.more": run_lib((a0, a1) => { const r = $0m41(run_loop($Scan$more$((a0), $0m43(a1)))); (a0); $0m41(a1); return r; }, 2),
  "Scan.fields": run_lib((a0, a1) => { const r = $0m41(run_loop($Scan$fields$((a0), $0m43(a1)))); (a0); $0m41(a1); return r; }, 2),
  "Scan.start": run_lib(() => { const r = $0m41(run_loop($Scan$start$()));  return r; }, 0),
  "Scan.state": run_lib((a0, a1, a2) => { const r = $0m45(run_loop($Scan$state$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Scan.result": run_lib((a0) => { const r = $0m45(run_loop($Scan$result$($0m43(a0)))); $0m41(a0); return r; }, 1),
  "Scan.finish": run_lib((a0) => { const r = $0m45(run_loop($Scan$finish$($0m43(a0)))); $0m41(a0); return r; }, 1),
  "Scan.within": run_lib((a0, a1) => { const r = $0m45(run_loop($Scan$within$($0m40(a0), (a1)))); $0m39(a0); (a1); return r; }, 2),
  "TraceState.parse_fields": run_lib((a0, a1) => { const r = $0m45(run_loop($TraceState$parse_fields$($0m38(a0), (a1)))); $0m37(a0); (a1); return r; }, 2),
  "TraceState.parse": run_lib((a0, a1) => { const r = $0m45(run_loop($TraceState$parse$($0m38(a0), (a1)))); $0m37(a0); (a1); return r; }, 2),
  "StateError.show": run_lib((a0) => { const r = (run_loop($StateError$show$($0m44(a0)))); $0m42(a0); return r; }, 1),
  "Entries.unless": run_lib((a0, a1, a2) => { const r = (run_loop($Entries$unless$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Entries.without": run_lib((a0, a1) => { const r = (run_loop($Entries$without$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "TraceState.from_entries.checked": run_lib((a0, a1, a2, a3) => { const r = (run_loop($TraceState$from_entries$checked$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "TraceState.from_entries": run_lib((a0, a1) => { const r = (run_loop($TraceState$from_entries$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "TraceState.set": run_lib((a0, a1, a2) => { const r = (run_loop($TraceState$set$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "TraceState.remove": run_lib((a0, a1) => { const r = (run_loop($TraceState$remove$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "StateEntry.size": run_lib((a0) => { const r = BigInt(run_loop($StateEntry$size$((a0)))); (a0); return r; }, 1),
  "Entries.size.rest": run_lib((a0) => { const r = BigInt(run_loop($Entries$size$rest$((a0)))); (a0); return r; }, 1),
  "Entries.size": run_lib((a0) => { const r = BigInt(run_loop($Entries$size$((a0)))); (a0); return r; }, 1),
  "TraceState.size": run_lib((a0) => { const r = BigInt(run_loop($TraceState$size$((a0)))); (a0); return r; }, 1),
  "Truncation.kept": run_lib((a0) => { const r = (run_loop($Truncation$kept$((a0)))); (a0); return r; }, 1),
  "Truncation.dropped": run_lib((a0) => { const r = (run_loop($Truncation$dropped$((a0)))); (a0); return r; }, 1),
  "StateEntry.is_large": run_lib((a0) => { const r = (run_loop($StateEntry$is_large$((a0)))); (a0); return r; }, 1),
  "Entries.has_large": run_lib((a0) => { const r = (run_loop($Entries$has_large$((a0)))); (a0); return r; }, 1),
  "Entries.drop_last_large": run_lib((a0) => { const r = (run_loop($Entries$drop_last_large$((a0)))); (a0); return r; }, 1),
  "Entries.drop_last": run_lib((a0) => { const r = (run_loop($Entries$drop_last$((a0)))); (a0); return r; }, 1),
  "Entries.shrink": run_lib((a0) => { const r = (run_loop($Entries$shrink$((a0)))); (a0); return r; }, 1),
  "Entries.truncate": run_lib((a0, a1, a2) => { const r = (run_loop($Entries$truncate$(nat_host(a0), nat_host(a1), (a2)))); BigInt(a0); BigInt(a1); (a2); return r; }, 3),
  "Entries.dropped": run_lib((a0, a1) => { const r = (run_loop($Entries$dropped$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "TraceState.truncate": run_lib((a0, a1) => { const r = (run_loop($TraceState$truncate$($0m38(a0), (a1)))); $0m37(a0); (a1); return r; }, 2),
  "OutgoingContext.new": run_lib((a0) => { const r = (run_loop($OutgoingContext$new$((a0)))); (a0); return r; }, 1),
  "OutgoingContext.with_state": run_lib((a0, a1) => { const r = (run_loop($OutgoingContext$with_state$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "OutgoingContext.context": run_lib((a0) => { const r = (run_loop($OutgoingContext$context$((a0)))); (a0); return r; }, 1),
  "OutgoingContext.state": run_lib((a0) => { const r = (run_loop($OutgoingContext$state$((a0)))); (a0); return r; }, 1),
  "OutgoingContext.get": run_lib((a0, a1) => { const r = (run_loop($OutgoingContext$get$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "OutgoingContext.set": run_lib((a0, a1, a2) => { const r = (run_loop($OutgoingContext$set$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "OutgoingContext.remove": run_lib((a0, a1) => { const r = (run_loop($OutgoingContext$remove$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Emission.of": run_lib((a0, a1) => { const r = (run_loop($Emission$of$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "OutgoingContext.emit": run_lib((a0, a1) => { const r = (run_loop($OutgoingContext$emit$($0m38(a0), (a1)))); $0m37(a0); (a1); return r; }, 2),
  "Emission.traceparent": run_lib((a0) => { const r = (run_loop($Emission$traceparent$((a0)))); (a0); return r; }, 1),
  "Emission.tracestate": run_lib((a0) => { const r = (run_loop($Emission$tracestate$((a0)))); (a0); return r; }, 1),
  "Emission.dropped": run_lib((a0) => { const r = (run_loop($Emission$dropped$((a0)))); (a0); return r; }, 1),
  "Header.name": run_lib((a0) => { const r = (run_loop($Header$name$((a0)))); (a0); return r; }, 1),
  "Header.value": run_lib((a0) => { const r = (run_loop($Header$value$((a0)))); (a0); return r; }, 1),
  "Carrier.traceparent_name": run_lib(() => { const r = (run_loop($Carrier$traceparent_name$()));  return r; }, 0),
  "Carrier.tracestate_name": run_lib(() => { const r = (run_loop($Carrier$tracestate_name$()));  return r; }, 0),
  "Carrier.named": run_lib((a0, a1) => { const r = (run_loop($Carrier$named$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Carrier.keep": run_lib((a0, a1, a2) => { const r = (run_loop($Carrier$keep$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Carrier.values.go": run_lib((a0, a1, a2) => { const r = (run_loop($Carrier$values$go$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Carrier.values": run_lib((a0, a1) => { const r = (run_loop($Carrier$values$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Text.drop_ows.go": run_lib((a0, a1, a2) => { const r = (run_loop($Text$drop_ows$go$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Text.drop_ows": run_lib((a0) => { const r = (run_loop($Text$drop_ows$((a0)))); (a0); return r; }, 1),
  "Text.trim_ows": run_lib((a0) => { const r = (run_loop($Text$trim_ows$((a0)))); (a0); return r; }, 1),
  "Text.has_comma.go": run_lib((a0, a1) => { const r = (run_loop($Text$has_comma$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Text.has_comma": run_lib((a0) => { const r = (run_loop($Text$has_comma$((a0)))); (a0); return r; }, 1),
  "Text.is_control": run_lib((a0) => { const r = (run_loop($Text$is_control$((a0)))); (a0); return r; }, 1),
  "Text.control.go": run_lib((a0, a1, a2) => { const r = $0m39(run_loop($Text$control$go$((a0), nat_host(a1), $0m40(a2)))); (a0); BigInt(a1); $0m39(a2); return r; }, 3),
  "Read.is_later": run_lib((a0) => { const r = $0m46(run_loop($Read$is_later$((a0)))); (a0); return r; }, 1),
  "Read.is_later.parsed": run_lib((a0) => { const r = $0m46(run_loop($Read$is_later$parsed$((a0)))); (a0); return r; }, 1),
  "Read.clean": run_lib((a0) => { const r = $0m4(run_loop($Read$clean$($0m40(a0)))); $0m39(a0); return r; }, 1),
  "Read.extension": run_lib((a0) => { const r = $0m4(run_loop($Read$extension$((a0)))); (a0); return r; }, 1),
  "Read.prefix": run_lib((a0) => { const r = $0m6(run_loop($Read$prefix$((a0)))); (a0); return r; }, 1),
  "Read.by_version": run_lib((a0, a1) => { const r = $0m6(run_loop($Read$by_version$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Read.known": run_lib((a0) => { const r = $0m6(run_loop($Read$known$((a0)))); (a0); return r; }, 1),
  "Read.invalid": run_lib((a0) => { const r = $0m48(run_loop($Read$invalid$($0m47(a0)))); $0m6(a0); return r; }, 1),
  "Read.single": run_lib((a0, a1) => { const r = $0m48(run_loop($Read$single$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Read.trimmed": run_lib((a0) => { const r = $0m48(run_loop($Read$trimmed$((a0)))); (a0); return r; }, 1),
  "Read.within": run_lib((a0, a1) => { const r = $0m48(run_loop($Read$within$($0m40(a0), (a1)))); $0m39(a0); (a1); return r; }, 2),
  "TraceParent.read": run_lib((a0, a1) => { const r = $0m48(run_loop($TraceParent$read$($0m38(a0), (a1)))); $0m37(a0); (a1); return r; }, 2),
  "Extract.ignored": run_lib((a0) => { const r = $0m50(run_loop($Extract$ignored$((a0)))); (a0); return r; }, 1),
  "Extract.kept": run_lib((a0, a1, a2) => { const r = $0m54(run_loop($Extract$kept$((a0), $0m51(a1), (a2)))); (a0); $0m53(a1); (a2); return r; }, 3),
  "Extract.incoming": run_lib((a0, a1, a2) => { const r = (run_loop($Extract$incoming$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Extract.parsed": run_lib((a0, a1, a2, a3) => { const r = $0m54(run_loop($Extract$parsed$($0m55(a0), (a1), (a2), (a3)))); $0m45(a0); (a1); (a2); (a3); return r; }, 4),
  "Extract.state": run_lib((a0, a1, a2, a3) => { const r = $0m54(run_loop($Extract$state$($0m38(a0), (a1), (a2), (a3)))); $0m37(a0); (a1); (a2); (a3); return r; }, 4),
  "Extract.read": run_lib((a0, a1, a2, a3, a4) => { const r = $0m54(run_loop($Extract$read$($0m56(a0), (a1), $0m38(a2), (a3), (a4)))); $0m48(a0); (a1); $0m37(a2); (a3); (a4); return r; }, 5),
  "Extract.parents": run_lib((a0, a1, a2, a3) => { const r = $0m54(run_loop($Extract$parents$($0m38(a0), (a1), (a2), (a3)))); $0m37(a0); (a1); (a2); (a3); return r; }, 4),
  "Context.extract": run_lib((a0, a1, a2) => { const r = $0m54(run_loop($Context$extract$($0m38(a0), (a1), (a2)))); $0m37(a0); (a1); (a2); return r; }, 3),
  "Extraction.context": run_lib((a0) => { const r = (run_loop($Extraction$context$($0m57(a0)))); $0m54(a0); return r; }, 1),
  "Extraction.parent": run_lib((a0) => { const r = $0m53(run_loop($Extraction$parent$($0m57(a0)))); $0m54(a0); return r; }, 1),
  "Extraction.state": run_lib((a0) => { const r = $0m50(run_loop($Extraction$state$($0m57(a0)))); $0m54(a0); return r; }, 1),
  "Extraction.incoming.base": run_lib((a0) => { const r = (run_loop($Extraction$incoming$base$((a0)))); (a0); return r; }, 1),
  "Extraction.incoming.of": run_lib((a0, a1) => { const r = (run_loop($Extraction$incoming$of$($0m51(a0), (a1)))); $0m53(a0); (a1); return r; }, 2),
  "Extraction.incoming": run_lib((a0) => { const r = (run_loop($Extraction$incoming$($0m57(a0)))); $0m54(a0); return r; }, 1),
  "IncomingContext.context": run_lib((a0) => { const r = (run_loop($IncomingContext$context$((a0)))); (a0); return r; }, 1),
  "IncomingContext.state": run_lib((a0) => { const r = (run_loop($IncomingContext$state$((a0)))); (a0); return r; }, 1),
  "IncomingContext.received": run_lib((a0) => { const r = (run_loop($IncomingContext$received$((a0)))); (a0); return r; }, 1),
  "IncomingContext.parent": run_lib((a0) => { const r = (run_loop($IncomingContext$parent$((a0)))); (a0); return r; }, 1),
  "IncomingContext.from_remote": run_lib((a0, a1) => { const r = (run_loop($IncomingContext$from_remote$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "ReceivedPair.traceparent": run_lib((a0) => { const r = (run_loop($ReceivedPair$traceparent$((a0)))); (a0); return r; }, 1),
  "ReceivedPair.tracestate": run_lib((a0) => { const r = (run_loop($ReceivedPair$tracestate$((a0)))); (a0); return r; }, 1),
  "BaseContext.parent": run_lib((a0) => { const r = (run_loop($BaseContext$parent$((a0)))); (a0); return r; }, 1),
  "BaseContext.state": run_lib((a0) => { const r = (run_loop($BaseContext$state$((a0)))); (a0); return r; }, 1),
  "TraceParentError.show": run_lib((a0) => { const r = (run_loop($TraceParentError$show$($0m52(a0)))); $0m49(a0); return r; }, 1),
  "TraceParentOutcome.show": run_lib((a0) => { const r = (run_loop($TraceParentOutcome$show$($0m51(a0)))); $0m53(a0); return r; }, 1),
  "StateOutcome.show": run_lib((a0) => { const r = (run_loop($StateOutcome$show$($0m58(a0)))); $0m50(a0); return r; }, 1),
  "Extraction.show": run_lib((a0) => { const r = (run_loop($Extraction$show$($0m57(a0)))); $0m54(a0); return r; }, 1),
  "Carrier.is_context": run_lib((a0) => { const r = (run_loop($Carrier$is_context$((a0)))); (a0); return r; }, 1),
  "Carrier.keep_unrelated": run_lib((a0, a1, a2) => { const r = (run_loop($Carrier$keep_unrelated$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Carrier.unrelated.go": run_lib((a0, a1) => { const r = (run_loop($Carrier$unrelated$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Carrier.replace": run_lib((a0, a1) => { const r = (run_loop($Carrier$replace$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Context.field_names": run_lib(() => { const r = (run_loop($Context$field_names$()));  return r; }, 0),
  "Carrier.context_fields": run_lib((a0, a1) => { const r = (run_loop($Carrier$context_fields$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Context.clear": run_lib((a0) => { const r = (run_loop($Context$clear$((a0)))); (a0); return r; }, 1),
  "Injection.of": run_lib((a0, a1) => { const r = (run_loop($Injection$of$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Context.inject": run_lib((a0, a1, a2) => { const r = (run_loop($Context$inject$($0m38(a0), (a1), (a2)))); $0m37(a0); (a1); (a2); return r; }, 3),
  "Injection.carrier": run_lib((a0) => { const r = (run_loop($Injection$carrier$((a0)))); (a0); return r; }, 1),
  "Injection.dropped": run_lib((a0) => { const r = (run_loop($Injection$dropped$((a0)))); (a0); return r; }, 1),
  "Text.joined.go": run_lib((a0, a1) => { const r = (run_loop($Text$joined$go$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Text.joined": run_lib((a0) => { const r = (run_loop($Text$joined$((a0)))); (a0); return r; }, 1),
  "Forward.carrier": run_lib((a0, a1, a2) => { const r = (run_loop($Forward$carrier$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Forward.state": run_lib((a0, a1, a2, a3) => { const r = $0m59(run_loop($Forward$state$($0m55(a0), (a1), (a2), (a3)))); $0m45(a0); (a1); (a2); (a3); return r; }, 4),
  "Forward.parent": run_lib((a0, a1, a2, a3, a4) => { const r = $0m59(run_loop($Forward$parent$($0m56(a0), $0m38(a1), (a2), (a3), (a4)))); $0m48(a0); $0m37(a1); (a2); (a3); (a4); return r; }, 5),
  "Forward.fits": run_lib((a0, a1, a2, a3, a4) => { const r = $0m59(run_loop($Forward$fits$($0m40(a0), $0m38(a1), (a2), (a3), (a4)))); $0m39(a0); $0m37(a1); (a2); (a3); (a4); return r; }, 5),
  "Forward.pair": run_lib((a0, a1, a2) => { const r = $0m59(run_loop($Forward$pair$($0m38(a0), (a1), (a2)))); $0m37(a0); (a1); (a2); return r; }, 3),
  "Context.forward": run_lib((a0, a1, a2) => { const r = $0m59(run_loop($Context$forward$($0m38(a0), (a1), (a2)))); $0m37(a0); (a1); (a2); return r; }, 3),
  "ForwardError.show": run_lib((a0) => { const r = (run_loop($ForwardError$show$($0m61(a0)))); $0m60(a0); return r; }, 1),
  "FailurePolicy.result": run_lib((a0, a1) => { const r = (run_loop($FailurePolicy$result$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Policy.apply": run_lib((a0, a1, a2) => { const r = (run_loop($Policy$apply$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Policy.apply.done": run_lib((a0, a1, a2) => { const r = (run_loop($Policy$apply$done$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Serve.sampled": run_lib((a0) => { const r = (run_loop($Serve$sampled$((a0)))); (a0); return r; }, 1),
  "Serve.from_child": run_lib((a0, a1, a2) => { const r = (run_loop($Serve$from_child$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Serve.from_start": run_lib((a0, a1) => { const r = (run_loop($Serve$from_start$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Serve.replaced": run_lib((a0) => { const r = (run_loop($Serve$replaced$((a0)))); (a0); return r; }, 1),
  "Serve.usable": run_lib((a0, a1, a2, a3) => { const r = $0m62(run_loop($Serve$usable$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "Serve.kept": run_lib((a0, a1, a2, a3) => { const r = $0m62(run_loop($Serve$kept$((a0), (a1), (a2), (a3)))); (a0); (a1); (a2); (a3); return r; }, 4),
  "ServicePlan.new": run_lib((a0, a1, a2) => { const r = $0m62(run_loop($ServicePlan$new$($0m57(a0), (a1), (a2)))); $0m54(a0); (a1); (a2); return r; }, 3),
  "ServicePlan.generation": run_lib((a0) => { const r = $0m33(run_loop($ServicePlan$generation$($0m63(a0)))); $0m62(a0); return r; }, 1),
  "ServicePlan.service": run_lib((a0, a1) => { const r = (run_loop($ServicePlan$service$($0m63(a0), (a1)))); $0m62(a0); (a1); return r; }, 2),
  "Serve.finish": run_lib((a0, a1) => { const r = (run_loop($Serve$finish$($0m63(a0), (a1)))); $0m62(a0); (a1); return r; }, 2),
  "Serve.strict": run_lib((a0) => { const r = (run_loop($Serve$strict$((a0)))); (a0); return r; }, 1),
  "Send.forwarded": run_lib((a0, a1, a2) => { const r = $0m65(run_loop($Send$forwarded$($0m64(a0), (a1), (a2)))); $0m59(a0); (a1); (a2); return r; }, 3),
  "Send.fallback": run_lib((a0, a1, a2, a3) => { const r = $0m65(run_loop($Send$fallback$($0m38(a0), (a1), (a2), (a3)))); $0m37(a0); (a1); (a2); (a3); return r; }, 4),
  "Send.of": run_lib((a0, a1, a2, a3, a4) => { const r = $0m65(run_loop($Send$of$($0m38(a0), (a1), (a2), (a3), (a4)))); $0m37(a0); (a1); (a2); (a3); (a4); return r; }, 5),
  "SendPlan.new": run_lib((a0, a1, a2, a3) => { const r = $0m67(run_loop($SendPlan$new$($0m38(a0), (a1), (a2), (a3)))); $0m37(a0); (a1); (a2); (a3); return r; }, 4),
  "SendPlan.generation": run_lib((a0) => { const r = $0m33(run_loop($SendPlan$generation$($0m68(a0)))); $0m67(a0); return r; }, 1),
  "SendPlan.sent": run_lib((a0, a1) => { const r = $0m65(run_loop($SendPlan$sent$($0m68(a0), (a1)))); $0m67(a0); (a1); return r; }, 2),
  "Send.finish": run_lib((a0, a1) => { const r = $0m69(run_loop($Send$finish$($0m68(a0), (a1)))); $0m67(a0); (a1); return r; }, 2),
  "Send.strict": run_lib((a0) => { const r = $0m72(run_loop($Send$strict$($0m70(a0)))); $0m65(a0); return r; }, 1),
  "Origin.show": run_lib((a0) => { const r = (run_loop($Origin$show$((a0)))); (a0); return r; }, 1),
  "Service.origin": run_lib((a0) => { const r = (run_loop($Service$origin$((a0)))); (a0); return r; }, 1),
  "Service.outgoing": run_lib((a0) => { const r = (run_loop($Service$outgoing$((a0)))); (a0); return r; }, 1),
  "Service.error": run_lib((a0) => { const r = (run_loop($Service$error$((a0)))); (a0); return r; }, 1),
  "Service.set": run_lib((a0, a1, a2) => { const r = (run_loop($Service$set$((a0), (a1), (a2)))); (a0); (a1); (a2); return r; }, 3),
  "Service.remove": run_lib((a0, a1) => { const r = (run_loop($Service$remove$((a0), (a1)))); (a0); (a1); return r; }, 2),
  "Service.show": run_lib((a0) => { const r = (run_loop($Service$show$((a0)))); (a0); return r; }, 1),
  "Unforwarded.show": run_lib((a0) => { const r = (run_loop($Unforwarded$show$($0m71(a0)))); $0m66(a0); return r; }, 1),
  "Sent.carrier": run_lib((a0) => { const r = (run_loop($Sent$carrier$($0m70(a0)))); $0m65(a0); return r; }, 1),
  "Sent.operation": run_lib((a0) => { const r = (run_loop($Sent$operation$($0m70(a0)))); $0m65(a0); return r; }, 1),
  "Sent.error": run_lib((a0) => { const r = (run_loop($Sent$error$($0m70(a0)))); $0m65(a0); return r; }, 1),
  "Sent.dropped": run_lib((a0) => { const r = (run_loop($Sent$dropped$($0m70(a0)))); $0m65(a0); return r; }, 1),
  "Send.fresh": run_lib((a0) => { const r = (run_loop($Send$fresh$((a0)))); (a0); return r; }, 1),
  "Sent.show": run_lib((a0) => { const r = (run_loop($Sent$show$($0m70(a0)))); $0m65(a0); return r; }, 1),
};
