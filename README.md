# Pharmacy Management System - Relational Database Schema & Implementation

A production-ready, fully normalized (3NF) relational database system designed to track medical inventory, supply chains, patient profiles, and secure financial sales transactions. This repository showcases advanced database engineering proficiencies, including Role-Based Access Control (RBAC), ACID-compliant transactional logic, automated triggers, indexed query optimization, and strict concurrency row-locking strategies.

## 🚀 Architectural Design & Advanced Features

### 1. Schema Normalization (3rd Normal Form)
The relational schema is mathematically normalized to **Third Normal Form (3NF)** to enforce structural data integrity, maximize storage efficiency, and completely eliminate insertion, update, and deletion anomalies across the entity lifecycle.

### 2. Enterprise Security & Access Control (RBAC)
Implements the Principle of Least Privilege by partitioning system privileges into discrete security roles:
* `pharmacy_admin`: Possesses absolute administrative, data definitions, and structural configuration control.
* `pharmacy_user`: Restricted strictly to Data Manipulation Language (DML) operations (SELECT, INSERT, UPDATE) for day-to-day operational execution.

### 3. Advanced Programmability & Concurrency Control
* **Automated Auditing Triggers:** Deploys reactive database triggers to intercept database state modifications (e.g., dynamically adjusting inventory stock counts in real-time immediately following a sale checkout event).
* **ACID Transaction Handling:** Wraps checkout and dispensing logic in strict `START TRANSACTION` segments using row-level locking (`FOR UPDATE`) to prevent negative inventory values or race conditions during high-volume simultaneous transactions.
* **Query Performance Profiling:** Utilizes targeted non-clustered database indices (e.g., `idx_sale_date`) to optimize complex multi-table JOIN operations and accelerate aggregation queries.

## 🛠️ Tech Stack & Database Architecture
* **Database Management System:** MySQL / MariaDB
* **Design Frameworks:** Entity-Relationship Modeling (ERD), 3NF Normalization
* **Core Concepts:** Stored Procedures, Database Triggers, ACID Compliance, Row-Level Concurrency Locking

## 📁 Repository Structure
* `Pharmacy_Database_Schema.sql` - Production script containing full DDL table initializations, data seeds, RBAC roles, triggers, and stored procedures.
* `Documentation/` - Directory housing the complete formal academic technical report and architectural analysis blocks.

## 🔧 Installation, Build, and Execution

### Prerequisites
Ensure you have a local instance of MySQL Server and the MySQL CLI or a client layout like MySQL Workbench installed.

### Step-by-Step Setup
1. Clone the repository to your workstation:
   ```bash
   git clone https://github.com/WorthySkill/Pharmacy-Management-Database-System.git
   cd Pharmacy-Management-Database-System
2. Execute the production script to compile the database architecture and seed data:
   ```bash
   mysql -u root -p < Pharmacy_Database_Schema.sql
3. Verify role initialization or test transactional query optimization run blocks using your preferred database IDE client.
