let init ~lib_dir =
  let conf = Filename.concat lib_dir "findlib.conf" in
  if Sys.file_exists conf then Findlib.init ~config:conf () else Findlib.init ()

let all () = List.sort_uniq String.compare (Fl_package_base.list_packages ())

let query name =
  match Fl_package_base.query name with
  | p -> Some p
  | exception Fl_package_base.No_such_package _ -> None

let exists name = Option.is_some (query name)

let is_ws = function ' ' | '\t' | '\n' | '\r' | '\012' -> true | _ -> false

let split_ws s =
  let b = Buffer.create 16 and out = ref [] in
  let flush () = if Buffer.length b > 0 then (out := Buffer.contents b :: !out; Buffer.clear b) in
  String.iter (fun c -> if is_ws c then flush () else Buffer.add_char b c) s;
  flush ();
  List.rev !out

(* The raw META [requires] value under no predicates, split on whitespace --
   exactly what [ocamlfind query -format "%(requires)"] reports. We read the
   property directly rather than via [Fl_package_base.requires], which resolves
   each name against installed packages and raises when one is missing (so a
   library requiring an uninstalled one would otherwise lose ALL its edges). *)
let requires name =
  match Findlib.package_property [] name "requires" with
  | s -> split_ws s
  | exception Not_found -> []
  | exception Fl_package_base.No_such_package _ -> []

let dir name =
  match Findlib.package_directory name with
  | d -> Some d
  | exception Fl_package_base.No_such_package _ -> None

let meta name = Option.map (fun p -> p.Fl_package_base.package_meta) (query name)
