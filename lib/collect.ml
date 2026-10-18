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

let of_switch ?switch o =
  Switch.with_switch ?switch @@ fun sw ->
  if not (Switch.installed sw o.package) then
    Error (Printf.sprintf "opam package %S is not installed in switch %s" o.package (Switch.name sw))
  else begin
    Libs.init ~lib_dir:(Switch.lib_dir sw);
    let dir l =
      match Libs.dir l with
      | Some d when Sys.file_exists d && Sys.is_directory d -> Some (Unix.realpath d)
      | _ -> None
    in
    (* A library belongs to whoever installed its META file; failing that,
       its directory. *)
    let owner l =
      match Option.bind (Libs.meta l) (Switch.owner sw) with
      | Some p -> Some p
      | None -> Option.bind (Libs.dir l) (Switch.owner sw)
    in
    let src =
      { libs = Libs.all (); exists = Libs.exists; requires = Libs.requires; dir;
        bytes = artifact_bytes; owner }
    in
    run src ~same_repo:(Switch.same_repo sw o.package) o
  end
