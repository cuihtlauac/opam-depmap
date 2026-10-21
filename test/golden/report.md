# demo — dependency & footprint report

**7** nodes (2 own · 5 external), **5** edges, **2** roots · total footprint **3.5 MiB**.

Distribution (sized nodes, n=5): median 512 KiB · p90 1.9 MiB · p95 1.9 MiB · p99 1.9 MiB · Gini 0.546 · top-5 = 100% of bytes.

## Top 15 by own footprint
| library | own bytes | kind |
|---|---|---|
| tool | 1.9 MiB | external |
| base | 1.0 MiB | external |
| stdlib | 512 KiB | external |
| fmt | 64 KiB | external |
| demo | 4 KiB | own |
| demo.extra | 0 B | own |
| iso | 0 B | external |

## Top 15 by transitive footprint (self + everything it pulls in)
| library | transitive | own |
|---|---|---|
| tool | 1.9 MiB | 1.9 MiB |
| demo | 1.6 MiB | 4 KiB |
| base | 1.5 MiB | 1.0 MiB |
| demo.extra | 576 KiB | 0 B |
| fmt | 576 KiB | 64 KiB |
| stdlib | 512 KiB | 512 KiB |
| iso | 0 B | 0 B |

## Top 15 most depended-upon (fan-in)
| library | consumers |
|---|---|
| fmt | 2 |
| stdlib | 2 |
| base | 1 |
| demo | 0 |
| demo.extra | 0 |
| iso | 0 |
| tool | 0 |

## Longest dependency chain (depth 2)
demo → base → stdlib
