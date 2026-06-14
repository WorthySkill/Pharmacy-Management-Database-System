/*
   Description: 
   This script initializes the Pharmacy Management System database. It sets up 
   role-based access control, builds a fully normalized (3NF) schema, populates 
   sample data, and implements advanced programmability (Triggers, Transactions, 
   Procedures) to ensure ACID compliance and data integrity.
   ======================================================================================= */

-- PART 1: ENVIRONMENT SETUP & ROLE-BASED ACCESS CONTROL

-- Reset for fresh installation
DROP DATABASE IF EXISTS Pharmacy_System;
CREATE DATABASE Pharmacy_System;
USE Pharmacy_System;

-- Security roles (Principle of Least Privilege)
DROP ROLE IF EXISTS 'pharmacy_admin', 'pharmacy_user';
CREATE ROLE 'pharmacy_admin';
CREATE ROLE 'pharmacy_user';

--  Admins full control & Users only manipulate data
GRANT ALL PRIVILEGES ON Pharmacy_System.* TO 'pharmacy_admin';
GRANT SELECT, INSERT, UPDATE ON Pharmacy_System.* TO 'pharmacy_user';



-- PART 2: SCHEMA DEFINITION (3rd Normal Form)

-- 1 - Suppliers Table: Stores contact info for l vendor
CREATE TABLE Suppliers (
    SupplierID      INT AUTO_INCREMENT PRIMARY KEY,
    SupplierName    VARCHAR(100) NOT NULL,
    ContactPhone    VARCHAR(15) UNIQUE NOT NULL,
    Address         VARCHAR(255)
);

-- 2. Drugs Table: The inventory & reference l suppliers
CREATE TABLE Drugs (
    DrugID          INT AUTO_INCREMENT PRIMARY KEY,
    DrugName        VARCHAR(100) NOT NULL,
    Category        VARCHAR(50) NOT NULL,
    SupplierID      INT NOT NULL,
    Price           DECIMAL(10,2) CHECK (Price > 0), 
    StockQuantity   INT DEFAULT 0 CHECK (StockQuantity >= 0),
    ExpiryDate      DATE NOT NULL,
    
    -- Prevent deleting a supplier if we still carry their drugs
    FOREIGN KEY (SupplierID) REFERENCES Suppliers(SupplierID) ON DELETE RESTRICT
);

-- 3 - Patients Table: Stores profiles ll clients
CREATE TABLE Patients (
    PatientID       INT AUTO_INCREMENT PRIMARY KEY,
    FullName        VARCHAR(100) NOT NULL,
    Phone           VARCHAR(15) UNIQUE,
    RegistrationDate DATE DEFAULT (CURRENT_DATE)
);

-- 4 - Prescriptions Table: linking patients with doctor orders
CREATE TABLE Prescriptions (
    PrescriptionID  INT AUTO_INCREMENT PRIMARY KEY,
    PatientID       INT NOT NULL,
    DoctorName      VARCHAR(100) NOT NULL,
    IssueDate       DATE NOT NULL,
    
    -- If a patient is removed, remove their prescription history
    FOREIGN KEY (PatientID) REFERENCES Patients(PatientID) ON DELETE CASCADE
);

-- 5 - Sales Table: header for transactions checkout
CREATE TABLE Sales (
    SaleID          INT AUTO_INCREMENT PRIMARY KEY,
    PatientID       INT NULL, -- Nullable to allow for anonymous walk-in purchases
    SaleDate        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    TotalAmount     DECIMAL(10,2) DEFAULT 0.00,
    FOREIGN KEY (PatientID) REFERENCES Patients(PatientID)
);

-- 6. Sale Items Table
CREATE TABLE Sale_Items (
    SaleItemID      INT AUTO_INCREMENT PRIMARY KEY,
    SaleID          INT NOT NULL,
    DrugID          INT NOT NULL,
    Quantity        INT NOT NULL CHECK (Quantity > 0),
    Subtotal        DECIMAL(10,2) NOT NULL,
    
    FOREIGN KEY (SaleID) REFERENCES Sales(SaleID) ON DELETE CASCADE,
    FOREIGN KEY (DrugID) REFERENCES Drugs(DrugID) ON DELETE RESTRICT
);

-- 7. Pharmacy Staff Table App layer security w authentication
CREATE TABLE Pharmacy_Staff (
    StaffID         INT AUTO_INCREMENT PRIMARY KEY,
    Username        VARCHAR(50) UNIQUE NOT NULL,
    PasswordHash    VARCHAR(255) NOT NULL, -- Security: Stores bcrypt/SHA-256 hashes only
    Role            ENUM('Admin', 'Pharmacist', 'Cashier') NOT NULL,
    CreatedAt       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);



