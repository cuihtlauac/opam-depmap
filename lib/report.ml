(* Metrics over a collected graph. Their definitions mirror the browser JS in
   lib/template.html (cross-referenced below) -- the page computes them at render
   time and discards them; here we persist them. Change one, change the other. *)

module S = Set.Make (String)

(* --- number formatting (byte-stable; pinned by test/golden) ------------- *)

(* x rounded to 3 decimals: trailing zeros stripped, but always at least one
   fractional digit (e.g. 0.1, 0.0, 0.667). *)
let float3 x =
  let s = Printf.sprintf "%.3f" x in
  let i = ref (String.length s - 1) in
  while !i > 0 && s.[!i] = '0' do decr i done;
  if s.[!i] = '.' then incr i;
  String.sub s 0 (!i + 1)

(* round half to even (banker's rounding): the percentile index and the
   top-5 percentage both go through it. *)
let round_half_even x =
  let fl = Float.floor x in
  let d = x -. fl in
  if d < 0.5 then fl
  else if d > 0.5 then fl +. 1.
  else if Float.rem fl 2. = 0. then fl else fl +. 1.

(* fmt(b): a human byte size for the digest. *)
let fmt b =
  if b >= 1048576 then Printf.sprintf "%.1f MiB" (float b /. 1048576.)
  else if b >= 1024 then Printf.sprintf "%.0f KiB" (float b /. 1024.)
  else Printf.sprintf "%d B" b

let render ?(top = 15) ~md (g : Graph.t) =
  let nodes = g.nodes in
  let ids = List.map (fun (n : Graph.node) -> n.id) nodes in
  let self_tbl = Hashtbl.create 1024 and kind_tbl = Hashtbl.create 1024 in
  List.iter
    (fun (n : Graph.node) -> Hashtbl.replace self_tbl n.id n.self; Hashtbl.replace kind_tbl n.id n.kind)
    nodes;
  let self_of i = Hashtbl.find self_tbl i in
  let kind_of i = Hashtbl.find kind_tbl i in
  let id_set = S.of_list ids in

  (* adjacency: edge [a, b] = "a requires b"; succ = deps, pred = consumers.
     Order within a list is irrelevant downstream (requires is sorted; pred is
     used order-independently), so we keep the cheap prepend. *)
  let succ = Hashtbl.create 1024 and pred = Hashtbl.create 1024 in
  List.iter (fun i -> Hashtbl.replace succ i []; Hashtbl.replace pred i []) ids;
  List.iter
    (fun (a, b) ->
      if S.mem a id_set && S.mem b id_set then begin
        Hashtbl.replace succ a (b :: Hashtbl.find succ a);
        Hashtbl.replace pred b (a :: Hashtbl.find pred b)
      end)
    g.edges;
  let succ_of i = Hashtbl.find succ i and pred_of i = Hashtbl.find pred i in
  let fan_in i = List.length (pred_of i) and fan_out i = List.length (succ_of i) in

  (* depth: longest path from an entry down to n. Mirrors metricBase/fl in template.html:
     0 at entries; the provisional 0 before recursing is also the cycle guard. *)
  let depth_tbl = Hashtbl.create 1024 in
  let rec depth i =
    match Hashtbl.find_opt depth_tbl i with
    | Some d -> d
    | None ->
        Hashtbl.replace depth_tbl i 0;
        let d =
          match pred_of i with [] -> 0 | ps -> 1 + List.fold_left (fun m p -> max m (depth p)) 0 ps
        in
        Hashtbl.replace depth_tbl i d;
        d
  in
  List.iter (fun i -> ignore (depth i)) ids;
  let depth i = Hashtbl.find depth_tbl i in

  (* transitive footprint: self + the self of everything reachable via requires.
     Mirrors the moveTip cone in template.html. *)
  let reachable i =
    let seen = ref S.empty and stack = ref (succ_of i) in
    while !stack <> [] do
      let u = List.hd !stack in
      stack := List.tl !stack;
      if not (S.mem u !seen) then begin
        seen := S.add u !seen;
        stack := succ_of u @ !stack
      end
    done;
    S.remove i !seen
  in
  let trans_tbl = Hashtbl.create 1024 in
  List.iter (fun i -> Hashtbl.replace trans_tbl i (self_of i + S.fold (fun m a -> a + self_of m) (reachable i) 0)) ids;
  let transitive i = Hashtbl.find trans_tbl i in

  (* size distribution over sized nodes. Mirrors the statline in template.html. *)
  let sizes = List.filter (fun s -> s > 0) (List.map self_of ids) |> List.sort compare |> Array.of_list in
  let nsz = Array.length sizes in
  let tot = Array.fold_left ( + ) 0 sizes in
  let pct p =
    if nsz = 0 then 0
    else sizes.(min (nsz - 1) (max 0 (int_of_float (round_half_even (p *. float (nsz - 1))))))
  in
  let gs = ref 0 in
  Array.iteri (fun i v -> gs := !gs + ((i + 1) * v)) sizes;
  let gini = if nsz > 0 && tot > 0 then (float (2 * !gs) /. float (nsz * tot)) -. (float (nsz + 1) /. float nsz) else 0.0 in
  let top5 = let s = ref 0 in for k = max 0 (nsz - 5) to nsz - 1 do s := !s + sizes.(k) done; !s in
  let top5_share = if tot > 0 then float top5 /. float tot else 0.0 in

  (* rankings: by key descending, ties broken by id. *)
  let take n l = List.filteri (fun i _ -> i < n) l in
  let ranked key =
    take top
      (List.stable_sort (fun a b -> let c = compare (key b) (key a) in if c <> 0 then c else String.compare a b) ids)
  in
  let top_by_self = ranked self_of and top_by_transitive = ranked transitive and top_by_fan_in = ranked fan_in in

  (* one representative longest chain: entry -> ... -> deepest node. *)
  let chain =
    match ids with
    | [] -> []
    | hd :: tl ->
        let best = List.fold_left (fun b i -> if (depth i, i) > (depth b, b) then i else b) hd tl in
        let rec walk cur acc =
          if depth cur <= 0 then acc
          else
            match List.filter (fun p -> depth p = depth cur - 1) (pred_of cur) with
            | [] -> acc
            | up -> let nx = List.fold_left min (List.hd up) (List.tl up) in walk nx (nx :: acc)
        in
        walk best [ best ]
  in

  let own_count = List.length (List.filter (fun (n : Graph.node) -> n.kind = Own) nodes) in
  let ext_count = List.length (List.filter (fun (n : Graph.node) -> n.kind = External) nodes) in
  let total_self = List.fold_left (fun a (n : Graph.node) -> a + n.self) 0 nodes in

  if md then begin
    let table head rows =
      let line cells = "| " ^ String.concat " | " cells ^ " |" in
      let sep = "|" ^ String.concat "|" (List.map (fun _ -> "---") head) ^ "|" in
      String.concat "\n" (line head :: sep :: List.map line rows)
    in
    let top5_pct = Printf.sprintf "%.0f" (100. *. float_of_string (float3 top5_share)) in
    let chain_line = if chain = [] then "_none_" else String.concat " \xe2\x86\x92 " chain in
    String.concat "\n"
      [ Printf.sprintf "# %s \xe2\x80\x94 dependency & footprint report" g.project;
        "";
        Printf.sprintf
          "**%d** nodes (%d own \xc2\xb7 %d external), **%d** edges, **%d** roots \xc2\xb7 total footprint **%s**."
          (List.length ids) own_count ext_count (List.length g.edges) (List.length g.roots) (fmt total_self);
        "";
        Printf.sprintf
          "Distribution (sized nodes, n=%d): median %s \xc2\xb7 p90 %s \xc2\xb7 p95 %s \xc2\xb7 p99 %s \xc2\xb7 Gini %s \xc2\xb7 top-5 = %s%% of bytes."
          nsz (fmt (pct 0.5)) (fmt (pct 0.9)) (fmt (pct 0.95)) (fmt (pct 0.99)) (float3 gini) top5_pct;
        "";
        Printf.sprintf "## Top %d by own footprint" top;
        table [ "library"; "own bytes"; "kind" ]
          (List.map (fun i -> [ i; fmt (self_of i); Graph.string_of_kind (kind_of i) ]) top_by_self);
        "";
        Printf.sprintf "## Top %d by transitive footprint (self + everything it pulls in)" top;
        table [ "library"; "transitive"; "own" ]
          (List.map (fun i -> [ i; fmt (transitive i); fmt (self_of i) ]) top_by_transitive);
        "";
        Printf.sprintf "## Top %d most depended-upon (fan-in)" top;
        table [ "library"; "consumers" ] (List.map (fun i -> [ i; string_of_int (fan_in i) ]) top_by_fan_in);
        "";
        Printf.sprintf "## Longest dependency chain (depth %d)" (if chain = [] then 0 else List.length chain - 1);
        chain_line;
        "" ]
  end
  else begin
    let open Graph in
    let summary =
      Obj
        [ ("nodes_total", Int (List.length ids));
          ("nodes_sized", Int nsz);
          ("edges", Int (List.length g.edges));
          ("roots", Int (List.length g.roots));
          ("own", Int own_count);
          ("external", Int ext_count);
          ("total_self_bytes", Int total_self);
          ("median_bytes", Int (pct 0.5));
          ("p90_bytes", Int (pct 0.9));
          ("p95_bytes", Int (pct 0.95));
          ("p99_bytes", Int (pct 0.99));
          ("gini", Raw (float3 gini));
          ("top5_share", Raw (float3 top5_share)) ]
    in
    let metric_notes =
      Obj
        [ ("self", Str "own compiled-artifact bytes (a proxy, not install size)");
          ("transitive", Str "self plus the self of every library reachable via `requires`");
          ("depth", Str "longest path from an entry (a root nothing requires) down to this node");
          ("fan_in", Str "number of libraries that directly require this one");
          ("fan_out", Str "number of libraries this one directly requires");
          ("requires", Str "direct findlib dependencies (the `succ` adjacency)") ]
    in
    json_to_string
      (Obj
         [ ("project", Str g.project);
           ("units", Str "bytes");
           ("metric_notes", metric_notes);
           ("summary", summary);
           ("roots", Arr (List.map (fun r -> Str r) g.roots));
           ( "top_by_self",
             Arr
               (List.map
                  (fun i -> Obj [ ("id", Str i); ("self", Int (self_of i)); ("kind", Str (string_of_kind (kind_of i))) ])
                  top_by_self) );
           ( "top_by_transitive",
             Arr
               (List.map
                  (fun i -> Obj [ ("id", Str i); ("transitive", Int (transitive i)); ("self", Int (self_of i)) ])
                  top_by_transitive) );
           ( "top_by_fan_in",
             Arr (List.map (fun i -> Obj [ ("id", Str i); ("fan_in", Int (fan_in i)) ]) top_by_fan_in) );
           ( "longest_chain",
             Obj
               [ ("depth", Int (if chain = [] then 0 else List.length chain - 1));
                 ("path", Arr (List.map (fun c -> Str c) chain)) ] );
           ( "nodes",
             Arr
               (List.map
                  (fun i ->
                    Obj
                      [ ("id", Str i);
                        ("kind", Str (string_of_kind (kind_of i)));
                        ("self", Int (self_of i));
                        ("transitive", Int (transitive i));
                        ("depth", Int (depth i));
                        ("fan_in", Int (fan_in i));
                        ("fan_out", Int (fan_out i));
                        ("requires", Arr (List.map (fun r -> Str r) (List.sort String.compare (succ_of i)))) ])
                  ids) ) ])
  end
