(** The findlib side: library names, requires, install dirs. *)

val init : lib_dir:string -> unit
(** Initialise findlib from [<lib_dir>/findlib.conf] when it exists (the
    switch's own configuration), so another switch can be queried without
    [opam exec]; otherwise from the default configuration. *)

val all : unit -> string list
(** Every findlib library, sub-libraries included, sorted. *)

val exists : string -> bool

val requires : string -> string list
(** Direct requirements under no predicates, as
    [ocamlfind query -format %(requires)] reports them. *)

val dir : string -> string option
(** The library's install directory. *)

val meta : string -> string option
(** The META file defining the library (the parent's, for a sub-library). *)
