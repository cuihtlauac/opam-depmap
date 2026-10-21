let replace_all ~sub ~by s =
  let n = String.length sub and b = Buffer.create (String.length s) in
  let rec go i =
    if i > String.length s - n then Buffer.add_string b (String.sub s i (String.length s - i))
    else if String.sub s i n = sub then (Buffer.add_string b by; go (i + n))
    else (Buffer.add_char b s.[i]; go (i + 1))
  in
  go 0;
  Buffer.contents b

(* Index of [sub] in [s] at or after [from], if any. *)
let find_from ~sub s from =
  let n = String.length sub and len = String.length s in
  let rec go i = if i > len - n then None else if String.sub s i n = sub then Some i else go (i + 1) in
  go from

(* A data-supplied subtitle overrides the default header prose (whole-switch
   mode). Replace the body of the first
   [<div class="sub">...</div>] with the subtitle. Absent -> untouched, so
   single-package output stays byte-identical. *)
let with_subtitle s = function
  | None -> s
  | Some sub ->
      let op = "<div class=\"sub\">" and cl = "</div>" in
      match find_from ~sub:op s 0 with
      | None -> s
      | Some i -> (
          let start = i + String.length op in
          match find_from ~sub:cl s start with
          | None -> s
          | Some j -> String.sub s 0 start ^ sub ^ String.sub s j (String.length s - j))

(* Same order as the original generator: the data goes in first, so a project
   name inside it is rewritten too. The subtitle swap runs last (after the
   [Dream] rename). *)
let html (g : Graph.t) =
  Template.html
  |> replace_all ~sub:"__DATA__" ~by:(Graph.to_string ~minify:true g)
  |> replace_all ~sub:"Dream" ~by:g.project
  |> fun s -> with_subtitle s g.subtitle
