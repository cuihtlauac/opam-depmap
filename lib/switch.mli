(** The opam side: the switch's installed packages, their source repos, and
    which package installed which file. *)

type t

val init : unit -> unit
(** Initialise opam's configuration from the opam root and the environment
    ([OPAMROOT], [OPAMSWITCH], ...). Call once, before {!with_switch}. *)

val with_switch : ?switch:string -> (t -> 'a) -> 'a
(** Load the switch (the current one by default) read-only. *)

val name : t -> string
val lib_dir : t -> string

val installed : t -> string -> bool

val same_repo : t -> string -> string list
(** The installed packages built from the same [dev-repo] as the given one
    (itself included), or just itself when it declares none. Sorted. *)

val owner : t -> string -> string option
(** [owner t path] is the opam package that installed [path] (a file or a
    directory), according to the switch's [.changes] records. A directory not
    recorded itself belongs to its nearest recorded ancestor. *)
