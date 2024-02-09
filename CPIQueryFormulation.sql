--  BASE QUERIES --
-- Location/Sales class summary for job quantity and amount (revenue/costs)
SELECT l.location_id, l.location_name, s.sales_class_id, s.sales_class_desc, tim.time_year, tim.time_month, s.base_price,
       SUM(j.quantity_ordered) AS SumQuantityOrdered,
	   SUM(j.quantity_ordered*unit_price) AS SumJobAmount
FROM w_job_f AS j, w_location_d AS l, w_sales_class_d AS s, w_time_d AS tim
WHERE j.location_id = l.location_id
  AND j.sales_class_id = s.sales_class_id
  AND j.contract_date = tim.time_id
GROUP BY l.location_id, l.location_name, s.sales_class_id, s.sales_class_desc, tim.time_year, tim.time_month, s.base_price
ORDER BY l.location_id, l.location_name, s.sales_class_id, s.sales_class_desc, tim.time_year, tim.time_month, s.base_price;

-- Location invoice revenue summary (revenue/costs)
WITH CTE_LocationInvoiceRevenueSummary AS    
(SELECT j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month, 
	   SUM(i.invoice_amount) AS SumInvoiceAmount,
	   SUM(i.invoice_quantity) AS SumInvoiceQuantity
FROM w_job_f AS j, w_sub_job_f As sj, w_job_shipment_f AS sh, w_invoiceline_f AS i, w_time_d AS tim, w_location_d AS l
WHERE j.job_id = sj.job_id 
       AND sj.sub_job_id = sh.sub_job_id 
       AND sh.invoice_id = i.invoice_id
	   AND j.contract_date = tim.time_id
	   AND j.location_id = l.location_id
GROUP BY j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month
ORDER BY j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month)

SELECT * FROM CTE_LocationInvoiceRevenueSummary;

-- Location subjob cost summary(revenue/costs)
WITH CTE_LocationSubjobCostSummary AS
(SELECT j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month,
	  SUM(sj.cost_labor) AS SumLaborCost,
	  SUM(sj.cost_material) AS SumMaterialCost,
	  SUM(sj.machine_hours * m.rate_per_hour) AS SumMachineCost,
	  SUM(sj.cost_overhead) AS SumOverheadCost,
	  SUM(sj.cost_labor+sj.cost_material+(sj.machine_hours * m.rate_per_hour)+sj.cost_overhead) AS SumTotalCost,
	  SUM(quantity_produced) AS SumQtyProduced,
      SUM(sj.cost_labor+sj.cost_material+(sj.machine_hours * m.rate_per_hour)+sj.cost_overhead)/SUM(quantity_produced) AS UnitPrice
FROM  w_job_f AS j, w_sub_job_f AS sj,  w_time_d AS tim, w_location_d AS l, w_machine_type_d AS m
WHERE j.job_id = sj.job_id
	  AND j.contract_date = tim.time_id
	  AND j.location_id = l.location_id 
	  AND sj.machine_type_id = m.machine_type_id
GROUP BY j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month
ORDER BY j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month)
	  
SELECT * FROM CTE_LocationSubjobCostSummary;

-- Returns by location and sales class (quality control)
SELECT l.location_id, l.location_name, s.sales_class_id, s.sales_class_desc, tim.time_year, tim.time_month,
      SUM(quantity_shipped - invoice_quantity) AS SumQuantityReturned,
	  SUM((quantity_shipped - invoice_quantity) * invoice_amount/invoice_quantity) AS SumReturnedAmount
FROM w_invoiceline_f AS i, w_sales_class_d AS s, w_time_d AS tim, w_location_d AS l	  
WHERE i.location_id = l.location_id
	  AND i.sales_class_id = s.sales_class_id
	  AND i.invoice_sent_date = tim.time_id
GROUP BY l.location_id, l.location_name, s.sales_class_id, s.sales_class_desc, tim.time_year, tim.time_month
HAVING SUM(quantity_shipped - invoice_quantity) > 0
ORDER BY l.location_id, l.location_name, s.sales_class_id, s.sales_class_desc, tim.time_year, tim.time_month;

