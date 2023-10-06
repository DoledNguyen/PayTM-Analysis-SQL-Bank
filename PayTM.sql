-- Kiểm tra dữ liệu 
SELECT * FROM dbo.fact_transaction_2019
SELECT * FROM dbo.fact_transaction_2020
SELECT * FROM dbo.dim_payment_channel
SELECT * FROM dbo.dim_platform
SELECT * FROM dbo.dim_scenario
SELECT * FROM dbo.dim_status -- status_id = 1 là giao dịch thành công các status_id còn lại có lỗi trong giao dịch
-- Kiểm tra các giá trị duy nhẩt 
SELECT DISTINCT transaction_type  FROM dbo.dim_scenario
SELECT DISTINCT sub_category FROM dbo.dim_scenario
SELECT DISTINCT category FROM dbo.dim_scenario

---- ANALYSIS
-- Tìm các giao dịch có transaction_type khác payment trong tháng 1 năm 2019
SELECT customer_id, transaction_id, fact_19.scenario_id, transaction_type, sub_category, category
FROM dbo.fact_transaction_2019 fact_19 --2019/2020
JOIN dbo.dim_scenario scena ON scena.scenario_id = fact_19.scenario_id
WHERE MONTH(transaction_time) = 1 AND transaction_type != 'Payment'

--Tìm các giao dịch có thanh toán trên nền tảng android ở tháng 1 trong 2 năm 2019 và 2020
SELECT customer_id, transaction_id, scenario_id, payment_method, payment_platform
FROM (SELECT * FROM dbo.fact_transaction_2019
      UNION 
      SELECT * FROM dbo.fact_transaction_2020) as fact_table
LEFT JOIN dim_platform platform ON fact_table.platform_id = platform.platform_id
LEFT JOIN dim_payment_channel channel ON channel.payment_channel_id = fact_table.payment_channel_id
WHERE payment_platform = 'android' AND MONTH(transaction_time) = 1

/* Tìm nhóm khách hàng phát sinh giao dịch trong tháng 01/2019 (Nhóm A) và các giao dịch bổ sung của nhóm khách hàng này (Nhóm A) 
tiếp tục phát sinh giao dịch trong tháng 01/2020.Nền tảng thanh toán là IOS*/
SELECT customer_id, transaction_id, scenario_id, payment_method, payment_platform
FROM fact_transaction_2019 AS fact_19
LEFT JOIN dim_platform AS platform
   ON fact_19.platform_id = platform.platform_id
LEFT JOIN dim_payment_channel AS channel
   ON fact_19.payment_channel_id = channel.payment_channel_id
WHERE MONTH(transaction_time) = 1
   AND payment_platform = 'ios' -- 11,783 rows của Group A phát sinh trong tháng 1/2019

UNION 
SELECT customer_id, transaction_id, scenario_id, payment_method, payment_platform
FROM fact_transaction_2020 AS fact_20
LEFT JOIN dim_platform AS platform
   ON fact_20.platform_id = platform.platform_id
LEFT JOIN dim_payment_channel AS channel
   ON fact_20.payment_channel_id = channel.payment_channel_id
WHERE MONTH(transaction_time) = 1
   AND payment_platform = 'ios'
   AND customer_id IN ( SELECT DISTINCT customer_id
                   FROM fact_transaction_2019 AS fact_19
                   LEFT JOIN dim_platform AS platform ON fact_19.platform_id = platform.platform_id
                   LEFT JOIN dim_payment_channel AS channel ON fact_19.payment_channel_id = channel.payment_channel_id
                   WHERE MONTH(transaction_time) = 1 AND payment_platform = 'ios'
                       ) -- Có 19,962 giao dịch phát sinh 

/* Với bảng dữ liệu fact_transaction_2019.
Hãy thống kê xem mỗi khách hàng đã phát sinh bao nhiêu giao dịch, đã chi bao nhiêu tiền (chỉ tính các gd thành công)*/
SELECT customer_id,
COUNT(transaction_id) number_trans,
SUM(charged_amount*1.0) spent_money
FROM fact_transaction_2019 fact_19
LEFT JOIN dbo.dim_status sta_table ON sta_table.status_id = fact_19.status_id
WHERE status_description = 'Success'
GROUP BY customer_id 
ORDER BY COUNT(transaction_id) DESC

