CREATE DATABASE Superstore_DWH;
USE Superstore_DWH;

--
UPDATE Staging_Superstore
SET 
    Sales = ROUND(Sales, 4),
    Discount = ROUND(Discount, 2),
    Profit = ROUND(Profit, 4);

-- Detect Warning Issue

select * from Staging_Superstore
 where Profit = null;

 SELECT 
    Row_ID, 
    Order_ID, 
    Sales, 
    Quantity, 
    Discount,
    Profit,
    (Sales / (1 - Discount) / Quantity) AS Unit_Original_Price,
    (Sales - Profit) / Quantity AS Unit_Cost
FROM Staging_Superstore
WHERE Product_ID = 'FUR-TA-10004289';

 --- Profit = Sales - Cost -> 721.875 - (6*190.3125) = -420

UPDATE Staging_Superstore
SET Profit = -420
WHERE Row_ID = 7345;

 ---
 select top 5* from Staging_Superstore;

 select count(distinct Customer_ID) As cst_id,
		count(distinct Customer_Name) As Cst_name,
		count(distinct Product_ID) as Products_id ,
		count(distinct Product_Name) as ProductsNames
  from Staging_Superstore;
 
 -- Detect ProductID Issue

 select Product_ID,
 count(Product_Name) as Products_Related,
 string_AGG( Product_Name , ' | ') as products
 
 from(
 Select distinct Product_ID ,Product_Name
 from Staging_Superstore) As DistinctProducts

 group by Product_ID
 having count(distinct Product_Name) >1;

 ---

 select Product_Name,
 count(Product_ID) as Related_IDs,
 STRING_AGG(Product_ID, '|') as IDs
 from(
 select distinct Product_ID, Product_Name
 from Staging_Superstore) AS DistinctProducts

 group by Product_Name
 having count(Product_ID)>1;

 ---
create OR ALTER VIEW Location_Dim as
	with distinct_location as(
		select distinct Region , City , State
			from Staging_Superstore)
	select 
	ROW_NUMBER() over (order BY Region, State, City) As Location_Key,
	Region , City , State
	from distinct_location;

select count(*) from Location_Dim;

---
create view Customers_Dim as
	select distinct Customer_ID , Customer_Name , Segment
	from Staging_Superstore;

select count(*) from Customers_Dim

---

create view Products_Dim as
	with distinct_products as(
		select distinct Product_ID , Product_Name , Category, Sub_Category
			from Staging_Superstore)
	select 
	ROW_NUMBER() over(order by Product_ID , Product_Name) As Product_Key,
	Product_ID , Product_Name , Category, Sub_Category
	from distinct_products;

	select count(*) from Products_Dim;
---
CREATE or alter VIEW Fact_Orders AS
SELECT 
    fact.Row_ID,
    fact.Order_ID,
    fact.Order_Date,
    fact.Ship_Date,
    fact.Ship_Mode,
    fact.Customer_ID,
    products.Product_Key,
    loc.Location_Key,
    fact.Sales,
    fact.Quantity,
    fact.Discount,
    fact.Profit,
   
    (Sales - Profit) AS COGS,
    CASE 
        WHEN Discount < 1 THEN Sales / (1 - Discount) 
        ELSE Sales 
    END AS Original_Price,
    datediff(day , Order_Date , Ship_Date) as Shipping_Days

FROM Staging_Superstore fact
INNER JOIN Products_Dim products 
    ON fact.Product_ID = products.Product_ID AND fact.Product_Name = products.Product_Name
INNER JOIN Location_Dim loc
    ON fact.Region = loc.Region AND fact.State = loc.State AND fact.City = loc.City;


  -- Fix Dates Isuue
  USE Superstore_DWH;
WITH FixedDates AS (
    SELECT
        CASE 
            WHEN DAY(Order_Date) <= 12 
            THEN DATEFROMPARTS(YEAR(Order_Date), DAY(Order_Date), MONTH(Order_Date))
            ELSE Order_Date 
        END AS New_Order_Date,
        CASE 
            WHEN DAY(Ship_Date) <= 12 
            THEN DATEFROMPARTS(YEAR(Ship_Date), DAY(Ship_Date), MONTH(Ship_Date))
            ELSE Ship_Date 
        END AS New_Ship_Date
    FROM Staging_Superstore
)
SELECT
    MIN(DATEDIFF(day, New_Order_Date, New_Ship_Date)) AS Min_Shipping_Days,
    MAX(DATEDIFF(day, New_Order_Date, New_Ship_Date)) AS Max_Shipping_Days,
    SUM(CASE WHEN New_Ship_Date < New_Order_Date THEN 1 ELSE 0 END) AS Negative_Rows
FROM FixedDates;

----
UPDATE Staging_Superstore
SET 
    Order_Date = CASE 
                    WHEN DAY(Order_Date) <= 12 
                    THEN DATEFROMPARTS(YEAR(Order_Date), DAY(Order_Date), MONTH(Order_Date))
                    ELSE Order_Date 
                 END,
    Ship_Date  = CASE 
                    WHEN DAY(Ship_Date) <= 12 
                    THEN DATEFROMPARTS(YEAR(Ship_Date), DAY(Ship_Date), MONTH(Ship_Date))
                    ELSE Ship_Date 
                 END;

select top 15* from Fact_Orders;
select * from Fact_Orders where Shipping_Days<0;
  ---
CREATE OR ALTER VIEW Date_Dim AS
WITH DateRange AS (
    SELECT 
        DATEFROMPARTS(YEAR(MIN(CAST(Order_Date AS DATE))), 1, 1) AS StartDate,
        DATEFROMPARTS(YEAR(MAX(CAST(Order_Date AS DATE))), 12, 31) AS EndDate
    FROM Staging_Superstore
),
Numbers AS (
    SELECT TOP 4096 
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
),
Calendar AS (
    SELECT DATEADD(day, n, StartDate) AS DateValue
    FROM DateRange
    CROSS JOIN Numbers
    WHERE DATEADD(day, n, StartDate) <= EndDate
)
SELECT 
    DateValue AS Date_Key,
    YEAR(DateValue) AS [Year],
    MONTH(DateValue) AS [Month_No],
    DATENAME(month, DateValue) AS [Month_Name],
    DATEPART(quarter, DateValue) AS [Quarter],
    DATENAME(weekday, DateValue) AS [Day_Name],
    DAY(DateValue) AS [Day]
FROM Calendar;

SELECT MIN(Date_Key) AS MinDate, MAX(Date_Key) AS MaxDate FROM Date_Dim;

SELECT TOP 5 State, SUM(Profit) AS Total_Profit
FROM Staging_Superstore
GROUP BY State
ORDER BY Total_Profit DESC;