-- Last shipment delays involving date promised (quality control)
WITH MaxShipDates AS ( 
SELECT sj.job_id,
       MAX(js.actual_ship_date)   AS Last_Shipment_Date,
       SUM(js.actual_quantity ) AS SumDelayShipQty
FROM w_job_shipment_f AS js, w_sub_job_f AS sj, w_job_f as j
WHERE sj.sub_job_id = js.sub_job_id
       AND j.job_id = sj.job_id
       AND js.actual_ship_date > j.date_promised
GROUP BY sj.job_id ),
TimeWorkDays AS (
SELECT Time_Id, ROW_NUMBER() OVER (ORDER BY TIME_ID ASC) AS Workday 
   FROM w_time_d ),
DelayedJobsPromiseDateCTE AS(
SELECT j.job_id, l.location_id, l.location_name,s.sales_class_id, s.sales_class_desc,j.date_promised,ms.last_shipment_date,
	   j.quantity_ordered,ms.SumDelayShipQty, twd2.workday - twd1.workday AS busdaydiff
FROM w_job_f AS j, w_sales_class_d AS s, w_location_d AS l, MaxShipDates AS ms, TimeWorkDays AS twd1 , TimeWorkDays AS twd2
WHERE j.location_id = l.location_id
  AND j.sales_class_id = s.sales_class_id
  AND j.job_id = ms.job_id
  AND j.date_promised = twd1.time_id
  AND ms.last_shipment_date = twd2.time_id)
  
SELECT * FROM DelayedJobsPromiseDateCTE;

-- First shipment delays involving shipped by date (quality control)
WITH FirstShipDates AS
( SELECT sj.job_id, MIN(js.actual_ship_date) as FirstShipDate
   FROM w_job_shipment_f AS js, w_sub_job_f AS sj
   WHERE sj.sub_job_id = js.sub_job_id
   GROUP BY sj.job_id
 ),
 TimeWorkDays AS (
SELECT time_id, ROW_NUMBER() OVER (ORDER BY time_id ASC) AS Workday 
   FROM w_time_d ),
DelayedJobsCTE AS(
SELECT j.job_id, l.location_id, l.location_name,s.sales_class_id, s.sales_class_desc,j.date_ship_by, 
       fs.firstshipdate, twd2.workday - twd1.workday AS busdaydiff
FROM w_job_f AS j, w_sales_class_d AS s, w_location_d AS l, FirstShipDates AS fs, TimeWorkDays AS twd1 , TimeWorkDays AS twd2	
WHERE j.job_id = fs.job_id
  AND j.sales_class_id = s.sales_class_id
  AND j.location_id = l.location_id
  AND j.date_ship_by = twd1.time_id
  AND fs.firstshipdate = twd2.time_id
  AND fs.firstshipdate > j.date_ship_by)
  
SELECT * FROM DelayedJobsCTE;

--  ANALYTICAL QUERIES --
-- Cumulative amount for locations
SELECT location_name, time_year, time_month, SUM(quantity_ordered * unit_price), SUM(SUM(quantity_ordered * unit_price)) OVER
	    (PARTITION BY location_name, time_year ORDER BY  time_month
		ROWS UNBOUNDED PRECEDING ) AS CumAmt  FROM
(SELECT l.location_name, tim.time_year, tim.time_month,
       j.quantity_ordered,  j.unit_price
FROM w_job_f AS j JOIN w_location_d AS l ON j.location_id = l.location_id JOIN w_time_d AS tim ON
j.contract_date = tim.time_id)d
GROUP BY location_name, time_year, time_month;

