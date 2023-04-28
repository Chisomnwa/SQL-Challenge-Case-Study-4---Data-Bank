-- C. Data Allocation Challenge

/*
For this multi-part challenge question - you have been requested to generate the following data elements to
help the Data Bank team estimate how much data will need to be provisioned for each option:
*/


/*1. running customer balance column that includes impact of each transaction

Steps:
* Calculate the running balance for each customer based on the order of their transaction.

* Adjust the 'txn_amount' to be negative for withdrawal and purchase transactions to reflect a negative balance.
*/

SELECT customer_id,
	   txn_date,
	   txn_type,
	   txn_amount,
	   SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount
				WHEN txn_type = 'withdrawal' THEN -txn_amount
				WHEN txn_type = 'purchase' THEN -txn_amount
				ELSE 0
			END) OVER(PARTITION BY customer_id ORDER BY txn_date) AS running_balance
FROM customer_transactions;


/*
2. customer balance at the end of each month

Steps:
* Calculate the closing balance for each customer for each month

* Adjust the 'txn_amount' to be negative for withdrawal and purchase transactions to reflect a negative balance
*/

SELECT customer_id,
	   DATEPART(MONTH, txn_date) AS month,
	   DATENAME(MONTH, txn_date) AS month_name,
	   SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount
				WHEN txn_type = 'withdrawal' THEN -txn_amount
				WHEN txn_type = 'purchase' THEN -txn_amount
				ELSE 0
			END) AS closing_balance
FROM customer_transactions
GROUP BY customer_id, DATEPART(MONTH, txn_date), DATENAME(MONTH, txn_date);


/*
3. minimum, average and maximum values of the running balance for each customer

Steps:
* Use a CTE to find the running balance of each customer based on the order of transaction

* Then calculate the minimum, maximum, and average balance for each customer.
*/

WITH running_balance AS
(
	SELECT customer_id,
		   txn_date,
		   txn_type,
		   txn_amount,
		   SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount
					WHEN txn_type = 'withdrawal' THEN -txn_amount
					WHEN txn_type = 'purchase' THEN -txn_amount
					ELSE 0
				END) OVER(PARTITION BY customer_id ORDER BY txn_date) AS running_balance
	FROM customer_transactions
)

SELECT customer_id,
	   AVG(running_balance) AS avg_running_balance,
	   MIN(running_balance) AS min_running_balance,
	   MAX(running_balance) AS max_running_balance
FROM running_balance
GROUP BY customer_id;


/* Now based on the provided three options, we will use each of the above calculated data elements to calculate
how much data would have been required for each data allocation option on a monthly basis*/

/*
For option 1: data is allocated based off the amount of money at the end of the previous month
How much data would have been required on a monthly basis?

Steps:
* Use a CTE to calculate the net transaction amount for each customer for each transaction and for each customer

* Use a second CTE to calculate the running customer balance of each customer, this time using the ROWS BETWEEN
THE UNBOUNDED PRECEDING AND CURRENT ROW clause to define the range of the rows that the SUM function should
consider for each. In this case it includes all the rows from the start of the partition up to and including
the current row.

* Use a third CTE to calculate the month end balance for each customer

* Use the final query to calculate the data required per month by summing up the monthly ending balances for
each customer
*/

WITH transaction_amt_cte AS
(
	SELECT customer_id,
		   txn_date,
		   MONTH(txn_date) AS txn_month,
		   txn_type,
		   CASE WHEN txn_type = 'deposit' THEN txn_amount 
				ELSE -txn_amount 
		   END AS net_transaction_amt
	FROM customer_transactions
),

