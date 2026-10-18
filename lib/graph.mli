(** The dependency map: findlib libraries, their requires edges and sizes.

    Serialised as [data.json]:
    [{project, roots, nodes:[{id, kind: own|external, self}], edges:[[a,b]]}]. *)

type kind = Own | External

type node = { id : string; kind : kind; self : int (** compiled-artifact bytes *) }

type t = {
  project : string;
  roots : string list;  (** entry libraries no other library requires *)
  nodes : node list;  (** sorted by [id] *)
  edges : (string * string) list;  (** [(a, b)]: [a] requires [b]; sorted, unique *)
}

val make :
  project:string -> roots:string list -> nodes:node list ->
  edges:(string * string) list -> t
(** Sorts nodes and edges and removes duplicate edges. *)

val to_string : ?minify:bool -> t -> string
(** Pretty-printed with a one-space indent (Python's [json.dumps(indent=1)]),
    or with no whitespace at all when [minify] (Python's
    [separators=(",", ":")]). *)

val of_string : string -> (t, string) result

val string_of_kind : kind -> string