-- Hãy cho biết số lượng giao dịch thành công và số khách hàng giao dịch thành công theo từng tháng trong 2019 ?
WITH joined_table AS (
   SELECT transaction_time, customer_id, transaction_id
   ,MONTH(transaction_time) [month]
   FROM fact_transaction_2019 fact_19
   JOIN dim_status AS sta ON fact_19.status_id = sta.status_id
   WHERE status_description = 'success'
)
SELECT [month]
,COUNT(transaction_id) number_trans
,COUNT(DISTINCT(customer_id)) number_cus
FROM joined_table
GROUP BY [month]
ORDER BY [month]

-- Tỷ trọng % giao dịch thành công của từng tháng so với cả năm là bao nhiêu?
WITH joined_table AS (
   SELECT transaction_time, customer_id, transaction_id,
   MONTH(transaction_time) [month]
   FROM fact_transaction_2019 AS fact_19
   JOIN dim_status AS sta ON fact_19.status_id = sta.status_id
   WHERE status_description = 'success'
)
,total_table as (
   SELECT [month],
   COUNT(transaction_id) number_trans,
   COUNT(customer_id) number_cus,
   (SELECT COUNT(transaction_id) FROM fact_transaction_2019) total_transaction_year,
   (SELECT COUNT(DISTINCT(customer_id)) FROM fact_transaction_2019) total_customer_year
   FROM joined_table
   GROUP BY [month]
)
SELECT [month],number_trans,number_cus
,FORMAT(number_trans*1.0/total_transaction_year,'p') percentage_trans
,FORMAT(number_cus*1.0/ total_customer_year,'p') percentage_customer
FROM total_table

/*Bạn hãy cho biết tổng số giao dịch của từng loại transaction_type, với điều kiện: giao dịch thành công, thời gian giao dịch trong 3 tháng đầu tiên của năm 2019
Tính tỷ trọng số lượng giao dịch của từng loại trên tổng số giao dịch trong 3 tháng.*/
WITH joined_table as (
   SELECT transaction_id, transaction_type
   FROM dbo.fact_transaction_2019 fact_19
   JOIN dbo.dim_scenario scena ON scena.scenario_id = fact_19.scenario_id
   WHERE MONTH(transaction_time) < 4 AND status_id = 1 -- thành công
) 
,total_table as (
   SELECT transaction_type
   ,COUNT(transaction_id) number_trans
   ,(SELECT COUNT(transaction_id) 
      FROM dbo.fact_transaction_2019
      WHERE MONTH(transaction_time) < 4 AND status_id = 1 ) total_trans
   FROM joined_table
   GROUP BY transaction_type
)
SELECT * 
,FORMAT(number_trans*1.0/total_trans,'p') [percentage]
FROM total_table
ORDER BY number_trans DESC

/*Thống kê xem mỗi tháng 2019 có bao nhiêu giao dịch nhóm Telco, bao nhiêu tiền. Mỗi tháng chiếm bao nhiêu % ?*/
WITH month_table AS (
   SELECT customer_id, transaction_id, transaction_time, charged_amount
       , MONTH(transaction_time) [month]
   FROM fact_transaction_2019 fact_19
   LEFT JOIN dim_scenario scena
   ON fact_19.scenario_id = scena.scenario_id
   WHERE category = 'Telco' AND status_id = 1 -- thành công
)
,amount_month AS (   
   SELECT DISTINCT [month]
    ,COUNT(transaction_id) OVER ( PARTITION BY [month] ) number_trans_month
    ,SUM(charged_amount *1.0) OVER ( PARTITION BY [month] ) total_amount_month
    ,(SELECT SUM (charged_amount *1.0) FROM month_table ) amount_year
   FROM month_table
)
SELECT *
,FORMAT(total_amount_month/amount_year,'p') pct_amount
FROM amount_month
--Tìm TOP 3 tháng có nhiều giao dịch bị lỗi nhất của từng năm
WITH failed_month_table AS (
  SELECT YEAR (transaction_time) [year]
   ,MONTH (transaction_time) [month]
   ,COUNT (transaction_id ) number_failed_trans
  FROM (SELECT transaction_id, transaction_time, scenario_id, status_id FROM dbo.fact_transaction_2019
        UNION
        SELECT transaction_id, transaction_time, scenario_id, status_id FROM dbo.fact_transaction_2020) AS fact_table
  WHERE status_id != 1 -- giao dịch lỗi
  GROUP BY YEAR (transaction_time), MONTH (transaction_time)
)
, rank_table AS (
   SELECT *
   ,RANK () OVER ( PARTITION BY [year] ORDER BY number_failed_trans DESC ) rank_column
   FROM failed_month_table
)
SELECT *
FROM rank_table
WHERE rank_column < 4