running_customer_balance_cte AS
(
	SELECT customer_id,
		   txn_date,
		   txn_month,
		   net_transaction_amt,
		   SUM(net_transaction_amt) OVER(PARTITION BY customer_id, txn_month ORDER BY txn_date
		   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_customer_balance
	FROM transaction_amt_cte
),

customer_end_month_balance_cte AS
(
	SELECT customer_id,
		   txn_month,
		   MAX(running_customer_balance) AS month_end_balance
	FROM running_customer_balance_cte
	GROUP BY customer_id, txn_month
)

SELECT txn_month,
	   SUM(month_end_balance) AS data_required_per_month
FROM customer_end_month_balance_cte
GROUP BY txn_month
ORDER BY data_required_per_month DESC;

-- Insights:

/*
* January requires more monthly data allocation (366,801) followed by March (144,015), and February (132,426),
with April (51,003) requiring the least amount of data.

* This actually means that data allocation that would be required per month varies across different months.

* This insight suggests that the amount of data required by customers is directly related to their transaction 
activities, and specifically to their end-of-month balances. This indicates that customers with higher balances 
tend to require more data than those with lower balances.

* In other words, customers tend to do have higher end month balances in January and March than in Frebruary and April
so more data should be should be allocated for January, followed by March, February and April.

* This insight generated would help predict customer behaviour, optimizing business strategies and managing costs.
*/


/*
For Option 2: data is allocated on the average amount of money kept in the account in the previous 30 days
How much data would have been required on a monthly  basis?

Steps:
* Use transaction_amt_cte CTE to calculate the net transaction amount for each customer in each month.

* Use running_customer_balance_cte CTE to calculate the running balance for each customer in each momth, 
based on the net transaction amount

* Use avg_running_customer_balance CTE to calculate the average running customer balance for ecah customer
across all months.

* In the final query, join the running_customer_balance and avg_running_customer_balance tables on the customer_id
column, group the data by month, and calculate the rounded sum of the average running customer balance as
data_required_per_month.

This gives an estimate of how much data would be required for option 2 on a monthly basis.
*/

WITH transaction_amt_cte AS
(
	SELECT customer_id,
		   MONTH(txn_date) AS txn_month,
		   SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount
					ELSE -txn_amount
				END) AS net_transaction_amt
	FROM customer_transactions
	GROUP BY customer_id, MONTH(txn_date)
	--ORDER BY customer_id
),

running_customer_balance_cte AS
(
	SELECT customer_id,
		   txn_month,
		   net_transaction_amt,
		   SUM(net_transaction_amt) OVER(PARTITION BY customer_id ORDER BY txn_month) AS running_customer_balance
	FROM transaction_amt_cte
),

avg_running_customer_balance AS
(
	SELECT customer_id,
		   AVG(running_customer_balance) AS avg_running_customer_balance
	FROM running_customer_balance_cte
	GROUP BY customer_id
)

SELECT txn_month,
	   ROUND(SUM(avg_running_customer_balance), 0) AS data_required_per_month
FROM running_customer_balance_cte r
JOIN avg_running_customer_balance a
ON r.customer_id = a.customer_id
GROUP BY txn_month
ORDER BY data_required_per_month;

-- Insights:

/*
* Based on our query output, the average running customer balance is negative for all four months,indicating 
that customers tend to withdraw more money than they deposit on average.

* The data required for February and March are higher than for January and April, suggesting that more data should
be allocated for those two months.

* These negative running balances, could impact the bank's overall financial health. Therefore, I recommend that 
the bank collect more data for February and March to better understand customer behavior during those months and
potentially identify any trends or anomalies that could impact the bank's business.
*/


/*
For option 3: data is updated real-time.
How much data would have been required on a monthly basis?

Steps:
* Use transaction_amt_cte CTE to calculate the net transaction amount for each customer for each month.

* Use running_customer_cte CTE to calculate the running balance for each customer by summing up the net transaction amounts over time(months).

* Use the final query to calculate the estimated data required per month for option 3, assuming that each byte of data requires one unit of storage.
*/

WITH transaction_amt_cte AS
(
	SELECT customer_id,
		   txn_date,
		   txn_month = MONTH(txn_date),
		   txn_type,
		   txn_amount,
		   net_transaction_amt = CASE WHEN txn_type = 'deposit' THEN txn_amount ELSE -txn_amount END
	FROM customer_transactions
),

running_customer_balance_cte AS
(
	SELECT customer_id,
		   txn_month,
		   running_customer_balance = SUM(net_transaction_amt) OVER (PARTITION BY customer_id ORDER BY txn_month)
	FROM transaction_amt_cte
)

SELECT txn_month,
	   SUM(running_customer_balance) AS data_required_per_month
FROM running_customer_balance_cte
GROUP BY txn_month
ORDER BY data_required_per_month;

-- Insights:

/*
* The data required for the month of March is significantly higher than for the other months. This shows that
there were more transactions happening in March than in the other months.

* The data required for January is positive, indicating that there might be some customers who have a higher
balance at the beginning of the year.
*/



