#Step 1: Create the database and a staging table
CREATE DATABASE retail_segmentation;

CREATE TABLE stg_online_retail (
	InvoiceNo VARCHAR(20),
    StockCode VARCHAR(20),
    Description VARCHAR(255),
    Quantity VARCHAR(20),
    InvoiceDate VARCHAR(30),
    UnitPrice VARCHAR(20),
    CustomerID VARCHAR(20),
    Country VARCHAR(50)
);

#Step 2: Import the CSV (Table data import wizard)
SELECT COUNT(*) FROM stg_online_retail;
SELECT COUNT(DISTINCT InvoiceNo) FROM stg_online_retail;   

#Step 3: Convert to proper data types

CREATE TABLE online_retail AS
SELECT
  InvoiceNo,
  StockCode,
  NULLIF(TRIM(Description), '')                 AS Description,
  CAST(Quantity AS SIGNED)                      AS Quantity,
  STR_TO_DATE(InvoiceDate, '%d/%m/%Y %H:%i')    AS InvoiceDate,
  CAST(UnitPrice AS DECIMAL(10,3))              AS UnitPrice,
  CAST(NULLIF(CustomerID, '') AS DECIMAL(10,0)) AS CustomerID,
  Country
FROM stg_online_retail;

#Check:
SELECT MIN(InvoiceDate), MAX(InvoiceDate), SUM(InvoiceDate IS NULL) AS null_dates
FROM online_retail;

#Step 4: Audit the data quality

USE retail_segmentation;

-- 1. Missing CustomerID: how many rows, and how much revenue?
SELECT COUNT(*) AS total_rows,
	SUM(CustomerID IS NULL) AS null_customer_rows,
    ROUND(100*SUM(CustomerID IS NULL)/COUNT(*), 1) AS pct_rows,
    ROUND(100*SUM(CASE WHEN CustomerID IS NULL THEN Quantity*UnitPrice END)
				/SUM(Quantity*UnitPrice),1) AS pct_revenue
	FROM online_retail;
    
-- 2. Cancellations (invoice numbers starting with C)
SELECT COUNT(*) FROM online_retail WHERE InvoiceNo LIKE 'C%';

-- 3. Zero or negative quantity / price
SELECT SUM(Quantity <= 0) AS bad_qty, SUM(UnitPrice <= 0) AS bad_price
FROM online_retail;

-- 4. Non-product codes (postage, fees, manual adjustments...)
SELECT StockCode, Description, COUNT(*) AS n
FROM online_retail
WHERE StockCode NOT REGEXP '^[0-9]{5}'
GROUP BY StockCode, Description
ORDER BY n DESC;

-- 5. Exact duplicate rows
SELECT COUNT(*) - 
		(SELECT COUNT(*) FROM (SELECT DISTINCT * FROM online_retail) d)
		AS duplicate_rows
FROM online_retail;

#Step 5: Build the clean table

CREATE TABLE clean_sales AS
SELECT distinct
	InvoiceNo, StockCode, Description, Quantity, InvoiceDate,UnitPrice, CustomerID, Country,
    ROUND (Quantity*UnitPrice, 2) AS line_total
FROM online_retail
WHERE CustomerID IS NOT NULL
	AND InvoiceNo NOT LIKE 'C%'        #exclude cancellations
    AND Quantity > 0
    AND UnitPrice > 0
    AND StockCode regexp '^[0-9]{5}';  #real products only
    

SELECT COUNT(*) AS rows_kept,
	COUNT(distinct CustomerID) AS customers,
    COUNT(distinct InvoiceNo) AS orders,
    ROUND(SUM(line_total)) AS revenue
FROM clean_sales;

#Step 6: Calculate RFM

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

#Step 7: Explore the business (2 quick queries)

-- Monthly revenue trend
SELECT DATE_FORMAT(InvoiceDate, '%Y-%m') AS month,
       ROUND(SUM(line_total)) AS revenue,
       COUNT(DISTINCT CustomerID) AS customers
FROM clean_sales
GROUP BY month ORDER BY month;

-- Do the top 20% of customers drive most of the revenue?
WITH cust AS (
  SELECT CustomerID, SUM(line_total) AS revenue
  FROM clean_sales GROUP BY CustomerID
), ranked AS (
  SELECT *, NTILE(5) OVER (ORDER BY revenue DESC) AS quintile FROM cust
)
SELECT quintile,
       COUNT(*) AS customers,
       ROUND(SUM(revenue)) AS revenue,
       ROUND(100 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS pct_of_revenue
FROM ranked GROUP BY quintile ORDER BY quintile;

SELECT COUNT(*) FROM rfm