-- Tìm top 3 KH chi nhiều tiền nhất trong mỗi tháng (chỉ tính giao dịch success và Telco)
WITH month_table AS (
   SELECT
    MONTH (transaction_time) [month]
   ,customer_id
   ,SUM (charged_amount *1.0) total_amount_month
   FROM fact_transaction_2019 fact_19
   LEFT JOIN dim_scenario scena
   ON fact_19.scenario_id = scena.scenario_id
   WHERE category = 'Telco' AND status_id = 1 -- thành công
   GROUP BY MONTH (transaction_time), customer_id
)
, rank_table AS (
   SELECT *
   ,RANK() OVER ( PARTITION BY [month] ORDER BY total_amount_month DESC ) rank_month
   FROM month_table
)
SELECT *
FROM rank_table
WHERE rank_month <= 3
ORDER BY [month], rank_month

-- Đánh giá yếu tố số lượng khách hàng theo từng tháng của năm 2020 tăng hay giảm bao nhiêu % so với cùng kì năm trước(2019).
WITH month_table AS (
   SELECT YEAR(transaction_time) [year]
   ,MONTH(transaction_time) [month]
   ,COUNT(DISTINCT customer_id ) number_customers
   FROM  (SELECT * FROM fact_transaction_2019
          UNION
          SELECT * FROM fact_transaction_2020 ) fact_table
   LEFT JOIN dim_scenario scena ON fact_table.scenario_id = scena.scenario_id
   WHERE category = 'Telco' AND status_id = 1 -- thành công
   GROUP BY YEAR(transaction_time), MONTH (transaction_time)
)
SELECT *
,LAG(number_customers, 12) OVER ( ORDER BY [year] ASC, [month] ASC ) number_customer_last_year
,FORMAT( number_customers *1.0 /  LAG (number_customers, 12) OVER ( ORDER BY [year] ASC, [month] ASC ), 'P' ) AS '% different'
FROM month_table

-- Khoảng cách trung bình giữa các lần thanh toán thành công  theo từng khách hàng trong nhóm Telecom trong năm 2019
WITH customer_table AS (
  SELECT TOP 1000 customer_id, transaction_id, transaction_time
  ,LAG(transaction_time, 1) OVER ( PARTITION BY customer_id ORDER BY transaction_time ASC ) previous_time
  ,DATEDIFF(day, LAG (transaction_time, 1) OVER ( PARTITION BY customer_id ORDER BY transaction_time ASC ),transaction_time) gap_day
  FROM (SELECT customer_id, transaction_id, transaction_time, scenario_id FROM dbo.fact_transaction_2019
        UNION
        SELECT customer_id, transaction_id, transaction_time, scenario_id FROM dbo.fact_transaction_2020) fact_table
  LEFT JOIN dbo.dim_scenario
  ON fact_table.scenario_id = dbo.dim_scenario.scenario_id
  WHERE category = 'Telco'
)
,gap_table AS (
   SELECT *
   ,AVG (gap_day) OVER ( PARTITION BY customer_id) AS avg_gap_day
   FROM customer_table
)
SELECT customer_id, avg_gap_day
FROM gap_table
GROUP BY customer_id, avg_gap_day
ORDER BY customer_id