-- PART 3: QUERY OPTIMIZATION ( we do indexes & naterialized Views)


-- B-Tree indexes to stop scanning the whole table on frequently searched columns
CREATE INDEX idx_drug_expiry   ON Drugs(ExpiryDate);
CREATE INDEX idx_sale_date     ON Sales(SaleDate);
CREATE INDEX idx_supplier_name ON Suppliers(SupplierName);

-- View caching: shows drugs expiring in less than 3 months
CREATE VIEW Expiring_Drugs_View AS 
SELECT DrugName, StockQuantity, ExpiryDate 
FROM Drugs 
WHERE ExpiryDate < DATE_ADD(CURRENT_DATE, INTERVAL 3 MONTH);



--  Triggers & Procedures

DELIMITER //

-- Trigger: expiration

-- Automatically rejects insertion of any medication that is expired
CREATE TRIGGER Prevent_Expired_Drug_Insert
BEFORE INSERT ON Drugs
FOR EACH ROW
BEGIN
    IF NEW.ExpiryDate < CURRENT_DATE THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Integrity Error: Cannot add an expired drug to inventory.';
    END IF;
END //

-- Procedure: Inventory Management

-- by3ml increment to stock levels when new stuff arrives
CREATE PROCEDURE Restock_Drug(IN p_DrugID INT, IN p_AddedQty INT)
BEGIN
    UPDATE Drugs 
    SET StockQuantity = StockQuantity + p_AddedQty 
    WHERE DrugID = p_DrugID;
END //

--  ACID-Compliant ll checkout
-- Handles concurrent sales securely by utilizing row-level locking. (IMPORTANT)
CREATE PROCEDURE Process_Sale(IN p_PatientID INT, IN p_DrugID INT, IN p_Qty INT)
BEGIN
    DECLARE v_Price DECIMAL(10,2);
    DECLARE v_Stock INT;
    DECLARE v_SaleID INT;
    
    START TRANSACTION;
    
    -- Lock the specific drug row to prevent checkout conflicts
    SELECT Price, StockQuantity INTO v_Price, v_Stock 
    FROM Drugs 
    WHERE DrugID = p_DrugID FOR UPDATE;
    
    -- verification to see if we have enough
    IF v_Stock >= p_Qty THEN
        
        --  generate L Sale Header
        INSERT INTO Sales (PatientID, TotalAmount) 
        VALUES (p_PatientID, v_Price * p_Qty);
        
        SET v_SaleID = LAST_INSERT_ID();
        
        -- Generate the detailed line item
        INSERT INTO Sale_Items (SaleID, DrugID, Quantity, Subtotal) 
        VALUES (v_SaleID, p_DrugID, p_Qty, v_Price * p_Qty);
        
        -- Deduct the amount purchased from stock 
        UPDATE Drugs 
        SET StockQuantity = StockQuantity - p_Qty 
        WHERE DrugID = p_DrugID;
        
        COMMIT; -- Save changes permanently
        
    ELSE
        --  abort if stock not enough
        ROLLBACK; 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transaction Failed: Insufficient stock.';
    END IF;
END //
DELIMITER ;


-- PART 4: SAMPLE DATA INGESTION

-- Insert Administrator Account
INSERT INTO Pharmacy_Staff (Username, PasswordHash, Role)
VALUES ('admin_mahmoud', '$2b$12$KixG...[dummy_bcrypt_hash]...', 'Admin');

-- Suppliers
INSERT INTO Suppliers (SupplierName, ContactPhone, Address) VALUES
('Eva Pharma',       '01011112222', '6th of October City, Industrial Zone'),
('Amoun Pharma',     '01122223333', 'El Obour City, Block 4'),
('SEDICO',           '01233334444', '6th of October City, First Industrial Zone'),
('EIPICO',           '01044445555', '10th of Ramadan City'),
('Pharma Swede',     '01155556666', 'Badr City'),
('Minapharm',        '01266667777', '10th of Ramadan City, Area 3'),
('Nile Co.',         '01077778888', 'El Salam City, Cairo'),
('Marcyrl',          '01188889999', 'El Obour City'),
('Apex Pharma',      '01299990000', 'Badr City, Industrial Area'),
('Global Napi',      '01000001111', '6th of October, 2nd Zone'),
('Memphis Pharm',    '01111112222', 'Al Amiriya, Cairo'),
('CID Pharm',        '01222223333', 'Giza, Pyramids Road'),
('Kahira Pharm',     '01033334444', 'Shoubra, Cairo'),
('El Nile Co.',      '01144445555', 'El Sawah, Cairo'),
('Alexandria Co.',   '01255556666', 'El Awaiyd, Alexandria'),
('Medical Union',    '01066667777', 'Abu Sultan, Ismailia'),
('Sigma',            '01177778888', 'Quesna Industrial Zone'),
('Hikma',            '01288889999', 'Beni Suef Industrial Zone'),
('October Pharma',   '01099990000', '6th of October City'),
('Rameda',           '01100001111', '6th of October City, 3rd Zone');

