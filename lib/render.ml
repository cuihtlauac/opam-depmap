let replace_all ~sub ~by s =
  let n = String.length sub and b = Buffer.create (String.length s) in
  let rec go i =
    if i > String.length s - n then Buffer.add_string b (String.sub s i (String.length s - i))
    else if String.sub s i n = sub then (Buffer.add_string b by; go (i + n))
    else (Buffer.add_char b s.[i]; go (i + 1))
  in
  go 0;
  Buffer.contents b

(* Same order as the original generator: the data goes in first, so a project
   name inside it is rewritten too. *)
let html (g : Graph.t) =
  Template.html
  |> replace_all ~sub:"__DATA__" ~by:(Graph.to_string ~minify:true g)
  |> replace_all ~sub:"Dream" ~by:g.project