--- TIME SERIES ANALYSIS
-- Phân tích xu hướng giao dịch thanh toán của danh mục Billing từ năm 2019 đến năm 2020. Đầu tiên, cho biết xu hướng số lượng giao dịch thành công theo tháng.
SELECT
YEAR(transaction_time) [year]
,MONTH (transaction_time) [month]
,COUNT (transaction_id) number_trans
FROM (SELECT transaction_id, transaction_time, scenario_id, status_id FROM dbo.fact_transaction_2019
      UNION
      SELECT transaction_id, transaction_time, scenario_id, status_id FROM dbo.fact_transaction_2020) fact_table
LEFT JOIN dbo.dim_scenario ON fact_table.scenario_id = dbo.dim_scenario.scenario_id
LEFT JOIN dbo.dim_status ON fact_table.status_id = dbo.dim_status.status_id
WHERE category = 'Billing' AND fact_table.status_id = 1
GROUP BY YEAR(transaction_time), MONTH (transaction_time)
ORDER BY [year], [month]
-- Có nhiều danh mục phụ của nhóm Thanh toán(sub_category). Sau khi xem xét kết quả trên, chia xu hướng thành từng danh mục phụ.
SELECT
YEAR(transaction_time) [year]
,MONTH (transaction_time) [month]
,sub_category
,COUNT (transaction_id) number_trans
FROM (SELECT transaction_id, transaction_time, scenario_id, status_id FROM dbo.fact_transaction_2019
      UNION
      SELECT transaction_id, transaction_time, scenario_id, status_id FROM dbo.fact_transaction_2020) fact_table
LEFT JOIN dbo.dim_scenario ON fact_table.scenario_id = dbo.dim_scenario.scenario_id
LEFT JOIN dbo.dim_status ON fact_table.status_id = dbo.dim_status.status_id
WHERE category = 'Billing' AND fact_table.status_id = 1
GROUP BY YEAR(transaction_time), MONTH (transaction_time), sub_category
ORDER BY [year], [month]
-- Pivot Table. Chỉ chọn các tiểu mục thuộc danh mục (Điện, Internet và Nước)
WITH month_table AS (
   SELECT
   YEAR(transaction_time) [year]
   ,MONTH (transaction_time) [month]
   ,sub_category
   ,COUNT (transaction_id) number_trans
   FROM (SELECT transaction_id, transaction_time, scenario_id, status_id FROM dbo.fact_transaction_2019
         UNION
         SELECT transaction_id, transaction_time, scenario_id, status_id FROM dbo.fact_transaction_2020) fact_table
   LEFT JOIN dbo.dim_scenario ON fact_table.scenario_id = dbo.dim_scenario.scenario_id
   LEFT JOIN dbo.dim_status ON fact_table.status_id = dbo.dim_status.status_id
   WHERE category = 'Billing' AND fact_table.status_id = 1
   GROUP BY YEAR(transaction_time), MONTH (transaction_time), sub_category
)
SELECT * FROM (
  SELECT
  [year],[month],sub_category,number_trans
  FROM month_table
) StudentResults
PIVOT (
  SUM(number_trans)
  FOR sub_category
  IN (Electricity, Internet, Water)
) AS PivotTable
ORDER BY [year],[month]
--Dựa vào truy vấn trên, tính tỷ lệ của từng danh mục phụ (Điện, Internet và Nước) trong tổng số cho mỗi tháng.
WITH month_table AS (
   SELECT
   YEAR(transaction_time) [year]
   ,MONTH (transaction_time) [month]
   ,sub_category
   ,COUNT (transaction_id) number_trans
  FROM (SELECT transaction_id, transaction_time, scenario_id, status_id FROM dbo.fact_transaction_2019
        UNION
        SELECT transaction_id, transaction_time, scenario_id, status_id FROM dbo.fact_transaction_2020) fact_table
  LEFT JOIN dbo.dim_scenario ON fact_table.scenario_id = dbo.dim_scenario.scenario_id
  LEFT JOIN dbo.dim_status ON fact_table.status_id = dbo.dim_status.status_id
  WHERE category = 'Billing' AND fact_table.status_id = 1
  GROUP BY YEAR(transaction_time), MONTH (transaction_time), sub_category
)
, pivot_table AS (
   SELECT * FROM (
   SELECT
   [year],[month],sub_category,number_trans
   FROM month_table
   ) StudentResults
   PIVOT (
   SUM(number_trans)
   FOR sub_category
   IN (Electricity, Internet, Water)
   ) AS PivotTable
)
SELECT *
,Electricity + Internet + Water AS total_trans_month
,FORMAT (Electricity*1.0 / ( Electricity + Internet + Water), 'p') elec_pct
,FORMAT (Internet *1.0 / (Electricity + Internet + Water), 'p') internet_pct
,FORMAT (Water*1.0 / (Electricity + Internet + Water), 'p') water_pct
FROM pivot_table
ORDER BY [year],[month]


