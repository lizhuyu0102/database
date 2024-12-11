USE ECONTEAM;
SELECT * FROM dbo.Customer;
SELECT * FROM dbo.Product;
SELECT * FROM Supplier;
SELECT * FROM Warehouse;
SELECT * FROM SupplierWarehouse;
SELECT * FROM CustomerAddress;
SELECT * FROM Coupon;
SELECT * FROM CouponCustomer;
select * from dbo.[Order];
SELECT * FROM OrderItem;
SELECT * FROM Payment;
SELECT * FROM Inventory;
SELECT * FROM [Return];
SELECT * FROM Shipment;
SELECT * FROM ShoppingCartItem;



--View1 monitor the performance of coupons
--CHECK THE USE OF ALL COUPON
SELECT * FROM vw_CouponUsageAnalysis;

--Check the usage of specific coupons
SELECT * 
FROM vw_CouponUsageAnalysis
WHERE CouponCode = 'FALL25';

--To check the usage of coupons within a specific time frame:
SELECT * 
FROM vw_CouponUsageAnalysis
WHERE StartDate >= '2024-07-01' AND EndDate <= '2024-12-31';


---View 2. Monitor products with inventory levels at or below the replenishment threshold
---Check if there are any products below the reorder level.
SELECT * FROM vw_ProductsBelowReorderLevel;