-- Moving average of average amount ordered for locations
SELECT l.location_name, tim.time_year, tim.time_month,
       AVG(j.quantity_ordered*j.unit_price) AS AvgJobAmount, 
	   AVG(AVG(j.quantity_ordered*j.unit_price)) OVER
	    (PARTITION BY l.location_name ORDER BY tim.time_year, tim.time_month
		ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS MovAvgAvgAmt
FROM w_job_f AS j, w_location_d AS l, w_time_d AS tim
WHERE j.location_id = l.location_id
  AND j.contract_date = tim.time_id
GROUP BY l.location_name, tim.time_year, tim.time_month;


-- Rank locations by descending sum of annual profit
WITH CTE_LocationInvoiceRevenueSummary AS    
(SELECT j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month, 
	   SUM(i.invoice_amount) AS SumInvoiceAmount,
	   SUM(i.invoice_quantity) AS SumInvoiceQuantity
FROM w_job_f AS j, w_sub_job_f As sj, w_job_shipment_f AS sh, w_invoiceline_f AS i, w_time_d AS tim, w_location_d AS l
WHERE j.job_id = sj.job_id 
       AND sj.sub_job_id = sh.sub_job_id 
       AND sh.invoice_id = i.invoice_id
	   AND j.contract_date = tim.time_id
	   AND j.location_id = l.location_id
GROUP BY j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month
ORDER BY j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month),
CTE_LocationSubjobCostSummary AS
(SELECT j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month,
	  SUM(sj.cost_labor) AS SumLaborCost,
	  SUM(sj.cost_material) AS SumMaterialCost,
	  SUM(sj.machine_hours * m.rate_per_hour) AS SumMachineCost,
	  SUM(sj.cost_overhead) AS SumOverheadCost,
	  SUM(sj.cost_labor+sj.cost_material+(sj.machine_hours * m.rate_per_hour)+sj.cost_overhead) AS SumTotalCost,
	  SUM(quantity_produced) AS SumQtyProduced,
      SUM(sj.cost_labor+sj.cost_material+(sj.machine_hours * m.rate_per_hour)+sj.cost_overhead)/SUM(quantity_produced) AS UnitPrice
FROM  w_job_f AS j, w_sub_job_f AS sj,  w_time_d AS tim, w_location_d AS l, w_machine_type_d AS m
WHERE j.job_id = sj.job_id
	  AND j.contract_date = tim.time_id
	  AND j.location_id = l.location_id 
	  AND sj.machine_type_id = m.machine_type_id
GROUP BY j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month
ORDER BY j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month)

SELECT p.location_name,p.time_year,
	   SUM(p.suminvoiceamount - c.sumtotalcost) AS AnnualProfit,
	   RANK () OVER (PARTITION BY p.time_year ORDER BY SUM(p.suminvoiceamount - c.sumtotalcost) DESC ) AS AnnualProfitRank
FROM CTE_LocationSubjobCostSummary AS c, CTE_LocationInvoiceRevenueSummary AS p
WHERE p.job_id = c.job_id
GROUP BY p.location_name,p.time_year;

-- Rank locations by descending annual profit margin
WITH CTE_LocationInvoiceRevenueSummary AS    
(SELECT j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month, 
	   SUM(i.invoice_amount) AS SumInvoiceAmount,
	   SUM(i.invoice_quantity) AS SumInvoiceQuantity
FROM w_job_f AS j, w_sub_job_f As sj, w_job_shipment_f AS sh, w_invoiceline_f AS i, w_time_d AS tim, w_location_d AS l
WHERE j.job_id = sj.job_id 
       AND sj.sub_job_id = sh.sub_job_id 
       AND sh.invoice_id = i.invoice_id
	   AND j.contract_date = tim.time_id
	   AND j.location_id = l.location_id
GROUP BY j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month
ORDER BY j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month),
CTE_LocationSubjobCostSummary AS
(SELECT j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month,
	  SUM(sj.cost_labor) AS SumLaborCost,
	  SUM(sj.cost_material) AS SumMaterialCost,
	  SUM(sj.machine_hours * m.rate_per_hour) AS SumMachineCost,
	  SUM(sj.cost_overhead) AS SumOverheadCost,
	  SUM(sj.cost_labor+sj.cost_material+(sj.machine_hours * m.rate_per_hour)+sj.cost_overhead) AS SumTotalCost,
	  SUM(quantity_produced) AS SumQtyProduced,
      SUM(sj.cost_labor+sj.cost_material+(sj.machine_hours * m.rate_per_hour)+sj.cost_overhead)/SUM(quantity_produced) AS UnitPrice
FROM  w_job_f AS j, w_sub_job_f AS sj,  w_time_d AS tim, w_location_d AS l, w_machine_type_d AS m
WHERE j.job_id = sj.job_id
	  AND j.contract_date = tim.time_id
	  AND j.location_id = l.location_id 
	  AND sj.machine_type_id = m.machine_type_id
GROUP BY j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month
ORDER BY j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month)
	   
SELECT p.location_name, p.time_year,
	   SUM(p.suminvoiceamount - c.sumtotalcost)/SUM(p.suminvoiceamount) AS ProfitMargin,
	   RANK () OVER (PARTITION BY p.time_year 
					 ORDER BY  SUM(p.suminvoiceamount - c.sumtotalcost)/SUM(p.suminvoiceamount)  DESC ) AS ProfitMarginRank
FROM CTE_LocationSubjobCostSummary AS c, CTE_LocationInvoiceRevenueSummary AS p
Where p.job_id = c.job_id
GROUP BY p.location_name, p.time_year;

-- Percent rank of job profit margins for locations
WITH CTE_LocationInvoiceRevenueSummary AS    
(SELECT j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month, 
	   SUM(i.invoice_amount) AS SumInvoiceAmount,
	   SUM(i.invoice_quantity) AS SumInvoiceQuantity
FROM w_job_f AS j, w_sub_job_f As sj, w_job_shipment_f AS sh, w_invoiceline_f AS i, w_time_d AS tim, w_location_d AS l
WHERE j.job_id = sj.job_id 
       AND sj.sub_job_id = sh.sub_job_id 
       AND sh.invoice_id = i.invoice_id
	   AND j.contract_date = tim.time_id
	   AND j.location_id = l.location_id
GROUP BY j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month
ORDER BY j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month),
CTE_LocationSubjobCostSummary AS
(SELECT j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month,
	  SUM(sj.cost_labor) AS SumLaborCost,
	  SUM(sj.cost_material) AS SumMaterialCost,
	  SUM(sj.machine_hours * m.rate_per_hour) AS SumMachineCost,
	  SUM(sj.cost_overhead) AS SumOverheadCost,
	  SUM(sj.cost_labor+sj.cost_material+(sj.machine_hours * m.rate_per_hour)+sj.cost_overhead) AS SumTotalCost,
	  SUM(quantity_produced) AS SumQtyProduced,
      SUM(sj.cost_labor+sj.cost_material+(sj.machine_hours * m.rate_per_hour)+sj.cost_overhead)/SUM(quantity_produced) AS UnitPrice
FROM  w_job_f AS j, w_sub_job_f AS sj,  w_time_d AS tim, w_location_d AS l, w_machine_type_d AS m
WHERE j.job_id = sj.job_id
	  AND j.contract_date = tim.time_id
	  AND j.location_id = l.location_id 
	  AND sj.machine_type_id = m.machine_type_id
GROUP BY j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month
ORDER BY j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month)

SELECT c.job_id,c.location_name, c.time_year,c.time_month,
	   SUM(p.suminvoiceamount - c.sumtotalcost)/SUM(p.suminvoiceamount) AS ProfitMargin,
	   PERCENT_RANK() OVER (ORDER BY  SUM(p.suminvoiceamount - c.sumtotalcost)/SUM(p.suminvoiceamount) DESC) AS ProfitMarginPercentRank
FROM  CTE_LocationSubjobCostSummary AS c, CTE_LocationInvoiceRevenueSummary AS p
Where p.job_id = c.job_id
GROUP BY c.job_id,c.location_name, c.time_year,c.time_month;

-- Top performers of percent rank of job profit margins for locations
WITH CTE_LocationInvoiceRevenueSummary AS    
(SELECT j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month, 
	   SUM(i.invoice_amount) AS SumInvoiceAmount,
	   SUM(i.invoice_quantity) AS SumInvoiceQuantity
FROM w_job_f AS j, w_sub_job_f As sj, w_job_shipment_f AS sh, w_invoiceline_f AS i, w_time_d AS tim, w_location_d AS l
WHERE j.job_id = sj.job_id 
       AND sj.sub_job_id = sh.sub_job_id 
       AND sh.invoice_id = i.invoice_id
	   AND j.contract_date = tim.time_id
	   AND j.location_id = l.location_id
GROUP BY j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month
ORDER BY j.job_id, l.location_id, l.location_name, j.unit_price, j.quantity_ordered, tim.time_year, tim.time_month),
CTE_LocationSubjobCostSummary AS
(SELECT j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month,
	  SUM(sj.cost_labor) AS SumLaborCost,
	  SUM(sj.cost_material) AS SumMaterialCost,
	  SUM(sj.machine_hours * m.rate_per_hour) AS SumMachineCost,
	  SUM(sj.cost_overhead) AS SumOverheadCost,
	  SUM(sj.cost_labor+sj.cost_material+(sj.machine_hours * m.rate_per_hour)+sj.cost_overhead) AS SumTotalCost,
	  SUM(quantity_produced) AS SumQtyProduced,
      SUM(sj.cost_labor+sj.cost_material+(sj.machine_hours * m.rate_per_hour)+sj.cost_overhead)/SUM(quantity_produced) AS UnitPrice
FROM  w_job_f AS j, w_sub_job_f AS sj,  w_time_d AS tim, w_location_d AS l, w_machine_type_d AS m
WHERE j.job_id = sj.job_id
	  AND j.contract_date = tim.time_id
	  AND j.location_id = l.location_id 
	  AND sj.machine_type_id = m.machine_type_id
GROUP BY j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month
ORDER BY j.job_id, l.location_id, l.location_name,tim.time_year,tim.time_month),
PercentRankJobProfitMargin AS
(SELECT c.job_id,c.location_name, c.time_year,c.time_month,
	   SUM(p.suminvoiceamount - c.sumtotalcost)/SUM(p.suminvoiceamount) AS ProfitMargin,
	   PERCENT_RANK() OVER (ORDER BY  SUM(p.suminvoiceamount - c.sumtotalcost)/SUM(p.suminvoiceamount)  DESC ) AS ProfitMarginPercentRank
FROM  CTE_LocationSubjobCostSummary AS c, CTE_LocationInvoiceRevenueSummary AS p
Where p.job_id = c.job_id
GROUP BY c.job_id,c.location_name, c.time_year,c.time_month)

SELECT job_id,location_name,time_year, time_month, profitmargin, ProfitMarginPercentRank
FROM PercentRankJobProfitMargin
WHERE ProfitMarginPercentRank <= 0.05;

-- Rank sales class by return quantities for each year
SELECT s.sales_class_desc, tim.time_year,
      SUM(quantity_shipped - invoice_quantity) AS SumQuantityReturned,
	  RANK () OVER (PARTITION BY tim.time_year ORDER BY SUM(quantity_shipped - invoice_quantity) DESC) AS ReturnedQtySalesClassRank
FROM w_invoiceline_f AS i, w_sales_class_d AS s, w_time_d AS tim  
WHERE i.sales_class_id = s.sales_class_id
	  AND i.invoice_sent_date = tim.time_id
GROUP BY s.sales_class_desc, tim.time_year
HAVING SUM(quantity_shipped - invoice_quantity) > 0;

-- Ratio to report of return quantities for sales classes by year 
SELECT s.sales_class_desc, tim.time_year,
      SUM(quantity_shipped - invoice_quantity) AS SumQuantityReturned,
	  SUM(quantity_shipped - invoice_quantity)/SUM(SUM(quantity_shipped - invoice_quantity)) 
	  	OVER (PARTITION BY tim.time_year) AS ReturnedQtySalesClassRatio
FROM w_invoiceline_f AS i, w_sales_class_d AS s, w_time_d AS tim  
WHERE i.sales_class_id = s.sales_class_id
	  AND i.invoice_sent_date = tim.time_id
GROUP BY s.sales_class_desc, tim.time_year
HAVING SUM(quantity_shipped - invoice_quantity) > 0
ORDER BY tim.time_year,SUM(quantity_shipped - invoice_quantity);

-- Rank locations by sum of business days delayed for the job shipped by date (first shipment)
WITH FirstShipDates AS
( SELECT sj.job_id, MIN(js.actual_ship_date) as FirstShipDate
   FROM w_job_shipment_f AS js, w_sub_job_f AS sj
   WHERE sj.sub_job_id = js.sub_job_id
   GROUP BY sj.job_id
 ),
 TimeWorkDays AS (
SELECT time_id, ROW_NUMBER() OVER (ORDER BY time_id ASC) AS Workday 
   FROM w_time_d ),
DelayedJobsCTE AS(
SELECT j.job_id, l.location_id, l.location_name,s.sales_class_id, s.sales_class_desc,j.date_ship_by, 
       fs.firstshipdate, twd2.workday - twd1.workday AS busdaydiff
FROM w_job_f AS j, w_sales_class_d AS s, w_location_d AS l, FirstShipDates AS fs, TimeWorkDays AS twd1 , TimeWorkDays AS twd2	
WHERE j.job_id = fs.job_id
  AND j.sales_class_id = s.sales_class_id
  AND j.location_id = l.location_id
  AND j.date_ship_by = twd1.time_id
  AND fs.firstshipdate = twd2.time_id
  AND fs.firstshipdate > j.date_ship_by)
  
 SELECT d.location_name,tim.time_year,
 		SUM(d.busdaydiff) AS SumBusdayDiff,
		RANK () OVER(PARTITION BY tim.time_year ORDER BY SUM(d.busdaydiff) DESC) AS LocRankBusDayDiff,
 		DENSE_RANK () OVER(PARTITION BY tim.time_year ORDER BY SUM(d.busdaydiff) DESC) AS LocDenseRankBusDayDiff
 FROM DelayedJobsCTE as d, w_time_d as tim
 WHERE d.date_ship_by = tim.time_id
 GROUP BY d.location_name,tim.time_year ;

-- Rank locations by delay percentage for jobs delayed on the last shipment date
WITH MaxShipDates AS ( 
SELECT sj.job_id,
       MAX(js.actual_ship_date)   AS Last_Shipment_Date,
       SUM(js.actual_quantity ) AS SumDelayShipQty
FROM w_job_shipment_f AS js, w_sub_job_f AS sj, w_job_f as j
WHERE sj.sub_job_id = js.sub_job_id
       AND j.job_id = sj.job_id
       AND js.actual_ship_date > j.date_promised
GROUP BY sj.job_id ),
TimeWorkDays AS (
SELECT Time_Id, ROW_NUMBER() OVER (ORDER BY TIME_ID ASC) AS Workday 
   FROM w_time_d ),
DelayedJobsPromiseDateCTE AS(
SELECT j.job_id, l.location_id, l.location_name,s.sales_class_id, s.sales_class_desc,j.date_promised,ms.last_shipment_date,
	   j.quantity_ordered,ms.SumDelayShipQty, twd2.workday - twd1.workday AS busdaydiff
FROM w_job_f AS j, w_sales_class_d AS s, w_location_d AS l, MaxShipDates AS ms, TimeWorkDays AS twd1 , TimeWorkDays AS twd2
WHERE j.location_id = l.location_id
  AND j.sales_class_id = s.sales_class_id
  AND j.job_id = ms.job_id
  AND j.date_promised = twd1.time_id
  AND ms.last_shipment_date = twd2.time_id)
  
SELECT djp.location_name,tim.time_year,
	   COUNT(djp.job_id) AS DelayedJobCount,
	   SUM(djp.busdaydiff) AS SumBusDayDiff,
	   SUM(j.quantity_ordered - djp.SumDelayShipQty)/SUM(j.quantity_ordered) AS OnTimeRate,
	   RANK () OVER (PARTITION BY tim.time_year 
					 ORDER BY SUM(j.quantity_ordered - djp.SumDelayShipQty)/SUM(j.quantity_ordered) DESC) AS rank_num
FROM DelayedJobsPromiseDateCTE as djp, w_time_d as tim, w_job_f as j
WHERE djp.job_id = j.job_id
	  AND djp.date_promised = tim.time_id
GROUP BY djp.location_name,tim.time_year;


