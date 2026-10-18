(** Emit the self-contained HTML page. *)

val html : Graph.t -> string
(** The embedded template with [__DATA__] replaced by the minified graph and
    every [Dream] by the project name. *)
