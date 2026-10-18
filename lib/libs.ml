let init ~lib_dir =
  let conf = Filename.concat lib_dir "findlib.conf" in
  if Sys.file_exists conf then Findlib.init ~config:conf () else Findlib.init ()

let all () = List.sort_uniq String.compare (Fl_package_base.list_packages ())

let query name =
  match Fl_package_base.query name with
  | p -> Some p
  | exception Fl_package_base.No_such_package _ -> None

let exists name = Option.is_some (query name)

let requires name =
  match Fl_package_base.requires ~preds:[] name with
  | l -> l
  | exception Fl_package_base.No_such_package _ -> []

let dir name =
  match Findlib.package_directory name with
  | d -> Some d
  | exception Fl_package_base.No_such_package _ -> None

let meta name = Option.map (fun p -> p.Fl_package_base.package_meta) (query name)
