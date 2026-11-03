SELECT CustomerID, InvoiceNo, Description, Quantity, UnitPrice,
       ROUND(-Quantity * UnitPrice) AS cancelled_value
FROM online_retail
WHERE InvoiceNo LIKE 'C%' AND CustomerID IS NOT NULL
ORDER BY cancelled_value DESC
LIMIT 10;

SELECT InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice,
       ROUND(Quantity * UnitPrice, 2) AS line_total
FROM online_retail
WHERE CustomerID = 15098
ORDER BY InvoiceDate;

RENAME TABLE clean_sales TO clean_sales_v1;
RENAME TABLE rfm TO rfm_v1;

CREATE INDEX idx_cust_stock ON online_retail (CustomerID, StockCode);

-- Rule 1: cancelled in full (same customer, product and quantity)
DROP TABLE IF EXISTS cancelled_pairs;
CREATE TABLE cancelled_pairs AS
SELECT DISTINCT o.InvoiceNo, o.StockCode
FROM online_retail o
JOIN online_retail c
  ON  c.CustomerID = o.CustomerID
  AND c.StockCode  = o.StockCode
  AND c.InvoiceNo LIKE 'C%'
  AND c.Quantity   = -o.Quantity
  AND c.InvoiceDate >= o.InvoiceDate
WHERE o.InvoiceNo NOT LIKE 'C%';

-- Rule 2: cancelled via a "Manual" credit of exactly the same value (large lines only)
INSERT INTO cancelled_pairs
SELECT DISTINCT o.InvoiceNo, o.StockCode
FROM online_retail o
JOIN online_retail c
  ON  c.CustomerID  = o.CustomerID
  AND c.InvoiceNo LIKE 'C%'
  AND c.Description = 'Manual'
  AND c.InvoiceDate >= o.InvoiceDate
  AND ROUND(-c.Quantity * c.UnitPrice, 2) = ROUND(o.Quantity * o.UnitPrice, 2)
WHERE o.InvoiceNo NOT LIKE 'C%'
  AND o.Quantity * o.UnitPrice >= 1000;

-- Rebuild clean_sales without the cancelled lines
CREATE TABLE clean_sales AS
SELECT DISTINCT o.InvoiceNo, o.StockCode, o.Description, o.Quantity,
       o.InvoiceDate, o.UnitPrice, o.CustomerID, o.Country,
       ROUND(o.Quantity * o.UnitPrice, 2) AS line_total
FROM online_retail o
LEFT JOIN cancelled_pairs p
  ON p.InvoiceNo = o.InvoiceNo AND p.StockCode = o.StockCode
WHERE p.InvoiceNo IS NULL
  AND o.CustomerID IS NOT NULL
  AND o.InvoiceNo NOT LIKE 'C%'
  AND o.Quantity > 0 AND o.UnitPrice > 0
  AND o.StockCode REGEXP '^[0-9]{5}';
  
SELECT COUNT(*) AS lines_flagged FROM cancelled_pairs;

SELECT COUNT(DISTINCT CustomerID) AS customers, ROUND(SUM(line_total)) AS revenue
FROM clean_sales;

SELECT ROUND((SELECT SUM(line_total) FROM clean_sales_v1)
           - (SELECT SUM(line_total) FROM clean_sales)) AS revenue_removed;

SELECT COUNT(*) FROM clean_sales WHERE CustomerID = 12346;     -- should be 0
SELECT COUNT(*) FROM clean_sales WHERE InvoiceNo = '556444';   -- should be 0

SET @snapshot = (SELECT DATE_ADD(MAX(DATE(InvoiceDate)), INTERVAL 1 DAY)
				FROM clean_sales);

CREATE TABLE rfm AS
SELECT
	CustomerID,
    DATEDIFF(@snapshot, MAX(DATE(InvoiceDate))) AS recency_days,
    COUNT(distinct InvoiceNo) AS frequency,
    ROUND(SUM(line_total),2) AS monetary
FROM clean_sales
GROUP BY CustomerID;

SELECT COUNT(*), MIN(recency_days), MAX(recency_days),
       MIN(frequency), MAX(frequency),
       MIN(monetary), ROUND(AVG(monetary)), MAX(monetary)
FROM rfm;

SELECT * FROM rfm;