/* Đề bài: 
Bạn là đang là Business Owner của sản phẩm thanh toán hóa đơn tiền điện (sub_category = electricity). Trong năm 2020 vừa qua, team Marketing đã triển khai rất nhiều chương trình khuyến mãi (promotion_id <> ‘0’)
nhưng không biết có mang lại hiệu quả hay không? Vì thế bạn muốn đánh giá một số metrics sau đây: 
Task 1: Cho biết xu hướng của lượng giao dịch thanh toán thành công có hưởng khuyến mãi (promtion_trans) theo từng tuần và chiếm tỷ trọng bao nhiêu trên tổng số giao dịch thanh toán thành công (promotion_ratio) ? 
Task 2: Trong tổng số khách hàng thanh toán thành công có hưởng khuyến mãi, có bao nhiêu % khách hàng đã phát sinh thêm bất kỳ giao dịch thanh toán thành công khác mà không phải là giao dịch khuyến mãi ? */

-- TASK 1: 
WITH elec_success_trans AS (
   SELECT transaction_id
   ,MONTH(transaction_time) [month]
   ,DATEPART( WEEK, transaction_time) week_number
   ,promotion_id
   ,IIF( promotion_id <> '0' , 'is_promo', 'non_promo') trans_type
   FROM fact_transaction_2020 fact_2020
   LEFT JOIN dim_scenario scena ON fact_2020.scenario_id = scena.scenario_id
   WHERE sub_category = 'Electricity' AND status_id = 1
)
SELECT week_number
,COUNT(CASE WHEN trans_type = 'is_promo' THEN transaction_id END ) number_promotion_trans
,COUNT(transaction_id) number_success_trans
,FORMAT(COUNT(CASE WHEN trans_type = 'is_promo' THEN transaction_id END )*1.0 / COUNT(transaction_id),'p' ) promotion_ratio
FROM elec_success_trans
GROUP BY week_number
ORDER BY week_number

-- TASK 2: Tính tỷ lệ KH hưởng khuyến mãi sau đó có phát sinh thêm giao dịch bình thường
WITH electric_table AS (
   SELECT customer_id, transaction_id, promotion_id
   ,IIF ( promotion_id <> '0' , 'is_promo', 'non_promo') trans_type
   FROM fact_transaction_2020 fact_2020
   LEFT JOIN dim_scenario scena ON fact_2020.scenario_id = scena.scenario_id
   WHERE sub_category = 'Electricity' AND status_id = 1
)
, previous_table AS (
   SELECT *
   ,LAG(trans_type, 1) OVER ( PARTITION BY customer_id ORDER BY transaction_id ASC ) check_previous_tran
   FROM electric_table
)
SELECT COUNT (DISTINCT customer_id) customer_make_non_promotion
 ,(SELECT COUNT (DISTINCT customer_id) FROM previous_table WHERE trans_type = 'is_promo') total_promotion_customer
FROM previous_table
WHERE trans_type = 'non_promo' AND check_previous_tran = 'is_promo'
--> Đáp án: 503 KH 

