-- Exploratory comment participation and overlapping complaint themes; not validated sentiment analysis.
-- MySQL 8+. See docs/metric_definitions.md for shared definitions.

-- Question: How often do review records contain nonblank comments, and how long are they?
-- Original review records are retained for text exploration; these are not unique-order metrics.
SELECT
    review_score,
    COUNT(*) AS total_reviews,

    SUM(
        CASE
            WHEN review_comment_message IS NOT NULL
                 AND TRIM(review_comment_message) <> ''
            THEN 1
            ELSE 0
        END
    ) AS reviews_with_comments,

    ROUND(
        SUM(
            CASE
                WHEN review_comment_message IS NOT NULL
                     AND TRIM(review_comment_message) <> ''
                THEN 1
                ELSE 0
            END
        ) / COUNT(*) * 100,
        2
    ) AS comment_rate_pct,

    ROUND(
        AVG(
            CASE
                WHEN review_comment_message IS NOT NULL
                     AND TRIM(review_comment_message) <> ''
                THEN CHAR_LENGTH(review_comment_message)
            END
        ),
        2
    ) AS avg_comment_length

FROM olist_order_reviews_dataset
GROUP BY review_score
ORDER BY review_score;

-- Question: Which themes occur in negative comments (scores 1-2)?
-- Portuguese regex rules are approximate and have not been manually validated.
-- Themes overlap; classified_pct is matching coverage, not accuracy. Counts are comment records.
WITH classified_reviews AS (
    SELECT
        review_id,
        review_score,
        review_comment_message,

        
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'não recebi|nao recebi|não.*entreg|nao.*entreg|não chegou|nao chegou|não.*chegou|nao.*chegou|nada de chegar|quando chegar|aguardando.*chegada|aguardando.*produto|atras|demor|prazo.*entrega|data prevista|dias previstos|passou.*prazo|passou.*dias|quase [0-9]+ dias'
            THEN 1 ELSE 0
        END AS delivery,

        
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'faltou|faltando|pedido incompleto|somente.*um|somente.*uma|apenas.*um|apenas.*uma|recebi.*metade|só recebi|so recebi|recebemos.*1|recebi.*dois.*um|recebi.*duas.*uma'
            THEN 1 ELSE 0
        END AS missing_product,

        
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'produto errado|produto diferente|produto.*difere|veio outro|recebi outro|enviaram.*outro|cor.*chegou.*cor|não.*foto|nao.*foto|não.*descri|nao.*descri|não.*anúncio|nao.*anuncio|inferior'
            THEN 1 ELSE 0
        END AS product_mismatch,

        
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'péssima qualidade|pessima qualidade|má qualidade|ma qualidade|qualidade.*ruim|não funciona|nao funciona|defeito|defeitu|quebrou|fraco|fraca|mal acabado|acabamento.*ruim|material.*ruim|não recomendo|nao recomendo'
            THEN 1 ELSE 0
        END AS quality_defect,

        
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'danific|quebrad|avariad|amassad|descolad|embalagem|caixa.*destru|batido|batida'
            THEN 1 ELSE 0
        END AS damage_packaging,

        
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'cancel|reembolso|devolver|devolução|devolucao|ressarc|dinheiro de volta|estorno|troca'
            THEN 1 ELSE 0
        END AS refund_return,

        
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'sem estoque|não tem.*estoque|nao tem.*estoque|não tinham.*dispon|nao tinham.*dispon|indisponível|indisponivel|disponibilidade'
            THEN 1 ELSE 0
        END AS stock,

        
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'sem resposta|não.*responde|nao.*responde|nenhum retorno|sem retorno|aguardando.*resposta|nenhuma satisfação|nenhuma satisfacao|não atend|nao atend|pós venda|pos venda|reclamação|reclamacao|falar com.*pessoa'
            THEN 1 ELSE 0
        END AS service_communication

    FROM olist_order_reviews_dataset
    WHERE review_score IN (1, 2)
      AND review_comment_message IS NOT NULL
      AND TRIM(review_comment_message) <> ''
)

