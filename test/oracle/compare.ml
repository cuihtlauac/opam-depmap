(* compare PKG ORACLE.json NEW.json EXPECTED_DIFFS

   Compares two data.json files and prints one line per difference:
     PKG FIELD +ITEM   (only in NEW)      PKG FIELD -ITEM   (only in ORACLE)
   Exits 1 if any difference is not listed in EXPECTED_DIFFS, whose lines are
   `PKG FIELD ±ITEM  # reason`. Only `roots` and `kind` differences can be
   expected; the graph (nodes, edges) and the sizes must always match. *)

open Opam_depmap

let load f =
  match Graph.of_string (In_channel.with_open_bin f In_channel.input_all) with
  | Ok g -> g
  | Error e -> Printf.eprintf "%s: %s\n" f e; exit 2

let set_diff field show a b =
  let module S = Set.Make (String) in
  let a = S.of_list (List.map show a) and b = S.of_list (List.map show b) in
  List.map (fun x -> (field, "-" ^ x)) (S.elements (S.diff a b))
  @ List.map (fun x -> (field, "+" ^ x)) (S.elements (S.diff b a))

let () =
  let pkg = Sys.argv.(1) and py = load Sys.argv.(2) and ml = load Sys.argv.(3) in
  let expected =
    In_channel.with_open_text Sys.argv.(4) In_channel.input_lines
    |> List.filter_map (fun l ->
           let l = match String.index_opt l '#' with Some i -> String.sub l 0 i | None -> l in
           match String.split_on_char ' ' l |> List.filter (( <> ) "") with
           | [ p; ("roots" | "kind") as f; item ] when p = pkg -> Some (f, item)
           | [] -> None
           | _ -> None)
  in
  let node (n : Graph.node) = n.id in
  let sized (n : Graph.node) = Printf.sprintf "%s=%d" n.id n.self in
  let kinded (n : Graph.node) = Printf.sprintf "%s=%s" n.id (Graph.string_of_kind n.kind) in
  let diffs =
    (if py.project <> ml.project then [ ("project", "-" ^ py.project); ("project", "+" ^ ml.project) ] else [])
    @ set_diff "roots" Fun.id py.roots ml.roots
    @ set_diff "nodes" node py.nodes ml.nodes
    @ set_diff "edges" (fun (a, b) -> a ^ "->" ^ b) py.edges ml.edges
    @ set_diff "self" sized py.nodes ml.nodes
    @ set_diff "kind" kinded py.nodes ml.nodes
  in
  let unexpected = List.filter (fun d -> not (List.mem d expected)) diffs in
  List.iter
    (fun ((f, i) as d) ->
      Printf.printf "%s %s %s%s\n" pkg f i (if List.mem d expected then "  (expected)" else ""))
    diffs;
  let missing = List.filter (fun d -> not (List.mem d diffs)) expected in
  List.iter (fun (f, i) -> Printf.printf "%s %s %s  (expected but absent)\n" pkg f i) missing;
  exit (if unexpected = [] && missing = [] then 0 else 1)