---COHORT ANALYSIS
-- Tìm ra tỉ lệ ở lại của nhóm khách hàng “Telco Card” sau từng tháng kể từ khi khách hàng đó sử dụng dịch vụ lần đầu tiên là tháng 1
WITH table_first_month AS (
   SELECT customer_id, transaction_id, transaction_time
   , MIN(MONTH(transaction_time)) OVER ( PARTITION BY customer_id ) first_month
   FROM fact_transaction_2019 fact_19
   JOIN dim_scenario sce ON fact_19.scenario_id = sce.scenario_id
   WHERE sub_category = 'Telco Card' AND status_id = 1
)
SELECT
MONTH(transaction_time) - 1 [supsequent_month]
,COUNT(DISTINCT customer_id) number_retained_customers
FROM table_first_month
WHERE first_month = 1
GROUP BY MONTH(transaction_time) - 1
ORDER BY [supsequent_month]
-- Tính tỉ lệ giữ chân
WITH table_first_month AS (
   SELECT customer_id, transaction_id, transaction_time
   ,MIN(MONTH (transaction_time)) OVER (PARTITION BY customer_id ) first_month
   FROM fact_transaction_2019 fact_19
   JOIN dim_scenario sce ON fact_19.scenario_id = sce.scenario_id
   WHERE sub_category = 'Telco Card' AND status_id = 1
)
, table_sub_month AS (
   SELECT
   MONTH(transaction_time) - 1 [supsequent_month]
   ,COUNT(DISTINCT customer_id) number_retained_customers
   FROM table_first_month
   WHERE first_month = 1
   GROUP BY MONTH(transaction_time) - 1
)
SELECT *
,FIRST_VALUE(number_retained_customers ) OVER ( ORDER BY supsequent_month ASC ) original_customers
,FORMAT(number_retained_customers*1.0/FIRST_VALUE(number_retained_customers ) OVER ( ORDER BY supsequent_month ASC ),'p') pct_retained
FROM table_sub_month

-- Mở rộng truy vấn trước đó, tính tỷ lệ giữ chân cho nhiều thuộc tính từ tháng chuyển đổi (tháng đầu tiên) (từ tháng 1 đến tháng 12).
WITH table_first_month AS (
   SELECT customer_id, transaction_id, transaction_time
   ,MIN(MONTH (transaction_time)) OVER ( PARTITION BY customer_id ) first_month
   ,MONTH(transaction_time) - MIN(MONTH (transaction_time)) OVER ( PARTITION BY customer_id ) subsequent_month
   FROM fact_transaction_2019 fact_19
   JOIN dim_scenario sce ON fact_19.scenario_id = sce.scenario_id
   WHERE sub_category = 'Telco Card' AND status_id = 1
)
,table_sub_month AS (
   SELECT first_month AS acquisition_month
   ,subsequent_month
   ,COUNT(DISTINCT customer_id) number_retained_customers
   FROM table_first_month
   GROUP BY first_month, subsequent_month
)
SELECT *
,FIRST_VALUE( number_retained_customers ) OVER ( PARTITION BY acquisition_month ORDER BY subsequent_month ASC ) original_customers
,FORMAT( number_retained_customers *1.0/ FIRST_VALUE( number_retained_customers ) OVER ( PARTITION BY acquisition_month ORDER BY subsequent_month ASC ), 'p') pct
FROM table_sub_month

-- Dùng pivot để chuyển sang dạng table heatmap
WITH table_first_month AS (
   SELECT customer_id, transaction_id, transaction_time
   ,MIN (MONTH (transaction_time)) OVER ( PARTITION BY customer_id ) first_month
   ,MONTH(transaction_time) - MIN( MONTH (transaction_time)) OVER ( PARTITION BY customer_id ) subsequent_month
   FROM fact_transaction_2019 fact_19
   JOIN dim_scenario sce ON fact_19.scenario_id = sce.scenario_id
   WHERE sub_category = 'Telco Card' AND status_id = 1
 )
, table_sub_month AS (
   SELECT first_month AS acquisition_month
   ,subsequent_month
   ,COUNT (DISTINCT customer_id) number_retained_customers
   FROM table_first_month
   GROUP BY first_month, subsequent_month
 )
, table_retention AS (
   SELECT *
   ,FIRST_VALUE ( number_retained_customers ) OVER ( PARTITION BY acquisition_month ORDER BY subsequent_month ASC ) original_customers
   ,FORMAT(number_retained_customers * 1.0 / FIRST_VALUE ( number_retained_customers ) OVER ( PARTITION BY acquisition_month ORDER BY subsequent_month ASC ),'p') pct
   FROM table_sub_month
 )
