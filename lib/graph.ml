type kind = Own | External

type node = { id : string; kind : kind; self : int }

type t = {
  project : string;
  roots : string list;
  nodes : node list;
  edges : (string * string) list;
  subtitle : string option;
}

let make ~project ~roots ~nodes ~edges =
  let nodes = List.sort (fun a b -> String.compare a.id b.id) nodes in
  { project; roots; nodes; edges = List.sort_uniq compare edges; subtitle = None }

let string_of_kind = function Own -> "own" | External -> "external"

(* --- printing: the canonical data.json JSON (one-space indent, or minified) - *)

type json = Str of string | Int of int | Raw of string | Arr of json list | Obj of (string * json) list

let to_json g =
  let fields =
    [ ("project", Str g.project);
      ("roots", Arr (List.map (fun r -> Str r) g.roots));
      ( "nodes",
        Arr
          (List.map
             (fun n ->
               Obj
                 [ ("id", Str n.id);
                   ("kind", Str (string_of_kind n.kind));
                   ("self", Int n.self) ])
             g.nodes) );
      ("edges", Arr (List.map (fun (a, b) -> Arr [ Str a; Str b ]) g.edges)) ]
  in
  (* subtitle is emitted last (after edges), only when present. *)
  Obj (match g.subtitle with None -> fields | Some s -> fields @ [ ("subtitle", Str s) ])

(* ensure_ascii-style: escape controls and non-ASCII bytes as \uXXXX. Library
   names are ASCII; non-ASCII bytes (if any) are escaped one by one. *)
let quote b s =
  Buffer.add_char b '"';
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | '\b' -> Buffer.add_string b "\\b"
      | '\012' -> Buffer.add_string b "\\f"
      | c when c < ' ' || c > '~' -> Printf.bprintf b "\\u%04x" (Char.code c)
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"'

let json_to_string ?(minify = false) j =
  let b = Buffer.create 4096 in
  let rec go indent = function
    | Str s -> quote b s
    | Int i -> Buffer.add_string b (string_of_int i)
    | Raw s -> Buffer.add_string b s
    | Arr [] -> Buffer.add_string b "[]"
    | Obj [] -> Buffer.add_string b "{}"
    | Arr l -> seq indent '[' ']' (fun i v -> go i v) l
    | Obj l ->
        seq indent '{' '}'
          (fun i (k, v) ->
            quote b k;
            Buffer.add_string b (if minify then ":" else ": ");
            go i v)
          l
  and seq : 'a. int -> char -> char -> (int -> 'a -> unit) -> 'a list -> unit =
   fun indent op cl item l ->
    let inner = indent + 1 in
    let nl i = if not minify then (Buffer.add_char b '\n'; Buffer.add_string b (String.make i ' ')) in
    Buffer.add_char b op;
    List.iteri
      (fun k v ->
        if k > 0 then Buffer.add_char b ',';
        nl inner;
        item inner v)
      l;
    nl indent;
    Buffer.add_char b cl
  in
  go 0 j;
  Buffer.contents b

let to_string ?minify g = json_to_string ?minify (to_json g)

(* --- parsing ---------------------------------------------------------------- *)

let of_string s =
  let ( let* ) = Result.bind in
  let str = function `String s -> Ok s | _ -> Error "expected a string" in
  let int = function
    | `Float f when Float.is_integer f -> Ok (int_of_float f)
    | _ -> Error "expected an integer"
  in
  let list f = function
    | `A l ->
        List.fold_right
          (fun x acc ->
            let* acc = acc in
            let* x = f x in
            Ok (x :: acc))
          l (Ok [])
    | _ -> Error "expected an array"
  in
  let field o k =
    match List.assoc_opt k o with
    | Some v -> Ok v
    | None -> Error (Printf.sprintf "missing field %S" k)
  in
  let node = function
    | `O o ->
        let* id = Result.bind (field o "id") str in
        let* kind = Result.bind (field o "kind") str in
        let* kind =
          match kind with
          | "own" -> Ok Own
          | "external" -> Ok External
          | k -> Error (Printf.sprintf "unknown kind %S" k)
        in
        let* self = Result.bind (field o "self") int in
        Ok { id; kind; self }
    | _ -> Error "expected a node object"
  in
  let edge = function
    | `A [ a; b ] ->
        let* a = str a in
        let* b = str b in
        Ok (a, b)
    | _ -> Error "expected an edge [a, b]"
  in
  match OpamJson.of_string s with
  | Some (`O o) ->
      let* project = Result.bind (field o "project") str in
      let* roots = Result.bind (field o "roots") (list str) in
      let* nodes = Result.bind (field o "nodes") (list node) in
      let* edges = Result.bind (field o "edges") (list edge) in
      let* subtitle =
        match List.assoc_opt "subtitle" o with
        | None -> Ok None
        | Some v -> Result.map Option.some (str v)
      in
      Ok { project; roots; nodes; edges; subtitle }
  | Some _ -> Error "expected a JSON object"
  | None -> Error "invalid JSON"
