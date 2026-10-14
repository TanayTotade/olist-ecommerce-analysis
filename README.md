# Olist E-Commerce Analysis | MySQL & Tableau

A portfolio project exploring the Brazilian E-Commerce Public Dataset by Olist through MySQL analysis and four Tableau dashboards. The analysis covers sales, customers, products, fulfillment, reviews, payments, sellers, and regional performance.

This edition preserves the SQL submitted during the analysis. Curation removes repeated, intermediate, and low-value statements, organizes files, and adds documentation. **Retained SQL logic is unchanged.** Suggested corrections are documented separately and have not been applied.

## Business questions

- Which categories and regions contribute most to sales?
- What distinguishes one-time and repeat customers?
- How do delivery outcomes relate to customer satisfaction?
- What payment and seller patterns appear in the data?
- Which regional and operational risks warrant closer investigation?

## Project files

| Folder | Contents |
| --- | --- |
| `sql/setup/` | Original CSV import statements, with duplicate/broken order-import attempt omitted |
| `sql/validation/` | Original row-count, relationship and coverage checks |
| `sql/analysis/` | Eleven focused analysis scripts |
| `sql/views/` | All fourteen original dashboard views, arranged in creation order |
| `docs/` | Curation decisions, query provenance, original metric definitions, suggested corrections |
| `dashboards/` | Dashboard structure and instructions for adding published work |

## Dataset and tools

Dataset: [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce).

Tools: MySQL 8.0+ and Tableau. The dataset contains multiple grains, including orders, items, payments, and review rows. Raw CSV files are not included in this repository.

## Using the SQL

1. Use the existing MySQL database from this project, containing the nine Olist source tables. The SQL files do not include CREATE TABLE statements. The review table must have the existing `review_row_id` column used by the original views.
2. If rebuilding from CSVs, create suitable source tables first. Edit the Windows CSV paths in `sql/setup/01_import_data.sql` and review newline settings and LOCAL INFILE configuration. Import each file only once. This is the original import workflow, not a newly verified installation script.
3. Select your project database as the active schema in Workbench; no database name is hardcoded in the analysis/view scripts.
4. Run `sql/validation/01_data_validation.sql` and inspect the outputs.
5. Run the view files in numeric order. The seller view is created before `vw_kpis`, which references it.
6. Run any analysis script after the data has been loaded. The analysis scripts are independent of the views.
7. Export relevant view results to Tableau or connect Tableau to MySQL.

Read `docs/metric_definitions.md` before comparing results across scripts: the original analysis uses different revenue, status, delivery, review, and seller-risk definitions in different places. They have deliberately not been standardized in this edition.

## Tableau presentation

1. Executive Sales Overview
2. Customer Experience & Delivery
3. Regional & Seller Risk
4. Customer Behavior & Insights

Add your final screenshots and Tableau Public link as described in `dashboards/README.md`.

## Curation and verification

All **90 retained statements** were compared to the uploaded SQL and confirmed unchanged apart from surrounding whitespace and terminal semicolon normalization. A provenance document maps every statement to its original file. No new analytical queries, schema SQL, Python importer, or replacement KPI figures are included.

This verification checks preservation of the submitted SQL. It does not establish that every retained query is statistically correct or newly tested in native MySQL. See `docs/suggested_corrections.md` for issues to review separately.
