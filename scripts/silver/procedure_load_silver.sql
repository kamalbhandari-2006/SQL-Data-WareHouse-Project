/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to 
    populate the 'silver' schema tables from the 'bronze' schema.
	Actions Performed:
		- Truncates Silver tables.
		- Inserts transformed and cleansed data from Bronze into Silver tables.
		
Parameters:
    None. 
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC Silver.load_silver;
===============================================================================
*/

CREATE OR ALTER PROCEDURE silver.load_silver AS
	BEGIN
		BEGIN TRY
			DECLARE @start_time DATETIME,@end_time DATETIME,@batch_start_time DATETIME,@batch_end_time DATETIME;
			SET @batch_start_time = GETDATE();
			PRINT'===========================================';
			PRINT'Loading Silver Layer';
			PRINT'===========================================';
			PRINT'-------------------------------------------';
			PRINT'Loading CRM Tables';
			PRINT'-------------------------------------------';
			SET @start_time = GETDATE();
			PRINT'>>Truncating Tables: silver.crm_cust_info';
			TRUNCATE TABLE silver.crm_cust_info;

			PRINT'>> Inserting Data Into: silver.crm_cust_info';

		--Table 1 crm_cust_info
		--INSERT CLEAN AND TRANSFORMED DATA INTO RESPECTIVE TABLE
			INSERT INTO silver.crm_cust_info (
				cst_id,
				cst_key,
				cst_firstname,
				cst_lastname,
				cst_marital_status,
				cst_gndr,
				cst_create_date)

			SELECT
				--Below TRIM() Is Used To Remove Unwanted Space From String Value Columns
				cst_id,
				cst_key,
				TRIM(cst_firstname),
				TRIM(cst_lastname),

					--CASE STAEMENTS Are Used To Convert Abrreviated Values Into Full Forms For Clarity In Final Reports
				CASE
					WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
					WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
					ELSE 'n/a'
				END AS cst_marital_status,
				CASE
					WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
					WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
					ELSE 'n/a'
				END AS cst_gndr,
				cst_create_date
			FROM 
				--Below Subquery Remove Duplicates and NULL values
				(SELECT
					*,
					ROW_NUMBER()OVER(PARTITION BY cst_id ORDER BY cst_create_date) AS row_rank
				FROM bronze.crm_cust_info
				WHERE 
					cst_id IS NOT NULL
				)T
			WHERE 
				row_rank  = 1
			SET @end_time = GETDATE();
			PRINT '>> Load Duration: ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + ' seconds';
			PRINT '------------------';

			SET @start_time = GETDATE();
			PRINT'>>Truncating Tables: silver.crm_prd_info';
			TRUNCATE TABLE silver.crm_prd_info;

			PRINT'>>Inserting Data Into: silver.crm_prd_info';

			-- Table 2 crm_prd_info(Below Due Tocleaning Data And Transforming WE added New Cols Updated existing COLUMNS So It Is MUST To Update Table Accordingly)

			--INSERTION
			INSERT INTO silver.crm_prd_info(
				prd_id ,
				cat_id ,
				prd_key ,
				prd_nm ,
				prd_cost ,
				prd_line ,
				prd_start_dt ,
				prd_end_dt)

			SELECT
				-- No NULL ID Here And No Duplicate
				prd_id,

				-- Dividing Prd_key In TWO PARTS As Those Part Are Required Separately To JOIN This Table With Two Diff Tables(And More Changes Neded TO Be Done To Make Those Keys Identical)
				REPLACE(SUBSTRING(prd_key,1,5),'-','_') AS cat_id,
				SUBSTRING(prd_key,7,LEN(prd_key)) AS prd_key,

				-- No Unwanted Space Here
				prd_nm,

				-- Handling NULL values Use ISNULL OR COALESCE 
				ISNULL(prd_cost,0) AS prd_cost,

				--CASE STAEMENTS Are Used To Convert Abrreviated Values Into Full Forms For Clarity In Final Reports
				CASE UPPER(TRIM(prd_line))
					WHEN 'M' THEN 'Mountain'
					WHEN 'R' THEN 'Road'
					WHEN 'S' THEN 'Other Sales'
					WHEN 'T' THEN 'Touring'
					ELSE 'n/a'
				END AS prd_line,

				CAST(prd_start_dt AS DATE) AS prd_start_dt,
				-- Updating End Date As It is Greater Then Start Date Which Is CORRUPTED INFO 
				CAST(LEAD(prd_start_dt) OVER( PARTITION BY prd_key ORDER BY prd_start_dt)-1 AS DATE) AS prd_end_dt
			FROM
				bronze.crm_prd_info

			SET @end_time = GETDATE();
			PRINT '>> Load Duration: ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + ' seconds';
			PRINT '------------------';

			SET @start_time = GETDATE();
			PRINT'>>Truncating Tables: silver.crm_sales_details';
			TRUNCATE TABLE silver.crm_sales_details;

			PRINT'>>Inserting Data Into: silver.crm_sales_details';

			--Table 3
			INSERT INTO silver.crm_sales_details(
				sls_ord_num ,
				sls_prd_key ,
				sls_cust_id ,
				sls_order_dt ,
				sls_ship_dt ,
				sls_due_dt ,
				sls_sales ,
				sls_quantity ,
				sls_price)

			SELECT 
				-- No Trailing Or Leading Space
				sls_ord_num ,

				--No NULLS  And DUPLICATE
				sls_prd_key ,
				sls_cust_id ,

				--Handling Invalid Date (No Issues With DateOrder)
				CASE WHEN (LEN(sls_order_dt) != 8) THEN NULL
					ELSE CAST(CAST(sls_order_dt AS varchar)AS DATE)
				END AS sls_order_dt,
				CASE WHEN (LEN(sls_ship_dt) != 8) THEN NULL
					ELSE CAST(CAST(sls_ship_dt AS varchar)AS DATE)
					END AS sls_ship_dt,
				CASE WHEN (LEN(sls_due_dt) != 8) THEN NULL
					ELSE CAST(CAST(sls_due_dt AS varchar)AS DATE)
					END AS sls_due_dt,

				--Business RULE Always Sales = Quantity * Price IF not Then Make it
				CASE WHEN  sls_sales IS NULL OR  sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)
					 THEN sls_quantity * ABS(sls_price)
					 ELSE sls_sales
				END AS sls_sales,

				sls_quantity ,

				CASE WHEN sls_price IS NULL  OR sls_price <= 0
					 THEN sls_sales/NULLIF (sls_quantity,0)
					 ELSE sls_price 
				END AS sls_price
			FROM bronze.crm_sales_details

			SET @end_time = GETDATE();
			PRINT '>> Load Duration: ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + ' seconds';
			PRINT '------------------';

			PRINT'-------------------------------------------';
			PRINT'Loading ERP Tables';
			PRINT'-------------------------------------------';

			SET @start_time = GETDATE();
			PRINT'>>Truncating Tables: silver.erp_cust_az12';
			TRUNCATE TABLE silver.erp_cust_az12;

			PRINT'>>Inserting Data Into: silver.erp_cust_az12';

		--Table 4
			INSERT INTO silver.erp_cust_az12(
				cid,
				bdate,
				gen)

			SELECT
				-- To Enable cid To JOIN With Another Table We Need To Modify Our Col AS Below(Specifically Removing 'STARTING THREE LETTERS')
				CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(UPPER(cid),4,LEN(cid))
					 ELSE cid
				END AS cid,

				-- SET Future BirthDate To NULL
				CASE WHEN bdate > GETDATE() THEN NULL 
					 ELSE bdate
				END AS bdate,

				--Data Standardization,Normalization And Handled NULL Values
				CASE WHEN UPPER(TRIM(gen)) IN  ('F','FEMALE') THEN 'FEMALE'
					 WHEN UPPER(TRIM(gen)) IN ('M','MALE') THEN 'MALE'
					 ELSE 'n/a'
				END AS gen

			FROM bronze.erp_cust_az12

			SET @end_time = GETDATE();
			PRINT '>> Load Duration: ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + ' seconds';
			PRINT '------------------';

			SET @start_time = GETDATE();
			PRINT'>>Truncating Tables: silver.erp_loc_a101';
			TRUNCATE TABLE silver.erp_loc_a101;

			PRINT'>>Inserting Data Into: silver.erp_loc_a101';

			-- Table 5
			INSERT INTO silver.erp_loc_a101
			(	cid,
				cntry
			)

			SELECT 
				-- To Enable cid To JOIN With Another Table We Need To Modify Our Col AS Below(Specifically Removing '-' FROM COLUMN)
				REPLACE(cid,'-','') cid,

				-- Data Standarization,Normalization Handling NULLS ,EMPTY STRINGS.
				CASE WHEN TRIM(cntry) = 'DE' THEN 'Germany'
					 WHEN  TRIM(cntry)  IN('US' , 'USA') THEN 'United States'
					 WHEN TRIM(cntry) = '' OR cntry IS NULL  THEN 'n/a'
				ELSE TRIM(cntry)
				END AS cntry
			FROM bronze.erp_loc_a101

			SET @end_time = GETDATE();
			PRINT '>> Load Duration: ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + ' seconds';
			PRINT '------------------';

			SET @start_time = GETDATE();
			PRINT'>>Truncating Tables: silver.erp_px_cat_g1v2';
			TRUNCATE TABLE silver.erp_px_cat_g1v2;

			PRINT'>>Inserting Data Into: silver.erp_px_cat_g1v2';

			-- Table 6
			INSERT INTO silver.erp_px_cat_g1v2
			(	id,
				cat,
				subcat,
				maintenance	
			)

		 -- NOTHING TO TRANSFORM/ UPDATE OR CLEAN AS TABLE IS CLEAN ALREADY
			SELECT
				id,
				cat,
				subcat,
				maintenance
			FROM bronze.erp_px_cat_g1v2
			SET @end_time = GETDATE();
			PRINT '>> Load Duration: ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + ' seconds';
			PRINT '------------------';
		
			SET @batch_end_time = GETDATE();
			PRINT'=========================================';
			PRINT'Loading silver Layer Is completed';
			PRINT'	- Total Load Duration: '+ CAST(DATEDIFF(second,@batch_start_time,@batch_end_time) AS NVARCHAR) + ' seconds';
			PRINT'=========================================';
		END TRY

		BEGIN CATCH
			PRINT'===============================================';
			PRINT'ERROR OCCURED DURING LOADING SILVER LAYER';
			PRINT'Error Message' + ERROR_MESSAGE();
			PRINT'Error Message' + CAST(ERROR_NUMBER() AS NVARCHAR);
			PRINT'Error Message' + CAST(ERROR_STATE() AS NVARCHAR);
			PRINT'===============================================';
	
	  END CATCH
END;
