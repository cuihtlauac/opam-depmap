(* opam-depmap: dependency map of an installed opam package.
   Also runs as an opam plugin: `opam depmap <pkg>`. *)

open Cmdliner
open Opam_depmap

let read_file f = In_channel.with_open_bin f In_channel.input_all

(* Write only when the content changed, so unchanged outputs keep their mtime. *)
let write_file f s =
  if not (Sys.file_exists f && read_file f = s) then
    Out_channel.with_open_bin f (fun oc -> output_string oc s)

let summary out (g : Graph.t) =
  Printf.printf "%s: nodes=%d edges=%d  ->  %s\n" g.project (List.length g.nodes)
    (List.length g.edges) out;
  List.stable_sort (fun (a : Graph.node) b -> compare b.self a.self) g.nodes
  |> List.iteri (fun i (n : Graph.node) ->
         if i < 10 then
           Printf.printf "  %6d KiB  %-8s %s\n" (n.self / 1024) (Graph.string_of_kind n.kind) n.id)

let render_to out g =
  let html = Render.html g in
  write_file out html;
  Printf.printf "wrote %s  (%d bytes)\n" out (String.length html)

let collect ~switch opts =
  Switch.init ();
  match Collect.of_switch ?switch opts with
  | Ok g -> Ok g
  | Error e -> Error e
  | exception OpamStd.Sys.Exit n -> Error (Printf.sprintf "opam failed (exit %d)" n)

let collect_all ~switch ~name =
  Switch.init ();
  match Collect.of_switch_all ?switch ?name () with
  | Ok g -> Ok g
  | Error e -> Error e
  | exception OpamStd.Sys.Exit n -> Error (Printf.sprintf "opam failed (exit %d)" n)

(* --- arguments ------------------------------------------------------------ *)

let package =
  Arg.(required & pos 0 (some string) None & info [] ~docv:"PACKAGE" ~doc:"Installed opam package to analyse.")

let opts =
  let name_t =
    Arg.(value & opt (some string) None & info [ "name" ] ~docv:"NAME" ~doc:"Display name (default: $(i,PACKAGE)).")
  in
  let entries =
    Arg.(value & opt_all string [] & info [ "entry" ] ~docv:"LIB"
           ~doc:"Findlib library to root the graph at (repeatable). Default: every library $(i,PACKAGE) installs.")
  in
  let own =
    Arg.(value & opt_all string [] & info [ "own" ] ~docv:"PKG"
           ~doc:"Opam package whose libraries count as the project's own (repeatable). \
                 Default: the installed packages sharing $(i,PACKAGE)'s dev-repo.")
  in
  Term.(const (fun package name entries own -> Collect.options ?name ~entries ~own package)
        $ package $ name_t $ entries $ own)

let switch =
  Arg.(value & opt (some string) None & info [ "switch" ] ~docv:"SWITCH" ~env:(Cmd.Env.info "OPAMSWITCH")
         ~doc:"Opam switch to read (default: the current one).")

let output default =
  Arg.(value & opt string default & info [ "o"; "output" ] ~docv:"FILE" ~doc:"Output file.")

let handle = function Ok () -> Ok () | Error e -> Error (`Msg e)

(* --- commands ------------------------------------------------------------- *)

let collect_cmd =
  let run switch opts out =
    handle
      (Result.map
         (fun g -> write_file out (Graph.to_string g); summary out g)
         (collect ~switch opts))
  in
  Cmd.v (Cmd.info "collect" ~doc:"Collect the dependency graph and sizes into a JSON file.")
    Term.(term_result (const run $ switch $ opts $ output "data.json"))

let render_cmd =
  let data =
    Arg.(value & pos 0 file "data.json" & info [] ~docv:"DATA" ~doc:"JSON file written by $(b,collect).")
  in
  let run data out =
    handle (Result.map (render_to out) (Graph.of_string (read_file data)))
  in
  Cmd.v (Cmd.info "render" ~doc:"Render a JSON file into a self-contained HTML page (no opam needed).")
    Term.(term_result (const run $ data $ output "squarified_treemap.html"))

let map_cmd =
  let data =
    Arg.(value & opt (some string) None & info [ "data" ] ~docv:"FILE" ~doc:"Also write the collected JSON to $(docv).")
  in
  let run switch opts data out =
    handle
      (Result.map
         (fun g ->
           Option.iter (fun f -> write_file f (Graph.to_string g); summary f g) data;
           render_to out g)
         (collect ~switch opts))
  in
  Cmd.v (Cmd.info "map" ~doc:"Collect and render in one go (the default command).")
    Term.(term_result (const run $ switch $ opts $ data $ output "squarified_treemap.html"))

let switch_cmd =
  let name_t =
    Arg.(value & opt (some string) None & info [ "name" ] ~docv:"NAME" ~doc:"Display name (default: the switch name).")
  in
  let data =
    Arg.(value & opt (some string) None & info [ "data" ] ~docv:"FILE" ~doc:"Also write the collected JSON to $(docv).")
  in
  let run switch name data out =
    handle
      (Result.map
         (fun g ->
           Option.iter (fun f -> write_file f (Graph.to_string g); summary f g) data;
           render_to out g)
         (collect_all ~switch ~name))
  in
  Cmd.v (Cmd.info "switch" ~doc:"Map the whole current switch (every library + library-less packages).")
    Term.(term_result (const run $ switch $ name_t $ data $ output "squarified_treemap.html"))

let report_cmd =
  let data =
    Arg.(value & pos 0 file "data.json" & info [] ~docv:"DATA" ~doc:"JSON file written by $(b,collect).")
  in
  let top =
    Arg.(value & opt int 15 & info [ "top" ] ~docv:"N" ~doc:"Entries per ranked list / digest table.")
  in
  let run data top out =
    let md = Filename.check_suffix out ".md" in
    handle
      (Result.map
         (fun g ->
           let s = Report.render ~top ~md g in
           write_file out s;
           Printf.printf "%s: %d nodes  ->  %s\n" (g : Graph.t).project (List.length g.nodes) out)
         (Graph.of_string (read_file data)))
  in
  Cmd.v
    (Cmd.info "report"
       ~doc:"Render a JSON file into a model-oriented report: enriched JSON, or a Markdown digest when $(b,-o) ends in .md.")
    Term.(term_result (const run $ data $ top $ output "report.json"))

let cmd =
  let doc = "dependency map and binary footprint of an installed opam package" in
  let man =
    [ `S Manpage.s_description;
      `P "Follows the findlib $(i,requires) of every library $(i,PACKAGE) installs, sizes each \
          library by its compiled artifacts, and renders a self-contained interactive HTML page. \
          $(b,opam-depmap) $(i,PACKAGE) is short for $(b,opam-depmap map) $(i,PACKAGE). \
          Installed as an opam plugin, it also runs as $(b,opam depmap)." ]
  in
  Cmd.group (Cmd.info "opam-depmap" ~doc ~man) [ map_cmd; collect_cmd; render_cmd; switch_cmd; report_cmd ]

(* `opam-depmap PKG ...` means `opam-depmap map PKG ...`. *)
let argv =
  let a = Sys.argv in
  if Array.length a > 1 && a.(1) <> "" && a.(1).[0] <> '-'
     && not (List.mem a.(1) [ "map"; "collect"; "render"; "switch"; "report"; "help" ])
  then Array.concat [ [| a.(0); "map" |]; Array.sub a 1 (Array.length a - 1) ]
  else a

let () = exit (Cmd.eval ~argv cmd)
