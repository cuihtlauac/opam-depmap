open Opam_depmap

let contains s sub =
  let n = String.length sub in
  let rec go i = i + n <= String.length s && (String.sub s i n = sub || go (i + 1)) in
  go 0

(* --- Graph ------------------------------------------------------------------ *)

let sample =
  Graph.make ~project:"demo" ~roots:[ "demo" ]
    ~nodes:
      [ { id = "dep"; kind = External; self = 2048 };
        { id = "demo"; kind = Own; self = 10 } ]
    ~edges:[ ("demo", "dep"); ("demo", "dep") ]

let test_make () =
  Alcotest.(check (list string)) "nodes sorted" [ "demo"; "dep" ]
    (List.map (fun (n : Graph.node) -> n.id) sample.nodes);
  Alcotest.(check int) "edges deduplicated" 1 (List.length sample.edges)

let test_print () =
  Alcotest.(check string) "minified"
    {|{"project":"demo","roots":["demo"],"nodes":[{"id":"demo","kind":"own","self":10},{"id":"dep","kind":"external","self":2048}],"edges":[["demo","dep"]]}|}
    (Graph.to_string ~minify:true sample);
  Alcotest.(check string) "indent=1"
    "{\n \"project\": \"demo\",\n \"roots\": [],\n \"nodes\": [],\n \"edges\": []\n}"
    (Graph.to_string { sample with roots = []; nodes = []; edges = [] })

let test_roundtrip () =
  List.iter
    (fun minify ->
      match Graph.of_string (Graph.to_string ~minify sample) with
      | Ok g -> Alcotest.(check bool) "same graph" true (g = sample)
      | Error e -> Alcotest.fail e)
    [ true; false ]

let test_bad_json () =
  Alcotest.(check bool) "rejects unknown kind" true
    (Result.is_error
       (Graph.of_string {|{"project":"p","roots":[],"nodes":[{"id":"a","kind":"x","self":1}],"edges":[]}|}))

(* --- Collect ---------------------------------------------------------------- *)

(* pkg.a -> pkg.b -> ext; pkg.a -> ext.sub; ext and ext.sub share a dir. *)
let fake =
  let req = function
    | "pkg" -> [ "pkg.b" ]
    | "pkg.a" -> [ "pkg.b"; "ext.sub" ]
    | "pkg.b" -> [ "ext" ]
    | _ -> []
  in
  let owners = [ ("pkg", "pkg"); ("pkg.a", "pkg"); ("pkg.b", "pkg"); ("ext", "ext"); ("ext.sub", "ext") ] in
  let dirs = [ ("pkg", "/p"); ("pkg.a", "/p/a"); ("pkg.b", "/p/b"); ("ext", "/e"); ("ext.sub", "/e") ] in
  Collect.
    { libs = [ "ext"; "ext.sub"; "other"; "pkg"; "pkg.a"; "pkg.b" ];
      exists = (fun l -> List.mem_assoc l owners || l = "other");
      requires = req;
      dir = (fun l -> List.assoc_opt l dirs);
      bytes = (fun d -> String.length d * 100);
      owner = (fun l -> List.assoc_opt l owners) }

let run ?(same_repo = [ "pkg" ]) o =
  match Collect.run fake ~same_repo o with Ok g -> g | Error e -> Alcotest.fail e

let node g id = List.find (fun (n : Graph.node) -> n.id = id) g.Graph.nodes

let test_closure () =
  let g = run (Collect.options "pkg") in
  Alcotest.(check (list string)) "nodes" [ "ext"; "ext.sub"; "pkg"; "pkg.a"; "pkg.b" ]
    (List.map (fun (n : Graph.node) -> n.id) g.nodes);
  Alcotest.(check (list string)) "roots: entries nothing requires" [ "pkg"; "pkg.a" ] g.roots;
  Alcotest.(check int) "edges" 4 (List.length g.edges)

let test_sizes () =
  let g = run (Collect.options "pkg") in
  Alcotest.(check int) "shortest name gets the shared dir" 200 (node g "ext").self;
  Alcotest.(check int) "the other gets 0" 0 (node g "ext.sub").self;
  Alcotest.(check int) "own dir" 400 (node g "pkg.a").self

let test_kind () =
  let g = run (Collect.options "pkg") in
  Alcotest.(check bool) "own" true ((node g "pkg.b").kind = Own);
  Alcotest.(check bool) "external" true ((node g "ext").kind = External);
  let g = run (Collect.options ~own:[ "ext" ] "pkg") in
  Alcotest.(check bool) "--own overrides" true ((node g "ext").kind = Own && (node g "pkg").kind = External)

