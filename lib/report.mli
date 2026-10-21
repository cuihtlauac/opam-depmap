(** Model-oriented report of a collected {!Graph.t}.

    Sibling of {!Render}: same graph in, a different rendering out. Where
    {!Render} encodes magnitudes visually (treemap area, colour, position),
    this persists the quantities those channels stand for as explicit numbers --
    [depth], [transitive] footprint, [fan_in]/[fan_out], the size distribution --
    the metrics a model needs and cannot reliably recompute over a large graph.
    Byte-stable: the JSON and digest formats are pinned by test/golden. *)

val render : ?top:int -> md:bool -> Graph.t -> string
(** [render ~md g] is the enriched JSON report (every node's metrics plus the
    adjacency), or the compact Markdown digest (summary, top-N tables, roots,
    longest chain) when [md]. [top] (default 15) bounds each ranked list. *)
