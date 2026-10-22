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
   :text ("The Lobster port of serialize, the open-source bitpacking serializer: the same wire as serialize.c, byte for byte, with the same refusals. The work is on the integration branch sprint/serialize-lobster and is not yet on main.")
   :rows
   (("design" "Design, family stubs and test runner")
    ("standard" "STANDARD.md matches serialize v1.17.0")
    ("ci" "Fleet CI workflow and its invariant test")
    ("bitpacker" "64-bit bitpacker and window reader")
    ("integers" "Ranged integers, int64, int128, uint128 and relative ints")
    ("floats" "float, double, fixed and compressed floats")
    ("strings" "Bytes, strings, wide strings, align and objects")
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
    ("conformance" "lobster" "port/conformance")
    ("fuzz" "lobster" "port/fuzz")
    ("bench" "lobster" "port/bench")
    ("bench-report" "lobster" "port/bench-report")))
  (:id "serialize-lobster-design" :type :task :title "Design, family stubs and test runner" :state :done :evidence ("land commit 40290f8f2ab5 on sprint/serialize-lobster (card serialize-lobster-design, stream serialize-lobster)"))
  (:id "port/design" :type :work-set :children ("serialize-lobster-design"))
  (:id "serialize-lobster-standard-matches-upstream" :type :task :title "STANDARD.md matches serialize v1.17.0" :state :done :evidence ("land commit 53cb234df4a4 on sprint/serialize-lobster (card serialize-lobster-standard-matches-upstream, stream serialize-lobster)"))
  (:id "port/standard" :type :work-set :children ("serialize-lobster-standard-matches-upstream"))
  (:id "serialize-lobster-ci" :type :task :title "Fleet CI workflow and its invariant test" :state :done :evidence ("land commit 164cd027da18 on sprint/serialize-lobster (card serialize-lobster-ci, stream serialize-lobster)"))
  (:id "port/ci" :type :work-set :children ("serialize-lobster-ci"))
  (:id "serialize-lobster-bitpacker" :type :task :title "64-bit bitpacker and window reader" :state :done :evidence ("land commit 60dc28704279 on sprint/serialize-lobster (card serialize-lobster-bitpacker, stream serialize-lobster)"))
  (:id "port/bitpacker" :type :work-set :children ("serialize-lobster-bitpacker"))
  (:id "serialize-lobster-integers" :type :task :title "Ranged integers, int64, int128, uint128 and relative ints" :state :done :evidence ("land commit 3c39205c1ff4 on sprint/serialize-lobster (card serialize-lobster-integers, stream serialize-lobster)"))
  (:id "port/integers" :type :work-set :children ("serialize-lobster-integers"))
  (:id "serialize-lobster-floats" :type :task :title "float, double, fixed and compressed floats" :state :done :evidence ("land commit b929e81b9f5f on sprint/serialize-lobster (card serialize-lobster-floats, stream serialize-lobster)"))
  (:id "port/floats" :type :work-set :children ("serialize-lobster-floats"))
  (:id "serialize-lobster-strings" :type :task :title "Bytes, strings, wide strings, align and objects" :state :done :evidence ("land commit 5ce447ab8ea4 on sprint/serialize-lobster (card serialize-lobster-strings, stream serialize-lobster)"))
  (:id "port/strings" :type :work-set :children ("serialize-lobster-strings"))
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