-- Inventory (Drugs)
INSERT INTO Drugs (DrugName, Category, SupplierID, Price, StockQuantity, ExpiryDate) VALUES
('Panadol Extra',     'Analgesic',         1,  35.00,  100, '2027-12-01'),
('Augmentin 1g',      'Antibiotic',        2,  120.00, 50,  '2026-08-15'),
('Brufen 400mg',      'NSAID',             3,  45.00,  200, '2028-01-10'),
('Congestal',         'Cold & Flu',        4,  25.00,  150, '2026-11-20'),
('Concor 5mg',        'Beta Blocker',      5,  55.00,  80,  '2027-05-30'),
('Nexium 40mg',       'Antacid',           6,  180.00, 40,  '2026-06-15'),
('Zithrokan 500mg',   'Antibiotic',        7,  95.00,  60,  '2027-02-28'),
('Cataflam 50mg',     'Analgesic',         8,  42.00,  120, '2028-03-10'),
('Amaryl 2mg',        'Antidiabetic',      9,  65.00,  90,  '2027-09-01'),
('Lipitor 20mg',      'Statin',            10, 140.00, 45,  '2026-10-15'),
('Eltroxin 50mcg',    'Thyroid',           11, 48.00,  110, '2028-05-20'),
('Claritine',         'Antihistamine',     12, 38.00,  85,  '2027-04-12'),
('Motilium',          'Antiemetic',        13, 30.00,  130, '2026-12-01'),
('Plavix 75mg',       'Antiplatelet',      14, 210.00, 35,  '2027-07-25'),
('Glucophage 1000mg', 'Antidiabetic',      15, 50.00,  105, '2028-08-10'),
('Voltaren Emulgel',  'Topical Analgesic', 16, 60.00,  75,  '2026-09-05'),
('Betadine',          'Antiseptic',        17, 20.00,  200, '2029-01-01'),
('Flumox 1g',         'Antibiotic',        18, 45.00,  140, '2027-03-15'),
('Capozide',          'Antihypertensive',  19, 58.00,  65,  '2026-11-30'),
('Otrivin',           'Decongestant',      20, 22.00,  160, '2028-02-18');

-- Clients (Patients)
INSERT INTO Patients (FullName, Phone, RegistrationDate) VALUES
('Youssef Ibrahim', '01099887766', '2026-01-10'), ('Ahmed Mahmoud',   '01188776655', '2026-01-12'),
('Omar Hassan',     '01277665544', '2026-01-15'), ('Khaled Mostafa',  '01066554433', '2026-02-01'),
('Mahmoud Ali',     '01155443322', '2026-02-05'), ('Tarek Ziad',      '01244332211', '2026-02-20'),
('Karim Fawzy',     '01033221100', '2026-03-02'), ('Hassan Said',     '01122110099', '2026-03-10'),
('Amr Kamal',       '01211009988', '2026-03-15'), ('Ziad Nabil',      '01000998877', '2026-03-18'),
('Ibrahim Saad',    '01199887766', '2026-03-22'), ('Mostafa Galal',   '01288776655', '2026-04-01'),
('Ali Tarek',       '01077665544', '2026-04-05'), ('Rami Yassin',     '01166554433', '2026-04-10'),
('Maged Shawky',    '01255443322', '2026-04-12'), ('Hussein Bahaa',   '01044332211', '2026-04-15'),
('Sherif Wael',     '01133221100', '2026-04-18'), ('Waleed Emad',     '01222110099', '2026-04-20'),
('Ayman Farouk',    '01011009988', '2026-04-22'), ('Essam Magdy',     '01100998877', '2026-04-24');

--  Historical sales data
INSERT INTO Sales (PatientID, SaleDate, TotalAmount) VALUES
(1,  '2026-04-01 10:00:00', 35.00),  (2,  '2026-04-02 11:30:00', 120.00),
(3,  '2026-04-03 14:15:00', 90.00),  (4,  '2026-04-04 09:45:00', 25.00),
(5,  '2026-04-05 16:20:00', 55.00),  (6,  '2026-04-06 18:00:00', 180.00),
(7,  '2026-04-07 12:10:00', 95.00),  (8,  '2026-04-08 13:25:00', 84.00),
(9,  '2026-04-09 15:50:00', 65.00),  (10, '2026-04-10 17:40:00', 140.00),
(11, '2026-04-11 10:30:00', 48.00),  (12, '2026-04-12 11:15:00', 76.00),
(13, '2026-04-13 14:05:00', 30.00),  (14, '2026-04-14 09:55:00', 210.00),
(15, '2026-04-15 16:45:00', 50.00),  (16, '2026-04-16 19:10:00', 60.00),
(17, '2026-04-17 12:40:00', 40.00),  (18, '2026-04-18 13:50:00', 45.00),
(19, '2026-04-19 15:20:00', 58.00),  (20, '2026-04-20 17:15:00', 66.00);

