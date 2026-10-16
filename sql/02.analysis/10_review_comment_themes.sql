-- Comment participation, final eight-theme classifier and delivery-complaint outcomes.

-- customer behavior by review score
-- Question: How often do customers leave comments, and how long are they?
-- Counts review records; NULL/blank comments are excluded from comment length averages.

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

-- new complaint theme
-- Question: Which complaint themes occur in nonblank negative reviews (scores 1-2)?
-- Portuguese keyword rules are approximate and may miss or misclassify comments.
-- Themes overlap: one comment may match several; theme counts are not additive.
-- classified_pct counts comments matching at least one theme, not classification accuracy.

WITH classified_reviews AS (
    SELECT
        review_id,
        review_score,
        review_comment_message,

        /* 1. DELIVERY / NON-DELIVERY */
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'não recebi|nao recebi|não.*entreg|nao.*entreg|não chegou|nao chegou|não.*chegou|nao.*chegou|nada de chegar|quando chegar|aguardando.*chegada|aguardando.*produto|atras|demor|prazo.*entrega|data prevista|dias previstos|passou.*prazo|passou.*dias|quase [0-9]+ dias'
            THEN 1 ELSE 0
        END AS delivery,

        /* 2. MISSING / INCOMPLETE ORDER */
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'faltou|faltando|pedido incompleto|somente.*um|somente.*uma|apenas.*um|apenas.*uma|recebi.*metade|só recebi|so recebi|recebemos.*1|recebi.*dois.*um|recebi.*duas.*uma'
            THEN 1 ELSE 0
        END AS missing_product,

        /* 3. WRONG / MISMATCHED PRODUCT */
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'produto errado|produto diferente|produto.*difere|veio outro|recebi outro|enviaram.*outro|cor.*chegou.*cor|não.*foto|nao.*foto|não.*descri|nao.*descri|não.*anúncio|nao.*anuncio|inferior'
            THEN 1 ELSE 0
        END AS product_mismatch,

        /* 4. QUALITY / DEFECT */
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'péssima qualidade|pessima qualidade|má qualidade|ma qualidade|qualidade.*ruim|não funciona|nao funciona|defeito|defeitu|quebrou|fraco|fraca|mal acabado|acabamento.*ruim|material.*ruim|não recomendo|nao recomendo'
            THEN 1 ELSE 0
        END AS quality_defect,

        /* 5. DAMAGE / PACKAGING */
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'danific|quebrad|avariad|amassad|descolad|embalagem|caixa.*destru|batido|batida'
            THEN 1 ELSE 0
        END AS damage_packaging,

        /* 6. CANCELLATION / REFUND / RETURN */
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'cancel|reembolso|devolver|devolução|devolucao|ressarc|dinheiro de volta|estorno|troca'
            THEN 1 ELSE 0
        END AS refund_return,

        /* 7. STOCK / AVAILABILITY */
        CASE
            WHEN LOWER(review_comment_message) REGEXP
                'sem estoque|não tem.*estoque|nao tem.*estoque|não tinham.*dispon|nao tinham.*dispon|indisponível|indisponivel|disponibilidade'
            THEN 1 ELSE 0
        END AS stock,

        /* 8. SERVICE / COMMUNICATION */
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
-- Counts matching review records, not distinct orders; outcomes are from the order table.
-- Missing delivery dates form a separate group; a missing estimate falls into the ELSE group.
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

        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 'Delivered late'

        ELSE 'Delivered on time'
    END

ORDER BY complaint_reviews DESC;

-- Question: What order statuses occur among delivery complaints with no delivery date?
-- Percentages use only matching review rows whose order has no recorded delivery date.
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
