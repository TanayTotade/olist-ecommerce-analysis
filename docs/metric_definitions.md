# Metric definitions

These definitions apply to the revised SQL. Rebuild views in filename order before refreshing Tableau extracts. Existing screenshots and workbook extracts are not recalculated by editing SQL.

| Area | Definition |
| --- | --- |
| Total revenue / sales | Item price plus freight, all order statuses; a historical sales-value measure, not profit or settled receipts |
| Product revenue | Item price only; retained explicitly for product/category composition and freight comparisons |
| Order counts | All orders, including orders with no item rows; category and seller counts necessarily require an associated item |
| AOV | Average item-plus-freight value per order with an item value; orders lacking item value are excluded from AOV, not from total order counts |
| Distinct people | `customer_unique_id`, including category customer counts |
| Customer segments / purchase progression / cohorts | All order statuses; timing analyses require a purchase timestamp; order ID breaks timestamp ties |
| Cohort months | Acquisition is first purchase month; a person is counted once per activity month; observed zero-activity months are explicit zero; future months are absent |
| Observation end | Latest purchase month in the extract; partial endpoint months must not be treated as complete calendar coverage |
| Review satisfaction | One latest review per order, ordered by answer timestamp descending then `review_row_id` descending; negative 1-2, neutral 3, positive 4-5 |
| Delivery eligibility | Delivered orders with purchase, approval, carrier, customer-delivery and estimate timestamps; purchase <= approval <= carrier <= customer delivery |
| Lateness | Full delivery timestamp > estimated delivery timestamp; a positive fraction of a day is late, including later on the same calendar date |
| Elapsed durations | Seconds / 86400.0; approval: purchase to approval, dispatch: approval to carrier, shipping: carrier to customer |
| Delivery-time distribution | Calendar-day DATEDIFF bands, explicitly distinct from fractional elapsed stage averages |
| Delay buckets | On time if <=0 elapsed days versus estimate; then (0,3], (3,7], (7,14], >14. Tableau field labels are retained; labels include fractional-day boundaries |
| Seller comparison | Commercial totals across all seller orders; delivery averages use eligible deliveries; review averages use latest reviewed orders; supporting table requires >=50 orders |
| Dashboard seller risk | Four or more adverse comparisons against five unweighted seller averages, including low order count; a descriptive heuristic, not validated prediction |
| Exploratory seller/category risk | Negative feedback on on-time deliveries: seller >=50 reviewed orders and >=15% negative; category >=100 and >=12%; intentionally distinct from dashboard classifications |
| Dashboard category risk | Category latest-review negative rate above marketplace latest-review negative rate; no minimum-history rule |
| Single-category attribution | Every item must resolve to the same known, nonblank category; mixed/unknown-category orders are excluded |
| Comment themes | Original nonblank negative review records, not latest-order reviews; eight overlapping Portuguese keyword rules; matching coverage is not accuracy |
| Payment usage | Distinct orders using a defined method; mixed-method orders appear in each method, so shares can sum above 100% |
| Payment value | Recorded payments, separate from item-based sales; averages use summed values per order-method |
| Installment classification | Each credit-card order appears once using its maximum recorded installment count; payment values sum all its credit-card records; nonpositive/missing counts are unknown |

Amounts are historical BRL. Multi-category and multi-seller counts overlap and must not be added as mutually exclusive groups. Orders without reviews or eligible deliveries remain in commercial totals but not the corresponding averages. Complaint and risk comparisons describe historical associations, not causal effects. Fixed exploratory risk thresholds and dashboard risk heuristics answer different questions and must not be presented as interchangeable.

The raw attached CSV and the user's historical MySQL import differ slightly in review-row counts. Validate final numbers against the intended import; fixture results are not replacements for the published KPIs.