-- Historical line items connected/mapped to the sales above
INSERT INTO Sale_Items (SaleID, DrugID, Quantity, Subtotal) VALUES
(1, 1, 1, 35.00),   (2, 2, 1, 120.00),  (3, 3, 2, 90.00),   (4, 4, 1, 25.00),
(5, 5, 1, 55.00),   (6, 6, 1, 180.00),  (7, 7, 1, 95.00),   (8, 8, 2, 84.00),
(9, 9, 1, 65.00),   (10, 10, 1, 140.00),(11, 11, 1, 48.00), (12, 12, 2, 76.00),
(13, 13, 1, 30.00), (14, 14, 1, 210.00),(15, 15, 1, 50.00), (16, 16, 1, 60.00),
(17, 17, 2, 40.00), (18, 18, 1, 45.00), (19, 19, 1, 58.00), (20, 20, 3, 66.00);

-- Historical prescriptions
INSERT INTO Prescriptions (PatientID, DoctorName, IssueDate) VALUES
(1, 'Dr. Samir Adel',   '2026-03-25'), (2, 'Dr. Hany Kamal',    '2026-03-26'),
(3, 'Dr. Magdy Youssef','2026-03-27'), (4, 'Dr. Wael Safwat',   '2026-03-28'),
(5, 'Dr. Tarek Nour',   '2026-03-29'), (6, 'Dr. Sherif Amin',   '2026-03-30'),
(7, 'Dr. Amr Helmy',    '2026-04-01'), (8, 'Dr. Khaled Radwan', '2026-04-02'),
(9, 'Dr. Bahaa Din',    '2026-04-03'), (10, 'Dr. Yasser Galal', '2026-04-04'),
(11, 'Dr. Samir Adel',  '2026-04-05'), (12, 'Dr. Hany Kamal',   '2026-04-06'),
(13, 'Dr. Magdy Youssef','2026-04-07'),(14, 'Dr. Wael Safwat',  '2026-04-08'),
(15, 'Dr. Tarek Nour',  '2026-04-09'), (16, 'Dr. Sherif Amin',  '2026-04-10'),
(17, 'Dr. Amr Helmy',   '2026-04-11'), (18, 'Dr. Khaled Radwan','2026-04-12'),
(19, 'Dr. Bahaa Din',   '2026-04-13'), (20, 'Dr. Yasser Galal', '2026-04-14');


-- PART 5

--  (Filter by Category)
SELECT * FROM Drugs WHERE Category = 'Antibiotic';

--  Basic delete operation (data purge)
-- stopping safe updates to delete old records
SET SQL_SAFE_UPDATES = 0;
DELETE FROM Patients WHERE RegistrationDate < '2025-01-01';
SET SQL_SAFE_UPDATES = 1;

--  simple JOIN (purchase history & sorted)
SELECT p.FullName, s.SaleDate, s.TotalAmount 
FROM Patients p
INNER JOIN Sales s ON p.PatientID = s.PatientID
ORDER BY s.SaleDate DESC;

--  Multi-Table JOIN (shows itemized receipts)
SELECT s.SaleID, d.DrugName, si.Quantity, si.Subtotal 
FROM Sale_Items si
JOIN Sales s ON si.SaleID = s.SaleID
JOIN Drugs d ON si.DrugID = d.DrugID;

-- optimization Check (showing the idx_sale_date index utilized)
EXPLAIN SELECT SUM(TotalAmount) AS AprilRevenue, COUNT(SaleID) AS TotalTransactions 
FROM Sales 
WHERE SaleDate >= '2026-04-01 00:00:00' AND SaleDate < '2026-05-01 00:00:00';

-- aggregate Function Execution (calculate revenue for April 2026 )
SELECT SUM(TotalAmount) AS AprilRevenue, COUNT(SaleID) AS TotalTransactions 
FROM Sales 
WHERE SaleDate >= '2026-04-01 00:00:00' AND SaleDate < '2026-05-01 00:00:00';

--  complex Subquery (find low stock for 6 october vendor )
SELECT DrugName, StockQuantity, Price 
FROM Drugs 
WHERE StockQuantity < 100 
AND SupplierID IN (
    SELECT SupplierID 
    FROM Suppliers 
    WHERE Address LIKE '%6th of October%'
);

-- security verification (shows hashed password in db)
SELECT Username, PasswordHash, Role FROM Pharmacy_Staff;
