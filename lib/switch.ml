open OpamStateTypes

type t = {
  st : unlocked switch_state;
  prefix : string;  (** realpath of the switch prefix *)
  files : (string, string) Hashtbl.t Lazy.t;  (** prefix-relative path -> package *)
}

let init () =
  OpamFormatConfig.init ();
  let root = OpamStateConfig.opamroot () in
  ignore (OpamStateConfig.load_defaults ~lock_kind:`Lock_read root);
  OpamCoreConfig.init ();
  OpamRepositoryConfig.init ();
  OpamStateConfig.init ~root_dir:root ()

let realpath p = try Unix.realpath p with Unix.Unix_error _ -> p

let index st =
  let tbl = Hashtbl.create 50_000 in
  OpamPackage.Set.iter
    (fun nv ->
      let name = OpamPackage.name nv in
      let changes = OpamPath.Switch.changes st.switch_global.root st.switch name in
      match OpamFile.Changes.read_opt changes with
      | None -> ()
      | Some ch ->
          OpamStd.String.Map.iter
            (fun path -> function
              | OpamDirTrack.Added _ | Kind_changed _ ->
                  Hashtbl.replace tbl path (OpamPackage.Name.to_string name)
              | Removed | Contents_changed _ | Perm_changed _ -> ())
            ch)
    st.installed;
  tbl

let with_switch ?switch f =
  let switch = Option.map OpamSwitch.of_string switch in
  OpamGlobalState.with_ `Lock_none @@ fun gt ->
  OpamSwitchState.with_ `Lock_none ?switch gt @@ fun st ->
  let prefix = realpath (OpamFilename.Dir.to_string (OpamPath.Switch.root gt.root st.switch)) in
  f { st = (st :> unlocked switch_state); prefix; files = lazy (index st) }

let name t = OpamSwitch.to_string t.st.switch

let lib_dir t =
  OpamFilename.Dir.to_string
    (OpamPath.Switch.lib_dir t.st.switch_global.root t.st.switch t.st.switch_config)

let find_installed t pkg =
  match OpamPackage.Name.of_string pkg with
  | name -> (
      try Some (OpamPackage.package_of_name t.st.installed name) with Not_found -> None)
  | exception _ -> None

let installed t pkg = Option.is_some (find_installed t pkg)

let dev_repo t nv =
  Option.map OpamUrl.to_string (OpamFile.OPAM.dev_repo (OpamSwitchState.opam t.st nv))

let same_repo t pkg =
  match find_installed t pkg with
  | None -> [ pkg ]
  | Some nv -> (
      match dev_repo t nv with
      | None -> [ pkg ]
      | Some repo ->
          OpamPackage.Set.fold
            (fun nv acc ->
              if dev_repo t nv = Some repo then
                OpamPackage.Name.to_string (OpamPackage.name nv) :: acc
              else acc)
            t.st.installed []
          |> List.sort String.compare)

let owner t path =
  let files = Lazy.force t.files in
  let path = realpath path and pre = t.prefix ^ "/" in
  let n = String.length pre in
  if String.length path <= n || String.sub path 0 n <> pre then None
  else
    (* Stop below top-level dirs like [lib]: they hold every package. *)
    let rec up rel =
      if not (String.contains rel '/') then None
      else
        match Hashtbl.find_opt files rel with
        | Some p -> Some p
        | None -> up (Filename.dirname rel)
    in
    up (String.sub path n (String.length path - n))

(* Each manifest entry is [ "<path>" {"<desc>"} ]; a file's desc is
   [F:S<bytes>T<mtime>]; we sum the recorded S sizes under bin/, sbin/, stublibs/. *)
let entry_re = Str.regexp "\"\\([^\"]+\\)\"[ \t\r\n]*{\"\\([^\"}]*\\)\"}"
let fsize_re = Str.regexp "F:S\\([0-9]+\\)"

let read_file f = try In_channel.with_open_bin f In_channel.input_all with Sys_error _ -> ""

let library_less t =
  let install = Filename.concat t.prefix ".opam-switch/install" in
  let top_of path = match String.index_opt path '/' with Some i -> String.sub path 0 i | None -> path in
  let is_meta path =
    String.length path > 4 && String.sub path 0 4 = "lib/" && Filename.check_suffix path "/META"
  in
  let scan fname =
    let pkg = Filename.chop_suffix fname ".changes" in
    let text = read_file (Filename.concat install fname) in
    let has_meta = ref false and size = ref 0 and pos = ref 0 in
    (try
       while true do
         let i = Str.search_forward entry_re text !pos in
         pos := i + String.length (Str.matched_string text);
         let path = Str.matched_group 1 text and desc = Str.matched_group 2 text in
         if is_meta path then has_meta := true;
         if (match top_of path with "bin" | "sbin" | "stublibs" -> true | _ -> false)
            && Str.string_match fsize_re desc 0
         then size := !size + int_of_string (Str.matched_group 1 desc)
       done
     with Not_found -> ());
    if !has_meta then None else Some (pkg, !size)
  in
  (try Sys.readdir install |> Array.to_list with Sys_error _ -> [])
  |> List.filter (fun f -> Filename.check_suffix f ".changes")
  |> List.sort String.compare
  |> List.filter_map scan
