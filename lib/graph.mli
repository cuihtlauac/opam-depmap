(** The dependency map: findlib libraries, their requires edges and sizes.

    Serialised as [data.json]:
    [{project, roots, nodes:[{id, kind: own|external, self}], edges:[[a,b]]}],
    plus an optional trailing [subtitle] (whole-switch mode supplies it). *)

type kind = Own | External

type node = { id : string; kind : kind; self : int (** compiled-artifact bytes *) }

type t = {
  project : string;
  roots : string list;  (** entry libraries no other library requires *)
  nodes : node list;  (** sorted by [id] *)
  edges : (string * string) list;  (** [(a, b)]: [a] requires [b]; sorted, unique *)
  subtitle : string option;  (** header prose override; emitted last when present *)
}

val make :
  project:string -> roots:string list -> nodes:node list ->
  edges:(string * string) list -> t
(** Sorts nodes and edges and removes duplicate edges. [subtitle] is [None];
    set it with a record update ([{ (make ...) with subtitle = Some s }]). *)

val to_string : ?minify:bool -> t -> string
(** Pretty-printed with a one-space indent, or with no whitespace at all when
    [minify]. *)

val of_string : string -> (t, string) result

val string_of_kind : kind -> string

(** A minimal JSON value and emitter: one-space indent, or no whitespace when
    [minify]. [Raw] emits its string verbatim, for pre-formatted numbers.
    Shared with {!Report}. *)
type json = Str of string | Int of int | Raw of string | Arr of json list | Obj of (string * json) list

val json_to_string : ?minify:bool -> json -> string
