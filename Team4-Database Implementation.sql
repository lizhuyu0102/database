CREATE DATABASE ECONTEAM;

USE ECONTEAM;


--Column Data Encryption
--- Create DMK
CREATE MASTER KEY
ENCRYPTION BY PASSWORD = 'Test_P@sswOrd';

--- Create certificate to protect symmetric key
CREATE CERTIFICATE TestCertificate
WITH SUBJECT = 'AdventureWorks Test Certificate',
EXPIRY_DATE = '2026-10-31';

--- Create symmetric key to encrypt data
CREATE SYMMETRIC KEY TestSymmetricKey
WITH ALGORITHM = AES_128
ENCRYPTION BY CERTIFICATE TestCertificate;

--- Open symmetric key
OPEN SYMMETRIC KEY TestSymmetricKey
DECRYPTION BY CERTIFICATE TestCertificate;



-- Create table
--- Use VARBINARY as the data type for the encrypted column
CREATE TABLE dbo.Customer
(
    CustomerID INT IDENTITY NOT NULL PRIMARY KEY,  
    Username VARCHAR(50) NOT NULL,        
    EncryptedPassword VARBINARY(250),        
    Email VARCHAR(100) NOT NULL,   -- Emails should be unique       
    Phone NVARCHAR(20) NOT NULL,   -- Supports international numbers
    Birthday DATE                         
);

CREATE TABLE dbo.Product
(
    ProductID INT IDENTITY NOT NULL PRIMARY KEY,
    Name VARCHAR(50) NOT NULL,
    Description VARCHAR(250) NOT NULL,    
    Price MONEY NOT NULL CHECK (Price > 0), 
	StockQuantity INT		-- use trigger to automatically calculate				
);

CREATE TABLE dbo.ShoppingCartItem
(
    CustomerID INT NOT NULL REFERENCES dbo.Customer(CustomerID) ON DELETE CASCADE,
    ProductID INT NOT NULL REFERENCES dbo.Product(ProductID),
    Quantity INT NOT NULL CHECK (Quantity > 0), 
    CONSTRAINT PKSCI PRIMARY KEY CLUSTERED (CustomerID, ProductID)
);

CREATE TABLE dbo.CustomerAddress
(
    AddressID INT IDENTITY NOT NULL PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES dbo.Customer(CustomerID) ON DELETE CASCADE,
    StreetAddress VARCHAR(400) NOT NULL,
    City VARCHAR(50) NOT NULL,
    State VARCHAR(50) NOT NULL,
    PostalCode INT NOT NULL,
    RecipientPhone NVARCHAR(20) NOT NULL,
    RecipientName VARCHAR(50) NOT NULL
);

CREATE TABLE dbo.Coupon
(
    CouponID INT IDENTITY NOT NULL PRIMARY KEY,
    CouponCode VARCHAR(50) NOT NULL UNIQUE,
    DiscountAmount MONEY, 
    DiscountPercentage DECIMAL(5, 2),
    MinimumPurchaseAmount MONEY,
    StartDate DATETIME NOT NULL,
    EndDate DATETIME NOT NULL,
    UsageLimit INT 
);

CREATE TABLE dbo.CouponCustomer
(
    CouponCustomerID INT IDENTITY NOT NULL PRIMARY KEY,
    CouponID INT NOT NULL 
		REFERENCES dbo.Coupon(CouponID) ON DELETE CASCADE,
    CustomerID INT NOT NULL 
		REFERENCES dbo.Customer(CustomerID) ON DELETE CASCADE,
    UsageDate DATETIME, 
    DiscountApplied MONEY,	-- use trigger to automatically calculate
    UsageStatus VARCHAR(20) CHECK (UsageStatus IN ('Active', 'Used', 'Expired'))
);


CREATE TABLE dbo.[Order]
(
    OrderID INT IDENTITY NOT NULL PRIMARY KEY,                            
    CouponCustomerID INT NULL 
		REFERENCES dbo.CouponCustomer(CouponCustomerID), 
    CustomerID INT NOT NULL 
		REFERENCES dbo.Customer(CustomerID) ON DELETE CASCADE, 
    TotalAmount MONEY,		 -- use trigger to automatically calculate
    OrderDate DATETIME DEFAULT CURRENT_TIMESTAMP                         
);

-- add unique constraint?to ensure the unique of NON NULL  CouponCustomerID
CREATE UNIQUE INDEX IDX_UQ_CouponCustomerID ON dbo.[Order](CouponCustomerID)
WHERE CouponCustomerID IS NOT NULL;



CREATE TABLE dbo.OrderItem
(
    OrderItemID INT IDENTITY NOT NULL PRIMARY KEY,
    OrderID INT NOT NULL 
		REFERENCES dbo.[Order](OrderID) ON DELETE CASCADE,
    ProductID INT NOT NULL 
		REFERENCES dbo.Product(ProductID),
    Quantity INT NOT NULL CHECK (Quantity > 0),
    Amount MONEY		-- use trigger to automatically calculate
);

CREATE TABLE dbo.Payment
(
    PaymentID INT IDENTITY NOT NULL PRIMARY KEY,
    OrderID INT NOT NULL REFERENCES dbo.[Order](OrderID),
    ActualPaidAmount MONEY CHECK (ActualPaidAmount >= 0),
    PaymentMethod VARCHAR(20),
    PaymentDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    PaymentStatus VARCHAR(20) 
		CHECK (PaymentStatus IN ('Finished', 'NOT YET'))
);

CREATE TABLE dbo.Warehouse
(
    WarehouseID INT IDENTITY NOT NULL PRIMARY KEY,
    Location VARCHAR(50) NOT NULL,
    WarehouseName VARCHAR(50) NOT NULL,
    Capacity INT CHECK (Capacity >= 0),
    ManagerName VARCHAR(50) NOT NULL,
    Phone NVARCHAR(20) NOT NULL
);

CREATE TABLE dbo.[Return]
(
    ReturnID INT IDENTITY NOT NULL PRIMARY KEY,
    OrderItemID INT NOT NULL REFERENCES dbo.OrderItem(OrderItemID),
    CustomerID INT NOT NULL REFERENCES dbo.Customer(CustomerID),
    WarehouseID INT NOT NULL REFERENCES dbo.Warehouse(WarehouseID),
    ReturnDate DATETIME,
    ReturnReason VARCHAR(400),
    RefundAmount MONEY CHECK (RefundAmount >= 0),
    QuantityReturned INT NOT NULL CHECK (QuantityReturned > 0),
    ReturnStatus VARCHAR(20) CHECK (ReturnStatus IN ('Finished', 'NOT YET'))
);

