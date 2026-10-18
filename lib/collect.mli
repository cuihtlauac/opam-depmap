(** Build the dependency map of an installed opam package. *)

type source = {
  libs : string list;  (** every findlib library in the switch *)
  exists : string -> bool;
  requires : string -> string list;  (** direct findlib requires *)
  dir : string -> string option;  (** canonical install dir, if it exists *)
  bytes : string -> int;  (** compiled-artifact bytes at the top level of a dir *)
  owner : string -> string option;  (** opam package that installed a library *)
}
(** Everything the algorithm needs from the switch, so it can run on a fake. *)

type options = {
  package : string;  (** opam package to analyse *)
  name : string option;  (** display name; defaults to [package] *)
  entries : string list;  (** libraries to root the graph at; [[]]: all of [package]'s *)
  own : string list;  (** opam packages whose libraries are own; [[]]: [same_repo] *)
}

val options : ?name:string -> ?entries:string list -> ?own:string list -> string -> options

val run : source -> same_repo:string list -> options -> (Graph.t, string) result
(** [same_repo] is the default own set: the packages sharing [package]'s dev-repo.

    The graph is the findlib [requires] closure of the entry libraries. A
    library is {!Graph.Own} when an own package installed it. Its size is the
    artifact bytes of its install dir; libraries sharing a dir give it all to
    the shortest name (ties: the first in alphabetical order). *)

val artifact_bytes : string -> int
(** Sum of the [.a .cmxa .cmxs .cma .cmi .cmx] files at the top level of a
    directory (sub-libraries live in subdirs). *)

val of_switch : ?switch:string -> options -> (Graph.t, string) result
(** {!run} on the given (default: current) opam switch. Requires {!Switch.init}. *)