SELECT acquisition_month
   , original_customers
   , "0", "1", "2", "3", "4", "5", "6","7", "8", "9", "10", "11"
FROM ( SELECT acquisition_month, subsequent_month, original_customers, pct
       FROM table_retention) AS source_table
PIVOT (
   MAX (pct)
   FOR subsequent_month IN ( "0", "1", "2", "3", "4", "5", "6",  "7", "8", "9", "10", "11" )
) AS pivot_logic
ORDER BY acquisition_month

-- Phân loại nhóm khách hàng? Từ đó đưa ra các ưu đãi hợp lí cho khách hàng (sử dụng mô hình RFM)
WITH fact_table AS -- tạo bảng fact chung
   (SELECT customer_id,transaction_id, transaction_time, charged_amount, sub_category
   ,CAST(transaction_time AS DATE) transaction_date
    FROM fact_transaction_2019 fact_2019
    JOIN dim_scenario scen ON scen.scenario_id = fact_2019.scenario_id
    WHERE status_id = 1 AND category = 'Billing'
   UNION ALL
      SELECT customer_id, transaction_id, transaction_time, charged_amount, sub_category
      ,CAST(transaction_time AS DATE) transaction_date
      FROM fact_transaction_2020 fact_2020
      JOIN dim_scenario scen ON scen.scenario_id = fact_2020.scenario_id
      WHERE status_id = 1 AND category = 'Billing')

,rfm_model AS (
   SELECT customer_id
   ,DATEDIFF(DAY, MAX(transaction_time), '2020-12-31') Recency
   ,COUNT(DISTINCT transaction_id) Frequency
   ,SUM(charged_amount) Monetary
   FROM fact_table
   GROUP BY customer_id
 )
,rfm_percent AS (
   SELECT customer_id
   ,PERCENT_RANK() OVER ( ORDER BY Recency DESC)  r_percent_rank
   ,PERCENT_RANK() OVER ( ORDER BY Frequency ASC) f_percent_rank
   ,PERCENT_RANK() OVER ( ORDER BY Monetary ASC) m_percent_rank
   FROM rfm_model
 )
,tier_table AS (
   SELECT customer_id,
   CASE WHEN r_percent_rank <= 0.25 then 4
        WHEN r_percent_rank <= 0.5 then 3
        WHEN r_percent_rank <= 0.75 then 2
        ELSE 1 END r_tier,
   CASE WHEN f_percent_rank <= 0.25 then 4
        WHEN f_percent_rank <= 0.5 then 3
        WHEN f_percent_rank <= 0.75 then 2
        ELSE 1 END f_tier,
   CASE WHEN m_percent_rank <= 0.25 then 4
        WHEN m_percent_rank <= 0.5 then 3
        WHEN m_percent_rank <= 0.75 then 2
        ELSE 1 END m_tier
   FROM rfm_percent
 )
, score_table AS (
   SELECT customer_id
   ,CONCAT(r_tier, f_tier, m_tier) as score
   FROM tier_table)
, label_table AS (
   SELECT *
   ,(CASE
         WHEN score = '111' THEN 'Best customers'
         WHEN score LIKE '[34][34][1-4]' THEN 'Lost Bad Customers'
         WHEN score LIKE '[34]2[1-4]' THEN 'Lost Customers'
         WHEN score LIKE '21[1-4]' THEN 'Almost lost'
         WHEN score LIKE '11[2-4]' THEN 'Loyal customers'
         WHEN score LIKE '[12][1-3]1' THEN 'Big Spender'
         WHEN score LIKE '[12]4[1-4]' THEN 'New customers'
         WHEN score LIKE '[34]1[1-4]' THEN 'Hibernating'
         WHEN score LIKE '[12][23][2-4]' THEN 'Potential Loyalist'
      END
   ) AS label
   FROM score_table)
SELECT label
,COUNT(customer_id) number_of_customers
FROM label_table
GROUP BY label
ORDER BY number_of_customers