SELECT
    COUNT(*) AS negative_comments,

    SUM(delivery) AS delivery,
    SUM(missing_product) AS missing_product,
    SUM(product_mismatch) AS product_mismatch,
    SUM(quality_defect) AS quality_defect,
    SUM(damage_packaging) AS damage_packaging,
    SUM(refund_return) AS refund_return,
    SUM(stock) AS stock,
    SUM(service_communication) AS service_communication,

    SUM(
        CASE
            WHEN delivery
               + missing_product
               + product_mismatch
               + quality_defect
               + damage_packaging
               + refund_return
               + stock
               + service_communication > 0
            THEN 1 ELSE 0
        END
    ) AS classified_comments,

    ROUND(
        SUM(
            CASE
                WHEN delivery
                   + missing_product
                   + product_mismatch
                   + quality_defect
                   + damage_packaging
                   + refund_return
                   + stock
                   + service_communication > 0
                THEN 1 ELSE 0
            END
        ) / COUNT(*) * 100,
        2
    ) AS classified_pct

FROM classified_reviews;

-- Question: What recorded delivery outcomes accompany delivery-related negative comments?
-- Count original matching review records; keep missing delivery dates and missing estimates separate.
-- Delivery outcomes reflect the extract, not necessarily status at the time a comment was written.
WITH delivery_complaints AS (
    SELECT
        r.order_id,
        r.review_score,
        r.review_comment_message
    FROM olist_order_reviews_dataset AS r
    WHERE r.review_score IN (1, 2)
      AND r.review_comment_message IS NOT NULL
      AND TRIM(r.review_comment_message) <> ''
      AND LOWER(r.review_comment_message) REGEXP
          'não recebi|nao recebi|não.*entreg|nao.*entreg|não chegou|nao chegou|não.*chegou|nao.*chegou|nada de chegar|quando chegar|aguardando.*chegada|aguardando.*produto|atras|demor|prazo.*entrega|data prevista|dias previstos|passou.*prazo|passou.*dias|quase [0-9]+ dias'
)

SELECT
    CASE
        WHEN o.order_delivered_customer_date IS NULL
            THEN 'Not delivered / no delivery date'

        WHEN o.order_estimated_delivery_date IS NULL
            THEN 'Unknown estimate'

        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 'Delivered late'

        ELSE 'Delivered on time'
    END AS delivery_outcome,

    COUNT(*) AS complaint_reviews,

    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (),
        2
    ) AS pct_of_delivery_complaints

FROM delivery_complaints AS dc
JOIN olist_orders_dataset AS o
    ON dc.order_id = o.order_id

GROUP BY
    CASE
        WHEN o.order_delivered_customer_date IS NULL
            THEN 'Not delivered / no delivery date'

        WHEN o.order_estimated_delivery_date IS NULL
            THEN 'Unknown estimate'

        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 'Delivered late'

        ELSE 'Delivered on time'
    END

ORDER BY complaint_reviews DESC;

-- Question: What order statuses occur in delivery complaints without a delivery date?
-- Percentages use only matching comment records with no delivery date.
WITH delivery_complaints AS (
    SELECT
        r.order_id
    FROM olist_order_reviews_dataset AS r
    WHERE r.review_score IN (1, 2)
      AND r.review_comment_message IS NOT NULL
      AND TRIM(r.review_comment_message) <> ''
      AND LOWER(r.review_comment_message) REGEXP
          'não recebi|nao recebi|não.*entreg|nao.*entreg|não chegou|nao chegou|não.*chegou|nao.*chegou|nada de chegar|quando chegar|aguardando.*chegada|aguardando.*produto|atras|demor|prazo.*entrega|data prevista|dias previstos|passou.*prazo|passou.*dias|quase [0-9]+ dias'
)

SELECT
    o.order_status,
    COUNT(*) AS complaint_reviews,

    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (),
        2
    ) AS pct
FROM delivery_complaints AS dc
JOIN olist_orders_dataset AS o
    ON dc.order_id = o.order_id

WHERE o.order_delivered_customer_date IS NULL

GROUP BY o.order_status
ORDER BY complaint_reviews DESC;