let test_entries () =
  let g = run (Collect.options ~entries:[ "pkg.b" ] ~name:"Demo" "pkg") in
  Alcotest.(check (list string)) "roots" [ "pkg.b" ] g.roots;
  Alcotest.(check string) "name" "Demo" g.project;
  Alcotest.(check int) "nodes" 2 (List.length g.nodes)

let test_errors () =
  let err o = Result.is_error (Collect.run fake ~same_repo:[] o) in
  Alcotest.(check bool) "no library" true (err (Collect.options "nolib"));
  Alcotest.(check bool) "unknown entry" true (err (Collect.options ~entries:[ "nope" ] "pkg"))

(* --- Render ----------------------------------------------------------------- *)

let test_render () =
  let html = Render.html sample in
  Alcotest.(check bool) "data inlined" true (contains html {|"project":"demo"|});
  Alcotest.(check bool) "no placeholder" false (contains html "__DATA__");
  Alcotest.(check bool) "name substituted" true (contains html "<title>demo dependency map</title>");
  Alcotest.(check bool) "no Dream left" false (contains html "Dream");
  Alcotest.(check bool) "self-contained" false (contains html "<script src")

(* --- Report ----------------------------------------------------------------- *)

(* a -> b -> c and a -> d, so depth(c)=2 and the longest chain is a -> b -> c. *)
let chain_graph =
  Graph.make ~project:"demo" ~roots:[ "a" ]
    ~nodes:
      [ { id = "a"; kind = Own; self = 100 };
        { id = "b"; kind = External; self = 200 };
        { id = "c"; kind = External; self = 50 };
        { id = "d"; kind = External; self = 10 } ]
    ~edges:[ ("a", "b"); ("b", "c"); ("a", "d") ]

let test_report_json () =
  let s = Report.render ~md:false chain_graph in
  (* transitive(a) = self(a) + self(b,c,d) = 100+200+50+10 *)
  Alcotest.(check bool) "transitive" true (contains s "\"transitive\": 360");
  Alcotest.(check bool) "depth of c" true (contains s "\"depth\": 2");
  Alcotest.(check bool) "adjacency" true (contains s "\"fan_in\"")

let test_report_md () =
  let s = Report.render ~md:true chain_graph in
  Alcotest.(check bool) "longest chain depth" true (contains s "Longest dependency chain (depth 2)");
  Alcotest.(check bool) "chain path" true (contains s "a \xe2\x86\x92 b \xe2\x86\x92 c");
  Alcotest.(check bool) "digest title" true (contains s "demo \xe2\x80\x94 dependency & footprint report")

(* --- Golden (byte-for-byte; the renderers are pure functions of data.json) -- *)

let read_file f = In_channel.with_open_bin f In_channel.input_all
let graph_of f = match Graph.of_string (read_file f) with Ok g -> g | Error e -> Alcotest.fail e

let test_golden_render () =
  (* real-world: the committed Dream example (PACKAGE mode, no subtitle) *)
  Alcotest.(check string) "dream page"
    (read_file "../example/dream/squarified_treemap.html")
    (Render.html (graph_of "../example/dream/data.json"));
  (* synthetic fixture exercising the subtitle swap (switch-style header) *)
  Alcotest.(check string) "fixture page" (read_file "golden/map.html") (Render.html (graph_of "golden/data.json"))

let test_golden_report () =
  let g = graph_of "golden/data.json" in
  Alcotest.(check string) "report.json" (read_file "golden/report.json") (Report.render ~md:false g);
  Alcotest.(check string) "report.md" (read_file "golden/report.md") (Report.render ~md:true g)

let () =
  Alcotest.run "opam-depmap"
    [ ( "graph",
        [ Alcotest.test_case "make" `Quick test_make;
          Alcotest.test_case "print" `Quick test_print;
          Alcotest.test_case "roundtrip" `Quick test_roundtrip;
          Alcotest.test_case "bad json" `Quick test_bad_json ] );
      ( "collect",
        [ Alcotest.test_case "closure" `Quick test_closure;
          Alcotest.test_case "sizes" `Quick test_sizes;
          Alcotest.test_case "kind" `Quick test_kind;
          Alcotest.test_case "entries" `Quick test_entries;
          Alcotest.test_case "errors" `Quick test_errors ] );
      ("render", [ Alcotest.test_case "html" `Quick test_render ]);
      ( "report",
        [ Alcotest.test_case "json" `Quick test_report_json;
          Alcotest.test_case "md" `Quick test_report_md ] );
      ( "golden",
        [ Alcotest.test_case "render" `Quick test_golden_render;
          Alcotest.test_case "report" `Quick test_golden_report ] ) ]
