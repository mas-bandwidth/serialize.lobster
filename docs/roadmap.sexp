; The serialize.lobster roadmap: the data ROADMAP.md is generated from, in the shape of
; mas-bandwidth/schema's docs/roadmap.sexp (one restricted S-expression; data, never evaluated).
; ROADMAP.md is rendered by tools/roadmap/render.lisp (vendored from mas-bandwidth/schema
; tools/roadmap at 609d4e032aff3323e4ee3a3495a1c86d56720914): edit this file, then `make roadmap`; `make roadmap-check`
; fails when the committed page is not what this data renders. Never edit ROADMAP.md by hand.
;
; A cell is ✅ only when every task under it is :done, and a :done task names its evidence (the
; land commit of the sprint card that built it, on the branch named). Every ❌ task names its
; sprint card, the archive file that keeps the card's whole brief and record, and its last pushed
; head. Rewritten 2026-10-20 at the pit stop, when Glenn archived every sprint stream that is not
; rocketnet: "Archive everything from the sprint that isn't rocketnet. Move the cards into their
; respective roadmaps."
(:schema 1 :root "serialize-lobster/roadmap"
 :page (:title "serialize.lobster roadmap"
        :roadmaps ("port")
        :closing ((:title "About this page" :text ("Each table lists the features of one area: ✅ is built, tested and landed, with the evidence in the source data; ❌ is not yet. The open rows were sprint cards when the sprint stopped for its pit stop on 2026-10-20; each one names its card, its archived brief and any pushed head in the source data, so the work can be picked up again."))))
 :nodes
 ((:id "serialize-lobster/roadmap" :type :work-set :children ("port"))
  (:id "port" :type :roadmap :title "The Lobster port of serialize"
   :text ("The Lobster port of serialize, the open-source bitpacking serializer: the same wire as serialize.c, byte for byte, with the same refusals, each for the same reason. Format 2.0 (serialize v2.0.0): finite floats only, an end that refuses trailing bytes and set padding, canonical int_relative, and no wstring. Standard 2.1 (serialize v2.1.0): the caller's own refusal, rejected, and the uniform rules U1 to U16. The 2.1.1 rulings (serialize v2.1.1): one write-misuse mechanism, the trap; a measure checks what a write checks; copy_string backs off to a whole character; the public surface documented.")
   :rows
   (("design" "Design, family stubs and test runner")
    ("standard" "STANDARD.md matches serialize v2.1.1")
    ("ci" "Fleet CI workflow and its invariant test")
    ("bitpacker" "64-bit bitpacker and window reader")
    ("integers" "Ranged integers, int64, int128, uint128 and relative ints")
    ("floats" "float, double, fixed and compressed floats")
    ("strings" "Bytes, strings, align and objects")
    ("format2" "Format 2.0: refusal reasons, finite floats, end, canonical int_relative")
    ("standard21" "Standard 2.1: the rejected refusal reason and the uniform rules U1 to U16, with the 2.1.1 rulings")
    ("controls" "Every per-rule control fails exactly its expected vectors")
    ("conformance" "Whole conformance corpus, byte for byte with serialize.c")
    ("fuzz" "Differential fuzzing against serialize.c")
    ("bench" "Benchmark against serialize.c, C++ serialize and serialize.rs")
    ("bench-report" "Goose vs C++ vs Rust (and Lobster) benchmark report"))
   :columns (("lobster" "lobster"))
   :cells
   (("design" "lobster" "port/design")
    ("standard" "lobster" "port/standard")
    ("ci" "lobster" "port/ci")
    ("bitpacker" "lobster" "port/bitpacker")
    ("integers" "lobster" "port/integers")
    ("floats" "lobster" "port/floats")
    ("strings" "lobster" "port/strings")
    ("format2" "lobster" "port/format2")
    ("standard21" "lobster" "port/standard21")
    ("controls" "lobster" "port/controls")
    ("conformance" "lobster" "port/conformance")
    ("fuzz" "lobster" "port/fuzz")
    ("bench" "lobster" "port/bench")
    ("bench-report" "lobster" "port/bench-report")))
  (:id "serialize-lobster-design" :type :task :title "Design, family stubs and test runner" :state :done :evidence ("land commit 40290f8f2ab5 on sprint/serialize-lobster (card serialize-lobster-design, stream serialize-lobster)"))
  (:id "port/design" :type :work-set :children ("serialize-lobster-design"))
  (:id "serialize-lobster-standard-matches-upstream" :type :task :title "STANDARD.md matches serialize v1.17.0" :state :done :evidence ("land commit 53cb234df4a4 on sprint/serialize-lobster (card serialize-lobster-standard-matches-upstream, stream serialize-lobster)"))
  (:id "serialize-lobster-standard-v2" :type :task :title "STANDARD.md, IMPLEMENTING.md, conformance/ and conformance-controls/ match serialize v2.0.0" :state :done :evidence ("commit 6abfa77 on rowan/format-2.0 (tools/revendor.sh v2.0.0; the CI corpus job diffs all four against the tag)"))
  (:id "serialize-lobster-standard-v21" :type :task :title "STANDARD.md, IMPLEMENTING.md, conformance/ and conformance-controls/ match serialize v2.1.0" :state :done :evidence ("branch rowan/2.1.0: tools/revendor.sh v2.1.0 (884bc3098c96); the CI corpus job diffs all four against the tag"))
  (:id "serialize-lobster-standard-v211" :type :task :title "STANDARD.md, IMPLEMENTING.md, conformance/ and conformance-controls/ match serialize v2.1.1" :state :done :evidence ("branch rowan/2.1.1-rulings: tools/revendor.sh v2.1.1; the CI corpus job diffs all four against the tag"))
  (:id "port/standard" :type :work-set :children ("serialize-lobster-standard-matches-upstream" "serialize-lobster-standard-v2" "serialize-lobster-standard-v21" "serialize-lobster-standard-v211"))
  (:id "serialize-lobster-ci" :type :task :title "Fleet CI workflow and its invariant test" :state :done :evidence ("land commit 164cd027da18 on sprint/serialize-lobster (card serialize-lobster-ci, stream serialize-lobster)"))
  (:id "port/ci" :type :work-set :children ("serialize-lobster-ci"))
  (:id "serialize-lobster-bitpacker" :type :task :title "64-bit bitpacker and window reader" :state :done :evidence ("land commit 60dc28704279 on sprint/serialize-lobster (card serialize-lobster-bitpacker, stream serialize-lobster)"))
  (:id "port/bitpacker" :type :work-set :children ("serialize-lobster-bitpacker"))
  (:id "serialize-lobster-integers" :type :task :title "Ranged integers, int64, int128, uint128 and relative ints" :state :done :evidence ("land commit 3c39205c1ff4 on sprint/serialize-lobster (card serialize-lobster-integers, stream serialize-lobster)"))
  (:id "port/integers" :type :work-set :children ("serialize-lobster-integers"))
  (:id "serialize-lobster-floats" :type :task :title "float, double, fixed and compressed floats" :state :done :evidence ("land commit b929e81b9f5f on sprint/serialize-lobster (card serialize-lobster-floats, stream serialize-lobster)"))
  (:id "port/floats" :type :work-set :children ("serialize-lobster-floats"))
  (:id "serialize-lobster-strings" :type :task :title "Bytes, strings, align and objects (wstring removed by format 2.0)" :state :done :evidence ("land commit 5ce447ab8ea4 on sprint/serialize-lobster (card serialize-lobster-strings, stream serialize-lobster)"))
  (:id "port/strings" :type :work-set :children ("serialize-lobster-strings"))
  (:id "serialize-lobster-format2" :type :task :title "Format 2.0: refusal reasons, finite floats, end, canonical int_relative, no wstring" :state :done :evidence ("commit 6abfa77 on rowan/format-2.0: conformance 397 of 397, 149 refusals each for its stated reason; fuzz against serialize.c v2.0.0 compares reasons"))
  (:id "port/format2" :type :work-set :children ("serialize-lobster-format2"))
  (:id "serialize-lobster-standard21" :type :task :title "Standard 2.1: the rejected reason (reject, the object latch) and U1 to U16 (read misuse refuses, measure latches nothing, end on a writer, copy_string, precomputed max_integer_value domain)" :state :done :evidence ("branch rowan/2.1.0: conformance 413 of 413, 156 refusals each for its stated reason; 18 controls fail exactly their lists; test/uniform with a reversed witness per changed rule"))
  (:id "serialize-lobster-rulings-211" :type :task :title "The 2.1.1 rulings: write and measure misuse traps, never latches (U9); a measure makes every write check but room (U6); fail and a refusing object on a write or a measure record nothing; copy_string backs off to a whole character and the public surface is documented (U15)" :state :done :evidence ("branch rowan/2.1.1-rulings: test/uniform/u9_test.lobster, red on 2.1.0 main and green after; 37 controls and witnesses, 8 new reversed witnesses"))
  (:id "port/standard21" :type :work-set :children ("serialize-lobster-standard21" "serialize-lobster-rulings-211"))
  (:id "serialize-lobster-controls" :type :task :title "Every per-rule control fails exactly its expected vectors" :state :done :evidence ("commit 6abfa77 on rowan/format-2.0: make controls, 15 of 15 conformance-controls plus 4 reversed witnesses and the harness's own control; at 2.1, 18 of 18 plus 10 witnesses"))
  (:id "port/controls" :type :work-set :children ("serialize-lobster-controls"))
  (:id "serialize-lobster-conformance" :type :task :title "Whole conformance corpus, byte for byte with serialize.c" :state :done :evidence ("land commit f936ec82d17e on sprint/serialize-lobster (card serialize-lobster-conformance, stream serialize-lobster)"))
  (:id "port/conformance" :type :work-set :children ("serialize-lobster-conformance"))
  (:id "serialize-lobster-fuzz-differential" :type :task :title "Differential fuzzing against serialize.c" :state :done :evidence ("land commit 2a26bfdb80ac on sprint/serialize-lobster (card serialize-lobster-fuzz-differential, stream serialize-lobster)"))
  (:id "port/fuzz" :type :work-set :children ("serialize-lobster-fuzz-differential"))
  (:id "serialize-lobster-bench" :type :task :title "Benchmark against serialize.c, C++ serialize and serialize.rs" :state :todo :evidence ()
   :note "card serialize-lobster-bench (stream serialize-lobster, working when archived); last pushed head bea0405a5e68df20de65535238d45ae0162c4270 on sprint/serialize-lobster-bench.w1.g1.e21; brief kept in ~/rowan-working/sprint-archive-2026-10-20/serialize-lobster/serialize-lobster-bench.md")
  (:id "port/bench" :type :work-set :children ("serialize-lobster-bench"))
  (:id "serialize-lobster-bench-report" :type :task :title "Goose vs C++ vs Rust (and Lobster) benchmark report" :state :todo :evidence ()
   :note "card serialize-lobster-bench-report (stream serialize-lobster, waiting when archived); no pushed head; brief kept in ~/rowan-working/sprint-archive-2026-10-20/serialize-lobster/serialize-lobster-bench-report.md")
  (:id "port/bench-report" :type :work-set :children ("serialize-lobster-bench-report"))))
