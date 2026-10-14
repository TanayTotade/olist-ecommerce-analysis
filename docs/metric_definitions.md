# Original metric definitions

This describes the submitted queries as retained. Differences are documented, not corrected.

| Area | Original definition / caveat |
| --- | --- |
| Sales baseline and regional/product supporting analysis | Generally item price only (`SUM(price)`); some queries restrict order statuses |
| Final dashboard sales/KPIs | Item price plus freight; all order statuses; AOV excludes orders without item value |
| Distinct people | Most customer analysis uses `customer_unique_id`; category sales view uses `customer_id`, an order-specific record |
| Customer value / repeat-purchase supporting analysis | Delivered orders; spend bands include freight |
| Dashboard customer segments/retention/cohorts | All orders; cohort/retention views require purchase timestamps |
| Supporting cohort analysis | Delivered-order acquisition and activity; differs from dashboard cohort view |
| Review satisfaction supporting analysis | Usually original review rows; repeated order reviews can affect counts |
| Dashboard KPI/state/review/seller views | Latest answer timestamp per order, tied by descending `review_row_id` |
| Dashboard delay/seller/category impact views | Average review score per order; differs from the latest-review convention |
| Supporting delivery lateness/buckets | Often calendar-day DATEDIFF |
| Final delivery/state/KPI lateness | Timestamp comparison, with fractional-day stage durations and chronology validation |
| Aggregate delay impact view | Calendar-day DATEDIFF buckets and averaged per-order review scores |
| Order-level delivery/review delay buckets | Timestamp intervals divided by 86400 |
| Supporting operational dispatch | Approval to carrier handoff |
| Final seller-view dispatch | Purchase to carrier handoff; not equivalent to operational dispatch |
| Final seller risk | At least four adverse comparisons against five unweighted seller averages, including low order count |
| Supporting seller performance | Minimum 50 seller/orders; supporting concentration uses item price only |
| Cross-dimensional seller risk | At least 50 on-time orders; on-time negative-review rate >=15%; distinct from dashboard risk heuristic |
| Cross-dimensional category risk | Original on-time negative-rate threshold and history rule in the retained statement; not interchangeable with final category-risk view |
| Review comment tagging | Eight overlapping Portuguese regex themes over negative original review rows with comments; not validated sentiment analysis |
| Payment usage | Distinct orders using each method; shares may exceed 100% across methods |
| Payment average | Depends on the query: record-level average or sum by order/method before averaging |

Multi-category and multi-seller orders can appear in several groups. Do not add their distinct counts as though groups were mutually exclusive. Missing cohort-view cells are sparse observations; distinguish no activity from months outside the observation period. Dataset endpoint months have limited sales coverage.

Amounts represent historical BRL values. Sales value, payment value, and profit are distinct; profit cannot be derived without costs. Negative reviews generally mean scores 1–2, neutral 3, and positive 4–5, but averaged scores may be fractional. Risk and delay comparisons describe historical associations, not causal effects.