CREATE TABLE dbo.Supplier
(
    SupplierID INT IDENTITY NOT NULL PRIMARY KEY,
    Name VARCHAR(50) NOT NULL,
    Phone NVARCHAR(20) NOT NULL,
    Email VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE dbo.SupplierWarehouse 
(
    SupplierID INT NOT NULL REFERENCES dbo.Supplier(SupplierID) ON DELETE CASCADE,
    WarehouseID INT NOT NULL REFERENCES dbo.Warehouse(WarehouseID) ON DELETE CASCADE,
    SupplyFrequency VARCHAR(50) NOT NULL,
    CONSTRAINT PKSW PRIMARY KEY CLUSTERED (SupplierID, WarehouseID)
);

CREATE TABLE dbo.Inventory
(
    InventoryID INT IDENTITY NOT NULL PRIMARY KEY,
    ProductID INT NOT NULL REFERENCES dbo.Product(ProductID),
    WarehouseID INT NOT NULL REFERENCES dbo.Warehouse(WarehouseID),
    QuantityInStock INT CHECK (QuantityInStock >= 0),
    ReorderLevel INT CHECK (ReorderLevel >= 0)
);

CREATE TABLE dbo.Shipment
(
    ShipmentID INT IDENTITY NOT NULL PRIMARY KEY,
    AddressID INT NOT NULL REFERENCES dbo.CustomerAddress(AddressID),
    WarehouseID INT NOT NULL REFERENCES dbo.Warehouse(WarehouseID),
    OrderItemID INT NOT NULL REFERENCES dbo.OrderItem(OrderItemID),
    TrackingNumber VARCHAR(50),
    Carrier VARCHAR(50) NOT NULL,
    ShipmentDate DATETIME,
    DeliveryDate DATETIME,
    ShipmentStatus VARCHAR(20) CHECK (ShipmentStatus IN ('Confirm', 'Packaged', 'Shipping', 'Delivery'))
);
GO


--Computed Columns based on a function
--- Product's StockQuantity trigger
CREATE TRIGGER trg_UpdateStockQuantity
ON dbo.Inventory
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Product
    SET StockQuantity = 
        (
            SELECT ISNULL(SUM(QuantityInStock), 0)
            FROM dbo.Inventory
            WHERE ProductID = P.ProductID
        )
    FROM dbo.Product P
    INNER JOIN 
        (SELECT DISTINCT ProductID FROM INSERTED
         UNION 
         SELECT DISTINCT ProductID FROM DELETED) AS ChangedProducts
    ON P.ProductID = ChangedProducts.ProductID;
END;
GO

---OrderItem's Amount trigger
CREATE TRIGGER trg_CalculateOrderItemAmount
ON dbo.OrderItem
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE OI
    SET OI.Amount = OI.Quantity * P.Price
    FROM dbo.OrderItem OI
    INNER JOIN dbo.Product P
    ON OI.ProductID = P.ProductID
    WHERE OI.OrderItemID IN (SELECT OrderItemID FROM INSERTED);
END;
GO

---Order's TotalAmount trigger
CREATE TRIGGER trg_UpdateOrderTotalAmount
ON dbo.OrderItem
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE O
    SET O.TotalAmount = 
        (
            SELECT ISNULL(SUM(OI.Amount), 0)
            FROM dbo.OrderItem OI
            WHERE OI.OrderID = O.OrderID
        )
    FROM dbo.[Order] O
    WHERE O.OrderID IN 
        (
            SELECT DISTINCT OrderID 
            FROM INSERTED
            UNION 
            SELECT DISTINCT OrderID 
            FROM DELETED
        );
END;
GO


---Calculate the Discount Applied
CREATE TRIGGER trg_CalculateDiscountApplied
ON dbo.CouponCustomer
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE CC
    SET DiscountApplied = 
        CASE 
            --IF we use Fixed Amount Discount Coupon
            WHEN C.DiscountAmount IS NOT NULL THEN C.DiscountAmount
            --IF we usePercentage Discount Coupon
            WHEN C.DiscountPercentage IS NOT NULL THEN 
                ISNULL((C.DiscountPercentage / 100.0) * O.TotalAmount, 0)
            ELSE 0
        END
    FROM dbo.CouponCustomer CC
    INNER JOIN dbo.Coupon C
        ON CC.CouponID = C.CouponID
    LEFT JOIN dbo.[Order] O
        ON CC.CouponCustomerID = O.CouponCustomerID
    WHERE CC.CouponCustomerID IN (SELECT CouponCustomerID FROM INSERTED);
END;
GO

---dynamically Update Coupon UsageDate
CREATE TRIGGER trg_UpdateCouponUsageDate
ON dbo.[Order]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE CC
    SET UsageDate = O.OrderDate
    FROM dbo.CouponCustomer CC
    INNER JOIN INSERTED I
        ON CC.CouponCustomerID = I.CouponCustomerID
    INNER JOIN dbo.[Order] O
        ON O.OrderID = I.OrderID;
END;
GO

--- automatically calculate the Actual Paid Amount
CREATE TRIGGER trg_CalculateActualPaidAmount
ON dbo.Payment
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE P
    SET ActualPaidAmount = 
        ISNULL(O.TotalAmount, 0) - ISNULL(CC.DiscountApplied, 0)
    FROM dbo.Payment P
    INNER JOIN dbo.[Order] O
        ON P.OrderID = O.OrderID
    LEFT JOIN dbo.CouponCustomer CC
        ON O.CouponCustomerID = CC.CouponCustomerID
    WHERE P.PaymentID IN (SELECT PaymentID FROM INSERTED);
END;
GO


--Table-level CHECK Constraints based on a function
CREATE FUNCTION dbo.CheckTotalAmountConstraint (@OrderID INT)
RETURNS BIT
AS
BEGIN
    DECLARE @Result BIT = 0;
    DECLARE @CouponID INT;
    DECLARE @MinimumPurchaseAmount MONEY;
    DECLARE @TotalAmount MONEY;

    -- get related CouponID and TotalAmount
    SELECT 
        @CouponID = c.CouponID,
        @TotalAmount = o.TotalAmount
    FROM dbo.[Order] o
    LEFT JOIN dbo.CouponCustomer cc ON o.CouponCustomerID = cc.CouponCustomerID
    LEFT JOIN dbo.Coupon c ON cc.CouponID = c.CouponID
    WHERE o.OrderID = @OrderID;

    -- If we donot have CouponID?the cinstraint will not work
    IF @CouponID IS NULL OR @TotalAmount IS NULL
    BEGIN
        SET @Result = 1; -- if not use coupon
    END
    ELSE
    BEGIN
        -- get MinimumPurchaseAmount
        SELECT @MinimumPurchaseAmount = MinimumPurchaseAmount
        FROM dbo.Coupon
        WHERE CouponID = @CouponID;

        -- check TotalAmount>= MinimumPurchaseAmount
        IF @TotalAmount >= @MinimumPurchaseAmount
        BEGIN
            SET @Result = 1; -- pass
        END
    END

    RETURN @Result;
END;
GO

ALTER TABLE dbo.[Order]
ADD CONSTRAINT CHK_TotalAmount_MinimumPurchaseAmount
CHECK (dbo.CheckTotalAmountConstraint(OrderID) = 1);


-- Customer
INSERT INTO dbo.Customer (Username, EncryptedPassword, Email, Phone, Birthday) VALUES
('jsmith2024', CONVERT(VARBINARY, 'hx7#kP9$v'), 'john.smith@email.com', '555-0101', '1990-03-15'),
('emma_wilson', CONVERT(VARBINARY, 'pL2$mN8*q'), 'emma.w@email.com', '555-0102', '1988-07-22'),
('michael_davis', CONVERT(VARBINARY, 'rT5#bV9$n'), 'm.davis@email.com', '555-0103', '1995-11-30'),
('sarah_brown', CONVERT(VARBINARY, 'kJ4$hM7#w'), 'sarahb@email.com', '555-0104', '1992-04-18'),
('david_taylor', CONVERT(VARBINARY, 'wQ8#nP3$x'), 'd.taylor@email.com', '555-0105', '1987-09-25'),
('lisa_anderson', CONVERT(VARBINARY, 'yH6$cR5#m'), 'l.anderson@email.com', '555-0106', '1993-01-12'),
('robert_martin', CONVERT(VARBINARY, 'uB9#fL4$k'), 'r.martin@email.com', '555-0107', '1985-06-28'),
('jennifer_white', CONVERT(VARBINARY, 'iM3$tG7#p'), 'j.white@email.com', '555-0108', '1991-12-05'),
('william_clark', CONVERT(VARBINARY, 'aS5#jK8$n'), 'w.clark@email.com', '555-0109', '1989-08-17'),
('emily_harris', CONVERT(VARBINARY, 'oL7$wD4#h'), 'e.harris@email.com', '555-0110', '1994-02-23'),
('thomas_lee', CONVERT(VARBINARY, 'xC6#mB9$r'), 't.lee@email.com', '555-0111', '1986-10-09'),
('amanda_king', CONVERT(VARBINARY, 'qP4$nF5#t'), 'a.king@email.com', '555-0112', '1993-05-14'),
('james_wright', CONVERT(VARBINARY, 'zM8#hJ3$w'), 'j.wright@email.com', '555-0113', '1990-07-31'),
('olivia_scott', CONVERT(VARBINARY, 'bK5$rT7#m'), 'o.scott@email.com', '555-0114', '1988-03-26'),
('daniel_green', CONVERT(VARBINARY, 'vH9#cL4$p'), 'd.green@email.com', '555-0115', '1992-09-08'),
('sophia_baker', CONVERT(VARBINARY, 'eR6$xM8#k'), 's.baker@email.com', '555-0116', '1987-12-19'),
('ryan_adams', CONVERT(VARBINARY, 'tN4#wP7$j'), 'r.adams@email.com', '555-0117', '1995-04-03'),
('nicole_hill', CONVERT(VARBINARY, 'gB8$fK3#h'), 'n.hill@email.com', '555-0118', '1991-08-27'),
('kevin_ross', CONVERT(VARBINARY, 'yL5#mS6$v'), 'k.ross@email.com', '555-0119', '1989-01-15'),
('laura_cooper', CONVERT(VARBINARY, 'cT7$bH4#n'), 'l.cooper@email.com', '555-0120', '1993-06-21'),
('brian_morgan', CONVERT(VARBINARY, 'uP3#jR8$w'), 'b.morgan@email.com', '555-0121', '1986-11-04'),
('rachel_phillips', CONVERT(VARBINARY, 'mK6$xF5#q'), 'r.phillips@email.com', '555-0122', '1994-03-30'),
('steven_torres', CONVERT(VARBINARY, 'hG9#nL7$t'), 's.torres@email.com', '555-0123', '1990-10-12'),
('michelle_gray', CONVERT(VARBINARY, 'wD4$cM8#k'), 'm.gray@email.com', '555-0124', '1988-05-28'),
('patrick_ward', CONVERT(VARBINARY, 'aR7#pJ3$v'), 'p.ward@email.com', '555-0125', '1992-12-09'),
('kelly_foster', CONVERT(VARBINARY, 'sB5$hT6#m'), 'k.foster@email.com', '555-0126', '1987-04-15'),
('christopher_price', CONVERT(VARBINARY, 'zL8#wK4$n'), 'c.price@email.com', '555-0127', '1995-07-22'),
('angela_butler', CONVERT(VARBINARY, 'qM3$fR7#h'), 'a.butler@email.com', '555-0128', '1991-02-06'),
('brandon_barnes', CONVERT(VARBINARY, 'xP6#cG5$t'), 'b.barnes@email.com', '555-0129', '1989-09-18'),
('rebecca_fisher', CONVERT(VARBINARY, 'vT4#mH8$w'), 'r.fisher@email.com', '555-0130', '1993-11-25');
GO



-- Product
INSERT INTO dbo.Product (Name, Description, Price) VALUES
('Wireless Earbuds', 'Premium Bluetooth 5.0 earbuds with noise cancellation', 99.99),
('Smart Watch', 'Fitness tracking smartwatch with heart rate monitor', 149.99),
('Phone Case', 'Shock-resistant phone case for iPhone 13', 29.99),
('Laptop Backpack', 'Water-resistant laptop backpack with USB charging port', 79.99),
('Power Bank', '20000mAh portable charger with fast charging', 49.99),
('Gaming Mouse', 'RGB gaming mouse with programmable buttons', 69.99),
('Mechanical Keyboard', 'RGB mechanical keyboard with blue switches', 129.99),
('Monitor Stand', 'Adjustable monitor stand with cable management', 39.99),
('Webcam', '1080p webcam with built-in microphone', 59.99),
('USB Hub', '7-port USB 3.0 hub with power adapter', 44.99),
('Tablet Stand', 'Adjustable tablet/iPad stand with aluminum build', 34.99),
('Wireless Charger', '15W fast wireless charging pad', 39.99),
('HDMI Cable', '4K HDMI 2.1 cable - 6ft', 19.99),
('Desk Mat', 'Extended gaming mouse pad - 31.5" x 11.8"', 24.99),
('Screen Protector', 'Tempered glass screen protector 2-pack', 19.99),
('Bluetooth Speaker', 'Portable waterproof speaker with 20hr battery', 89.99),
('Laptop Cooling Pad', 'Laptop cooler with 5 quiet fans', 45.99),
('Graphics Tablet', 'Digital drawing tablet with 8192 pressure levels', 199.99),
('Camera Ring Light', '10" LED ring light with phone holder', 34.99),
('WiFi Extender', 'Dual band WiFi range extender', 79.99),
('Desktop Speaker Set', '2.1 channel speakers with subwoofer', 129.99),
('Gaming Headset', '7.1 surround sound gaming headset', 89.99),
('Keyboard Wrist Rest', 'Memory foam keyboard wrist rest', 19.99),
('Cable Management Box', 'Large cable management box with cover', 29.99),
('Mini PC Speaker', 'Compact USB powered computer speakers', 24.99),
('Laptop Stand', 'Aluminum laptop stand with ventilation', 49.99),
('USB Microphone', 'Condenser microphone for streaming', 69.99),
('External SSD', '1TB portable SSD with USB-C', 149.99),
('Desk Organizer', 'Multi-compartment desk organizer', 34.99),
('Monitor Light Bar', 'Screen-mounted LED monitor light', 59.99),
('Kombucha Antioxidant', '20+ surface layers* to boost luminosity, hydration', 199.99);
GO

-- Supplier
INSERT INTO dbo.Supplier (Name, Phone, Email) VALUES
('Tech Global Supply', '555-0201', 'sales@techglobal.com'),
('ElectroTech Inc', '555-0202', 'orders@electrotech.com'),
('Digital Solutions Ltd', '555-0203', 'supply@digitalsolutions.com'),
('Smart Electronics Co', '555-0204', 'orders@smartelectronics.com'),
('Prime Components', '555-0205', 'sales@primecomp.com'),
('Advanced Hardware Ltd', '555-0206', 'sales@advancedhardware.com'),
('FutureTech Supplies', '555-0207', 'contact@futuretech.com'),
('Silicon Valley Partners', '555-0208', 'info@siliconvalley.com'),
('Global Tech Warehouse', '555-0209', 'support@globaltech.com'),
('Unified Electronics', '555-0210', 'service@unifiedelectronics.com');
GO


-- Warehouse
INSERT INTO dbo.Warehouse (Location, WarehouseName, Capacity, ManagerName, Phone) VALUES
('Boston, MA', 'East Coast Hub', 100000, 'Michael Johnson', '555-1001'),
('Los Angeles, CA', 'West Coast Hub', 120000, 'Sarah Martinez', '555-1002'),
('Chicago, IL', 'Central Hub', 90000, 'David Wilson', '555-1003'),
('Seattle, WA', 'Northwest Hub', 85000, 'Emily Carter', '555-1004'),
('Dallas, TX', 'Southern Hub', 95000, 'Christopher Lee', '555-1005'),
('Miami, FL', 'Southeast Hub', 70000, 'Olivia Brown', '555-1006'),
('Denver, CO', 'Rocky Mountain Hub', 80000, 'William Adams', '555-1007'),
('New York, NY', 'Northeast Hub', 110000, 'Sophia Davis', '555-1008'),
('Atlanta, GA', 'Mid-South Hub', 87000, 'James Taylor', '555-1009'),
('San Francisco, CA', 'Bay Area Hub', 115000, 'Isabella Moore', '555-1010');
GO



-- SupplierWarehouse
INSERT INTO dbo.SupplierWarehouse (SupplierID, WarehouseID, SupplyFrequency) VALUES
(1, 1, 'Weekly'),
(1, 2, 'Bi-Weekly'),
(1, 3, 'Monthly'),
(2, 1, 'Monthly'),
(2, 4, 'Weekly'),
(2, 5, 'Bi-Weekly'),
(3, 2, 'Monthly'),
(3, 3, 'Weekly'),
(3, 6, 'Bi-Weekly'),
(4, 3, 'Monthly'),
(4, 7, 'Weekly'),
(4, 8, 'Bi-Weekly'),
(5, 1, 'Weekly'),
(5, 5, 'Monthly'),
(5, 9, 'Bi-Weekly'),
(6, 2, 'Weekly'),
(6, 4, 'Bi-Weekly'),
(6, 10, 'Monthly'),
(7, 1, 'Bi-Weekly'),
(7, 3, 'Monthly'),
(7, 6, 'Weekly'),
(8, 2, 'Weekly'),
(8, 8, 'Monthly'),
(8, 9, 'Bi-Weekly'),
(9, 5, 'Bi-Weekly'),
(9, 7, 'Weekly'),
(9, 10, 'Monthly'),
(10, 4, 'Weekly'),
(10, 6, 'Bi-Weekly'),
(10, 8, 'Monthly');
GO



-- CustomerAddress
INSERT INTO dbo.CustomerAddress (CustomerID, StreetAddress, City, State, PostalCode, RecipientPhone, RecipientName) VALUES
(1, '123 Oak Street', 'Boston', 'MA', 02108, '555-0101', 'John Smith'),
(2, '456 Pine Avenue', 'Seattle', 'WA', 98101, '555-0102', 'Emma Wilson'),
(3, '789 Maple Lane', 'Chicago', 'IL', 60601, '555-0103', 'Michael Davis'),
(4, '321 Elm Street', 'Austin', 'TX', 78701, '555-0104', 'Sarah Brown'),
(5, '654 Cedar Road', 'Portland', 'OR', 97201, '555-0105', 'David Taylor'),
(6, '987 Birch Boulevard', 'Denver', 'CO', 80201, '555-0106', 'Lisa Anderson'),
(7, '147 Spruce Drive', 'Atlanta', 'GA', 30301, '555-0107', 'Robert Martin'),
(8, '258 Willow Way', 'Miami', 'FL', 33101, '555-0108', 'Jennifer White'),
(9, '369 Ash Avenue', 'Phoenix', 'AZ', 85001, '555-0109', 'William Clark'),
(10, '741 Palm Street', 'San Diego', 'CA', 92101, '555-0110', 'Emily Harris'),
(11, '852 Beach Road', 'New York', 'NY', 10001, '555-0111', 'Thomas Lee'),
(12, '963 Lake Drive', 'Houston', 'TX', 77001, '555-0112', 'Amanda King'),
(13, '159 River Lane', 'Philadelphia', 'PA', 19101, '555-0113', 'James Wright'),
(14, '267 Mountain View', 'Las Vegas', 'NV', 89101, '555-0114', 'Olivia Scott'),
(15, '348 Valley Road', 'Detroit', 'MI', 48201, '555-0115', 'Daniel Green'),
(16, '492 Forest Street', 'Nashville', 'TN', 37201, '555-0116', 'Sophia Baker'),
(17, '573 Park Avenue', 'San Francisco', 'CA', 94101, '555-0117', 'Ryan Adams'),
(18, '681 Ocean Drive', 'Los Angeles', 'CA', 90001, '555-0118', 'Nicole Hill'),
(19, '794 Sunset Boulevard', 'Dallas', 'TX', 75201, '555-0119', 'Kevin Ross'),
(20, '825 Highland Avenue', 'Seattle', 'WA', 98102, '555-0120', 'Laura Cooper'),
(21, '936 Grove Street', 'Portland', 'OR', 97202, '555-0121', 'Brian Morgan'),
(22, '147 Market Street', 'Boston', 'MA', 02109, '555-0122', 'Rachel Phillips'),
(23, '258 Union Avenue', 'Chicago', 'IL', 60602, '555-0123', 'Steven Torres'),
(24, '369 State Street', 'Austin', 'TX', 78702, '555-0124', 'Michelle Gray'),
(25, '471 Main Road', 'Denver', 'CO', 80202, '555-0125', 'Patrick Ward'),
(26, '582 Church Street', 'Atlanta', 'GA', 30302, '555-0126', 'Kelly Foster'),
(27, '693 Madison Avenue', 'Miami', 'FL', 33102, '555-0127', 'Christopher Price'),
(28, '714 Washington Street', 'Phoenix', 'AZ', 85002, '555-0128', 'Angela Butler'),
(29, '825 Jefferson Road', 'San Diego', 'CA', 92102, '555-0129', 'Brandon Barnes'),
(30, '936 Adams Street', 'New York', 'NY', 10002, '555-0130', 'Rebecca Fisher');
GO


-- Coupon
INSERT INTO dbo.Coupon (CouponCode, DiscountAmount, DiscountPercentage, MinimumPurchaseAmount, StartDate, EndDate, UsageLimit) VALUES
('WELCOME10', 10, NULL, 50, '2024-01-01', '2024-01-31', 10),
('SPRING20', NULL, 20, 10, '2024-03-01', '2024-03-31', 20),
('SUMMER15', 15, NULL, 75, '2024-06-01', '2024-06-30', 10),
('FALL25', NULL, 25, 15, '2024-09-01', '2024-09-30', 20),
('WINTER30', 30, NULL, 20, '2024-12-01', '2024-12-31', 10),
('FLASH50', NULL, 50, 30, '2024-01-15', '2024-01-16', 10),
('SAVE40', 40, NULL, 25, '2024-02-01', '2024-02-14', 20),
('SPECIAL45', NULL, 45, 27, '2024-04-01', '2024-04-15', 10),
('DEAL35', 35, NULL, 22, '2024-05-01', '2024-05-31', 20),
('EXTRA15', NULL, 15, 10, '2024-07-01', '2024-07-31', 15),
('BONUS20', 20, NULL, 15, '2024-08-01', '2024-08-31', 25),
('SAVE25', 25, NULL, 17, '2024-10-01', '2024-10-31', 15),
('HOLIDAY40', NULL, 40, 25, '2024-11-01', '2024-11-30', 25),
('NEW15', NULL, 15, 75, '2024-01-01', '2024-12-31', 30),
('VIP30', 30, NULL, 20, '2024-01-01', '2024-12-31', 5);
GO

-- CouponCustomer
INSERT INTO dbo.CouponCustomer (CouponID, CustomerID, UsageStatus) VALUES
(1, 2, 'Used'),
(1, 4, 'Used'),
(2, 6, 'Used'),
(3, 8, 'Used'),
(4, 10, 'Used'),
(5, 12, 'Used'),
(6, 14, 'Used'),
(7, 16, 'Used'),
(8, 18, 'Used'),
(9, 20, 'Used'),
(10, 22, 'Used'),
(11, 24, 'Used'),
(12, 26, 'Used'),
(13, 28, 'Used'),
(14, 30, 'Used'),
(1, 5, 'Used'),
(2, 12, 'Used'),
(3, 18, 'Used'),
(4, 22, 'Used'),
(5, 27, 'Used'),
(6, 6, 'Used'),
(7, 11, 'Used'),
(8, 17, 'Used'),
(9, 24, 'Used'),
(10, 30, 'Used');
GO

-- Order
INSERT INTO dbo.[Order] (CustomerID, CouponCustomerID, OrderDate) VALUES
(1, NULL, '2024-01-01'),
(2, 1, '2024-01-02'),
(3, NULL,  '2024-01-02'),
(4, 2, '2024-01-03'),
(5, NULL, '2024-01-03'),
(6, 3, '2024-01-04'),
(7, NULL, '2024-01-04'),
(8, 4, '2024-01-05'),
(9, NULL,'2024-01-05'),
(10, 5,'2024-01-06'),
(11, NULL, '2024-01-06'),
(12, 6, '2024-01-07'),
(13, NULL, '2024-01-07'),
(14, 7, '2024-01-08'),
(15, NULL, '2024-01-08'),
(16, 8, '2024-01-09'),
(17, NULL, '2024-01-09'),
(18, 9, '2024-01-10'),
(19, NULL, '2024-01-10'),
(20, 10, '2024-01-11'),
(21, NULL, '2024-01-11'),
(22, 11, '2024-01-12'),
(23, NULL, '2024-01-12'),
(24, 12, '2024-01-13'),
(25, NULL, '2024-01-13'),
(26, 13, '2024-01-14'),
(27, NULL, '2024-01-14'),
(28, 14, '2024-01-15'),
(29, NULL, '2024-01-15'),
(30, 15, '2024-01-16'),
(1, NULL, '2024-01-17'),
(5, 16, '2024-01-17'),
(8, NULL, '2024-01-18'),
(12, 17, '2024-01-18'),
(15, NULL, '2024-01-19'),
(18, 18, '2024-01-19'),
(20, NULL, '2024-01-20'),
(22, 19, '2024-01-20'),
(25, NULL, '2024-01-21'),
(27, 20, '2024-01-21'),
(3, NULL, '2024-01-22'),
(6, 21, '2024-01-22'),
(9, NULL, '2024-01-23'),
(11, 22, '2024-01-23'),
(14, NULL, '2024-01-24'),
(17, 23, '2024-01-24'),
(21, NULL, '2024-01-25'),
(24, 24,'2024-01-25'),
(28, NULL,'2024-01-26'),
(30, 25,'2024-01-26');


-- OrderItem
INSERT INTO dbo.OrderItem (OrderID, ProductID, Quantity) VALUES
(1, 1, 2),
(1, 3, 1),
(1, 5, 1),
(2, 2, 3),
(2, 4, 2),
(3, 1, 1),
(4, 6, 2),
(4, 8, 1),
(5, 7, 4),
(5, 9, 3),
(6, 10, 1),
(7, 11, 5),
(7, 13, 3),
(8, 12, 1),
(9, 14, 2),
(10, 15, 3),
(11, 16, 2),
(12, 17, 3),
(13, 18, 2),
(14, 19, 4),
(15, 20, 1),
(16, 21, 3),
(17, 22, 2),
(18, 23, 4),
(19, 24, 2),
(20, 25, 3),
(21, 26, 1),
(22, 27, 2),
(23, 28, 3),
(24, 29, 4),
(25, 30, 1),
(26, 1, 3),
(27, 2, 2),
(28, 3, 4),
(29, 4, 1),
(30, 5, 3),
(31, 6, 2),
(32, 7, 4),
(33, 8, 1),
(34, 9, 3),
(35, 10, 2),
(36, 11, 4),
(37, 12, 1),
(38, 13, 3),
(39, 14, 2),
(40, 15, 4),
(41, 16, 1),
(42, 17, 3),
(43, 18, 2),
(44, 19, 4),
(45, 20, 1),
(46, 21, 3),
(47, 22, 2),
(48, 23, 4),
(49, 24, 1),
(50, 25, 3);


-- Payment
INSERT INTO dbo.Payment (OrderID, PaymentMethod, PaymentDate, PaymentStatus) VALUES
(1, 'Credit Card', '2024-01-01', 'Finished'),
(2, 'PayPal', '2024-01-02', 'Finished'),
(3, 'Debit Card', '2024-01-02', 'Finished'),
(4, 'Credit Card', '2024-01-03', 'Finished'),
(5, 'PayPal', '2024-01-03', 'Finished'),
(6, 'Credit Card', '2024-01-04', 'Finished'),
(7, 'Debit Card', '2024-01-04', 'Finished'),
(8, 'PayPal', '2024-01-05', 'Finished'),
(9, 'Credit Card', '2024-01-05', 'Finished'),
(10, 'Credit Card', '2024-01-06', 'Finished'),
(11, 'PayPal', '2024-01-06', 'Finished'),
(12, 'Debit Card', '2024-01-07', 'Finished'),
(13, 'Credit Card', '2024-01-07', 'Finished'),
(14, 'PayPal', '2024-01-08', 'Finished'),
(15, 'Credit Card', '2024-01-08', 'Finished'),
(16, 'Debit Card', '2024-01-09', 'Finished'),
(17, 'Credit Card', '2024-01-09', 'Finished'),
(18, 'PayPal', '2024-01-10', 'Finished'),
(19, 'Credit Card', '2024-01-10', 'Finished'),
(20, 'Debit Card', '2024-01-11', 'Finished'),
(21, 'Credit Card', '2024-01-11', 'Finished'),
(22, 'PayPal', '2024-01-12', 'Finished'),
(23, 'Credit Card', '2024-01-12', 'Finished'),
(24, 'Debit Card', '2024-01-13', 'Finished'),
(25, 'PayPal', '2024-01-13', 'Finished'),
(26, 'Credit Card', '2024-01-14', 'Finished'),
(27, 'Credit Card', '2024-01-14', 'Finished'),
(28, 'PayPal', '2024-01-15', 'Finished'),
(29, 'Debit Card', '2024-01-15', 'Finished'),
(30, 'Credit Card', '2024-01-16', 'Finished'),
(31, 'PayPal', '2024-01-17', 'Finished'),
(32, 'Credit Card', '2024-01-17', 'Finished'),
(33, 'Debit Card', '2024-01-18', 'Finished'),
(34, 'Credit Card', '2024-01-18', 'Finished'),
(35, 'PayPal', '2024-01-19', 'Finished'),
(36, 'Credit Card', '2024-01-19', 'Finished'),
(37, 'Debit Card', '2024-01-20', 'Finished'),
(38, 'PayPal', '2024-01-20', 'Finished'),
(39, 'Credit Card', '2024-01-21', 'Finished'),
(40, 'Credit Card', '2024-01-21', 'Finished'),
(41, 'PayPal', '2024-01-22', 'Finished'),
(42, 'Debit Card', '2024-01-22', 'Finished'),
(43, 'Credit Card', '2024-01-23', 'Finished'),
(44, 'PayPal', '2024-01-23', 'Finished'),
(45, 'Credit Card', '2024-01-24', 'Finished'),
(46, 'Debit Card', '2024-01-24', 'Finished'),
(47, 'PayPal', '2024-01-25', 'Finished'),
(48, 'Credit Card', '2024-01-25', 'Finished'),
(49, 'Credit Card', '2024-01-26', 'Finished'),
(50, 'PayPal', '2024-01-26', 'Finished');


-- Inventory
INSERT INTO dbo.Inventory (ProductID, WarehouseID, QuantityInStock, ReorderLevel) VALUES
(1, 1, 50, 20),
(1, 2, 60, 20),
(1, 3, 40, 20),
(2, 1, 30, 15),
(2, 2, 40, 15),
(2, 3, 30, 15),
(3, 1, 70, 30),
(3, 2, 65, 30),
(3, 3, 65, 30),
(4, 1, 40, 20),
(4, 2, 40, 20),
(4, 3, 40, 20),
(5, 1, 60, 25),
(5, 2, 60, 25),
(5, 3, 60, 25),
(6, 1, 30, 15),
(6, 2, 30, 15),
(6, 3, 30, 15),
(7, 1, 25, 12),
(7, 2, 25, 12),
(7, 3, 25, 12),
(8, 1, 35, 15),
(8, 2, 35, 15),
(8, 3, 40, 15),
(9, 1, 30, 15),
(9, 2, 35, 15),
(9, 3, 30, 15),
(10, 1, 45, 20),
(10, 2, 45, 20),
(10, 3, 40, 20),
(11, 1, 55, 25),
(11, 2, 50, 25),
(11, 3, 55, 25),
(12, 1, 45, 20),
(12, 2, 45, 20),
(12, 3, 50, 20),
(13, 1, 85, 40),
(13, 2, 80, 40),
(13, 3, 85, 40),
(14, 1, 55, 25),
(14, 2, 60, 25),
(14, 3, 55, 25),
(15, 1, 100, 45),
(15, 2, 100, 45),
(15, 3, 100, 45),
(16, 1, 30, 15),
(16, 2, 25, 15),
(16, 3, 30, 15),
(17, 1, 35, 15),
(17, 2, 30, 15),
(17, 3, 30, 15),
(18, 1, 20, 10),
(18, 2, 20, 10),
(18, 3, 20, 10),
(19, 1, 40, 20),
(19, 2, 40, 20),
(19, 3, 40, 20),
(20, 1, 35, 15),
(20, 2, 40, 15),
(20, 3, 35, 15),
(21, 1, 25, 12),
(21, 2, 20, 12),
(21, 3, 25, 12),
(22, 1, 30, 15),
(22, 2, 35, 15),
(22, 3, 30, 15),
(23, 1, 65, 30),
(23, 2, 70, 30),
(23, 3, 65, 30),
(24, 1, 50, 25),
(24, 2, 50, 25),
(24, 3, 50, 25),
(25, 1, 60, 30),
(25, 2, 60, 30),
(25, 3, 60, 30),
(26, 1, 45, 20),
(26, 2, 40, 20),
(26, 3, 45, 20),
(27, 1, 30, 15),
(27, 2, 25, 15),
(27, 3, 30, 15),
(28, 1, 25, 12),
(28, 2, 20, 12),
(28, 3, 25, 12),
(29, 1, 45, 20),
(29, 2, 50, 20),
(29, 3, 45, 20),
(30, 1, 30, 15),
(30, 2, 30, 15),
(30, 3, 30, 15),
(31, 1, 20, 50);

-- Return
INSERT INTO dbo.[Return] (OrderItemID, CustomerID, ReturnDate, ReturnReason, RefundAmount, QuantityReturned, ReturnStatus, WarehouseID) VALUES
(4, 2, '2024-01-09', 'Defective Product', 81.83, 3, 'Finished', 3),
(7, 4, '2024-01-10', 'Wrong Size', 87.62, 2, 'Finished', 2),
(12, 7, '2024-01-11', 'Not As Described', 89.05, 5, 'Finished', 1),
(15, 9, '2024-01-12', 'Changed Mind', 95.25, 2, 'Finished', 3),
(18, 12, '2024-01-13', 'Better Price Found', 45.99, 3, 'Finished', 2),
(22, 16, '2024-01-14', 'Quality Issues', 129.99, 3, 'Finished', 1),
(25, 19, '2024-01-15', 'Damaged in Transit', 29.99, 2, 'Finished', 3),
(28, 22, '2024-01-16', 'Wrong Color', 69.99, 2, 'Finished', 2),
(31, 25, '2024-01-17', 'Arrived Too Late', 59.99, 1, 'Finished', 1),
(35, 29, '2024-01-18', 'Defective Product', 79.99, 1, 'NOT YET', 3),
(38, 5, '2024-01-19', 'Wrong Size', 129.99, 4, 'NOT YET', 2),
(41, 10, '2024-01-20', 'Not As Described', 44.99, 2, 'NOT YET', 1),
(44, 11, '2024-01-21', 'Changed Mind', 34.99, 4, 'NOT YET', 3),
(47, 21, '2024-01-22', 'Quality Issues', 89.99, 1, 'NOT YET', 2),
(50, 24, '2024-01-23', 'Damaged in Transit', 24.99, 3, 'NOT YET', 1);

SELECT * FROM [Return]

-- Shipment
INSERT INTO dbo.Shipment (OrderItemID, AddressID, ShipmentDate, DeliveryDate, TrackingNumber, Carrier, ShipmentStatus, WarehouseID) VALUES
(1, 1, '2024-01-02', '2024-01-05', 'TN100001', 'FedEx', 'Delivery', 1),
(2, 1, '2024-01-02', '2024-01-05', 'TN100002', 'FedEx', 'Delivery', 2),
(3, 1, '2024-01-02', '2024-01-05', 'TN100003', 'FedEx', 'Delivery', 1),
(4, 2, '2024-01-03', '2024-01-06', 'TN100004', 'UPS', 'Delivery', 3),
(5, 2, '2024-01-03', '2024-01-06', 'TN100005', 'UPS', 'Delivery', 2),
(6, 3, '2024-01-03', '2024-01-07', 'TN100006', 'USPS', 'Delivery', 1),
(7, 4, '2024-01-04', '2024-01-08', 'TN100007', 'FedEx', 'Delivery', 2),
(8, 4, '2024-01-04', '2024-01-08', 'TN100008', 'FedEx', 'Delivery', 3),
(9, 5, '2024-01-04', '2024-01-09', 'TN100009', 'UPS', 'Delivery', 1),
(10, 5, '2024-01-04', '2024-01-09', 'TN100010', 'UPS', 'Delivery', 2),
(11, 6, '2024-01-05', '2024-01-10', 'TN100011', 'USPS', 'Delivery', 3),
(12, 7, '2024-01-05', '2024-01-11', 'TN100012', 'FedEx', 'Delivery', 1),
(13, 7, '2024-01-05', '2024-01-11', 'TN100013', 'FedEx', 'Delivery', 2),
(14, 8, '2024-01-06', '2024-01-12', 'TN100014', 'UPS', 'Delivery', 3),
(15, 9, '2024-01-06', '2024-01-13', 'TN100015', 'USPS', 'Delivery', 1),
(16, 10, '2024-01-07', '2024-01-14', 'TN100016', 'FedEx', 'Delivery', 2),
(17, 11, '2024-01-07', '2024-01-15', 'TN100017', 'UPS', 'Delivery', 3),
(18, 12, '2024-01-08', '2024-01-16', 'TN100018', 'USPS', 'Delivery', 1),
(19, 13, '2024-01-08', '2024-01-17', 'TN100019', 'FedEx', 'Delivery', 2),
(20, 14, '2024-01-09', '2024-01-18', 'TN100020', 'UPS', 'Delivery', 3),
(21, 15, '2024-01-09', '2024-01-19', 'TN100021', 'USPS', 'Delivery', 1),
(22, 16, '2024-01-10', '2024-01-20', 'TN100022', 'FedEx', 'Delivery', 2),
(23, 17, '2024-01-10', '2024-01-21', 'TN100023', 'UPS', 'Delivery', 3),
(24, 18, '2024-01-11', '2024-01-22', 'TN100024', 'USPS', 'Delivery', 1),
(25, 19, '2024-01-11', '2024-01-23', 'TN100025', 'FedEx', 'Delivery', 2),
(26, 20, '2024-01-12', '2024-01-24', 'TN100026', 'UPS', 'Delivery', 3),
(27, 21, '2024-01-12', '2024-01-25', 'TN100027', 'USPS', 'Delivery', 1),
(28, 22, '2024-01-13', '2024-01-26', 'TN100028', 'FedEx', 'Delivery', 2),
(29, 23, '2024-01-13', '2024-01-27', 'TN100029', 'UPS', 'Delivery', 3),
(30, 24, '2024-01-14', '2024-01-28', 'TN100030', 'USPS', 'Delivery', 1),
(31, 25, '2024-01-14', '2024-01-29', 'TN100031', 'FedEx', 'Packaged', 2),
(32, 26, '2024-01-15', '2024-01-30', 'TN100032', 'UPS', 'Shipping', 3),
(33, 27, '2024-01-15', '2024-01-31', 'TN100033', 'USPS', 'Shipping', 1),
(34, 28, '2024-01-16', '2024-02-01', 'TN100034', 'FedEx', 'Confirm', 2),
(35, 29, '2024-01-16', '2024-02-02', 'TN100035', 'UPS', 'Confirm', 3),
(36, 30, '2024-01-17', '2024-02-03', 'TN100036', 'USPS', 'Confirm', 1);

INSERT INTO dbo.ShoppingCartItem (CustomerID, ProductID, Quantity) VALUES 
(21, 2, 5),
(17, 14, 2),
(13, 14, 10),
(6, 28, 6),
(5, 8, 7),
(30, 15, 4),
(25, 27, 5),
(22, 29, 8),
(23, 11, 6),
(13, 4, 7),
(1, 4, 7),
(7, 4, 4),
(26, 21, 10),
(13, 27, 8),
(17, 9, 10),
(1, 14, 7),
(5, 30, 5),
(23, 24, 6),
(15, 16, 3),
(26, 19, 2),
(16, 30, 10),
(5, 15, 3),
(25, 6, 9),
(28, 28, 4),
(1, 30, 7),
(29, 3, 9),
(23, 4, 1),
(23, 10, 3),
(3, 6, 3),
(30, 10, 1),
(11, 20, 2),
(27, 21, 4),
(11, 4, 4),
(4, 30, 4),
(18, 24, 8),
(7, 19, 2),
(7, 26, 3),
(8, 20, 1);



--VIEW

--- View 1. The marketing team can monitor the performance of coupons from multiple dimensions, 
--- enabling data-driven decisions to improve the accuracy and effectiveness of coupon distribution 
--- while optimizing the cost-efficiency of promotional campaigns.
CREATE VIEW vw_CouponUsageAnalysis AS
SELECT 
    C.CouponID,
    C.CouponCode,
    C.StartDate,
    C.EndDate,
    COUNT(CC.CouponCustomerID) AS TotalUsageCount, -- Number of times the coupon was used
	SUM(ISNULL(CC.DiscountApplied, 0)) AS TotalDiscountAmount, -- Total discount amount
	AVG(O.TotalAmount) AS AvgOrderAmount, -- Average order amount
	COUNT(DISTINCT O.CustomerID) AS UniqueUsers, -- Number of unique users using the coupon
	COUNT(DISTINCT O.OrderID) AS TotalOrders -- Total number of orders using the coupon
FROM 
    dbo.Coupon C
LEFT JOIN 
    dbo.CouponCustomer CC ON C.CouponID = CC.CouponID
LEFT JOIN 
    dbo.[Order] O ON CC.CouponCustomerID = O.CouponCustomerID
GROUP BY 
    C.CouponID, C.CouponCode, C.StartDate, C.EndDate;
GO
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
---to help supply chain personnel manage inventory and replenishment processes more efficiently
CREATE VIEW vw_ProductsBelowReorderLevel AS
SELECT 
    P.Name AS ProductName,
	I.WarehouseID,
    I.QuantityInStock,
	I.ReorderLevel,
	I.QuantityInStock-I.ReorderLevel AS reorderamount    
FROM 
    dbo.Inventory I
INNER JOIN 
    dbo.Product P
ON 
    P.ProductID = I.ProductID
WHERE 
    I.QuantityInStock <= I.ReorderLevel; 
GO
--Check if there are any products below the reorder level.
SELECT * FROM vw_ProductsBelowReorderLevel;