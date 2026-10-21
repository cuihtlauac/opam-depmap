type source = {
  libs : string list;
  exists : string -> bool;
  requires : string -> string list;
  dir : string -> string option;
  bytes : string -> int;
  owner : string -> string option;
}

type options = { package : string; name : string option; entries : string list; own : string list }

let options ?name ?(entries = []) ?(own = []) package = { package; name; entries; own }

module S = Set.Make (String)

let closure src entries =
  let rec go nodes edges = function
    | [] -> (nodes, edges)
    | lib :: rest when S.mem lib nodes -> go nodes edges rest
    | lib :: rest ->
        let deps = src.requires lib in
        go (S.add lib nodes) (List.map (fun d -> (lib, d)) deps @ edges) (deps @ rest)
  in
  go S.empty [] entries

(* Libraries sharing an install dir: the shortest name gets the dir's bytes. *)
let sizes src nodes =
  let by_dir = Hashtbl.create 64 in
  S.iter
    (fun n -> Option.iter (fun d -> Hashtbl.replace by_dir d (n :: Option.value ~default:[] (Hashtbl.find_opt by_dir d))) (src.dir n))
    nodes;
  let size = Hashtbl.create 64 in
  Hashtbl.iter
    (fun d libs ->
      let shorter a b =
        let c = compare (String.length a) (String.length b) in
        if c <> 0 then c else String.compare a b
      in
      match List.sort shorter libs with
      | owner :: rest ->
          Hashtbl.replace size owner (src.bytes d);
          List.iter (fun l -> Hashtbl.replace size l 0) rest
      | [] -> ())
    by_dir;
  fun n -> Option.value ~default:0 (Hashtbl.find_opt size n)

let run src ~same_repo o =
  let entries =
    match o.entries with
    | [] -> List.filter (fun l -> src.owner l = Some o.package) src.libs
    | l -> l
  in
  match (entries, List.filter (fun l -> not (src.exists l)) entries) with
  | [], _ ->
      Error
        (Printf.sprintf "no findlib library found for %S -- pass --entry with the libraries to map"
           o.package)
  | _, missing :: _ -> Error (Printf.sprintf "findlib library %S not found" missing)
  | entries, [] ->
      let own = S.of_list (match o.own with [] -> same_repo | l -> l) in
      let nodes, edges = closure src entries in
      let size = sizes src nodes in
      let kind n =
        match src.owner n with Some p when S.mem p own -> Graph.Own | _ -> Graph.External
      in
      let required = S.of_list (List.map snd edges) in
      Ok
        (Graph.make
           ~project:(Option.value ~default:o.package o.name)
           ~roots:(List.filter (fun r -> not (S.mem r required)) (List.sort_uniq String.compare entries))
           ~nodes:(List.map (fun id -> { Graph.id; kind = kind id; self = size id }) (S.elements nodes))
           ~edges)

let exts = [ ".a"; ".cmxa"; ".cmxs"; ".cma"; ".cmi"; ".cmx" ]

let artifact_bytes dir =
  Array.fold_left
    (fun acc f ->
      if List.exists (Filename.check_suffix f) exts then
        match Unix.stat (Filename.concat dir f) with
        | { st_kind = S_REG; st_size; _ } -> acc + st_size
        | _ | (exception Unix.Unix_error _) -> acc
      else acc)
    0
    (try Sys.readdir dir with Sys_error _ -> [||])

(* The install dir, realpath'd, only if it is an existing directory. *)
let real_dir l =
  match Libs.dir l with
  | Some d when Sys.file_exists d && Sys.is_directory d -> Some (Unix.realpath d)
  | _ -> None

let of_switch ?switch o =
  Switch.with_switch ?switch @@ fun sw ->
  if not (Switch.installed sw o.package) then
    Error (Printf.sprintf "opam package %S is not installed in switch %s" o.package (Switch.name sw))
  else begin
    Libs.init ~lib_dir:(Switch.lib_dir sw);
    (* A library belongs to whoever installed its META file; failing that,
       its directory. *)
    let owner l =
      match Option.bind (Libs.meta l) (Switch.owner sw) with
      | Some p -> Some p
      | None -> Option.bind (Libs.dir l) (Switch.owner sw)
    in
    let src =
      { libs = Libs.all (); exists = Libs.exists; requires = Libs.requires; dir = real_dir;
        bytes = artifact_bytes; owner }
    in
    run src ~same_repo:(Switch.same_repo sw o.package) o
  end

(* Header prose for whole-switch mode (swapped into the page's subtitle). *)
let switch_subtitle name =
  Printf.sprintf
    "The whole <b>%s</b> switch. Rectangles are every compiled library's binary \
     footprint, area &prop; own bytes, coloured by depth; <b>dots</b> are root \
     libraries (nothing else in the switch requires them). Library-less packages \
     (tools, conf-*, compilers) appear as isolated blocks sized by their binary \
     footprint. <b>Hover</b> to trace a library's binary and everything it pulls in."
    name

let of_switch_all ?switch ?name () =
  Switch.with_switch ?switch @@ fun sw ->
  Libs.init ~lib_dir:(Switch.lib_dir sw);
  let name = Option.value ~default:(Switch.name sw) name in
  match Libs.all () with
  | [] -> Error "no findlib libraries found in this switch"
  | libs ->
      let libset = S.of_list libs in
      (* Edges: each library's requires, kept only when both ends are libraries. *)
      let edges =
        List.concat_map
          (fun n -> List.filter_map (fun d -> if S.mem d libset then Some (n, d) else None) (Libs.requires n))
          libs
      in
      (* Library sizes: the shared install-dir dedup (shortest name wins). *)
      let src =
        { libs; exists = Libs.exists; requires = Libs.requires; dir = real_dir;
          bytes = artifact_bytes; owner = (fun _ -> None) }
      in
      let lib_size = sizes src libset in
      (* Roots = libraries nothing requires; they (and only they) are the own layer. *)
      let required = S.of_list (List.map snd edges) in
      let roots = List.filter (fun l -> not (S.mem l required)) libs in
      let root_set = S.of_list roots in
      let lib_nodes =
        List.map
          (fun id ->
            { Graph.id; kind = (if S.mem id root_set then Graph.Own else Graph.External); self = lib_size id })
          libs
      in
      (* Library-less packages: isolated, edge-less, never own. *)
      let libless_nodes =
        List.map (fun (id, bytes) -> { Graph.id; kind = Graph.External; self = bytes }) (Switch.library_less sw)
      in
      Ok
        { (Graph.make ~project:name ~roots ~nodes:(lib_nodes @ libless_nodes) ~edges) with
          subtitle = Some (switch_subtitle name) }
