-- Full Sales Management Application SQL Schema
-- Includes: Tables, Indexes, Views, Search Functions, Triggers

-- ROLES & USERS
CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role_id INT REFERENCES roles(id),
    created_at TIMESTAMP DEFAULT now()
);

-- CUSTOMERS & SUPPLIERS
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(150) NOT NULL,
    phone VARCHAR(50),
    email VARCHAR(150),
    address TEXT,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE suppliers (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(150) NOT NULL,
    phone VARCHAR(50),
    email VARCHAR(150),
    address TEXT,
    created_at TIMESTAMP DEFAULT now()
);

-- PRODUCTS & WAREHOUSES
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    sku VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    price NUMERIC(12,2) NOT NULL,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE warehouses (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    location TEXT
);

CREATE TABLE stock (
    id SERIAL PRIMARY KEY,
    product_id INT REFERENCES products(id),
    warehouse_id INT REFERENCES warehouses(id),
    quantity NUMERIC(12,2) DEFAULT 0,
    UNIQUE(product_id, warehouse_id)
);

-- SALES & PURCHASES
CREATE TABLE sales (
    id SERIAL PRIMARY KEY,
    invoice_number VARCHAR(50) UNIQUE NOT NULL,
    customer_id INT REFERENCES customers(id),
    total NUMERIC(12,2) NOT NULL,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE sales_items (
    id SERIAL PRIMARY KEY,
    sale_id INT REFERENCES sales(id) ON DELETE CASCADE,
    product_id INT REFERENCES products(id),
    quantity NUMERIC(12,2) NOT NULL,
    price NUMERIC(12,2) NOT NULL
);

CREATE TABLE purchases (
    id SERIAL PRIMARY KEY,
    invoice_number VARCHAR(50) UNIQUE NOT NULL,
    supplier_id INT REFERENCES suppliers(id),
    total NUMERIC(12,2) NOT NULL,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE purchase_items (
    id SERIAL PRIMARY KEY,
    purchase_id INT REFERENCES purchases(id) ON DELETE CASCADE,
    product_id INT REFERENCES products(id),
    quantity NUMERIC(12,2) NOT NULL,
    price NUMERIC(12,2) NOT NULL
);

-- PAYMENTS (مديونية)
CREATE TABLE payments (
    id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customers(id),
    supplier_id INT REFERENCES suppliers(id),
    related_invoice VARCHAR(50),
    amount NUMERIC(12,2) NOT NULL,
    payment_type VARCHAR(20) CHECK (payment_type IN ('customer','supplier')),
    created_at TIMESTAMP DEFAULT now()
);

-- RETURNS (مرتجعات)
CREATE TABLE returns (
    id SERIAL PRIMARY KEY,
    type VARCHAR(20) CHECK (type IN ('sale','purchase')),
    related_invoice VARCHAR(50),
    customer_id INT REFERENCES customers(id),
    supplier_id INT REFERENCES suppliers(id),
    reason TEXT,
    created_at TIMESTAMP DEFAULT now(),
    is_deleted BOOLEAN DEFAULT FALSE
);

-- INVOICE TEMPLATES (تصميم الفواتير)
CREATE TABLE invoice_templates (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    content JSONB NOT NULL, -- حفظ الصور/النصوص/الالوان/الجداول بصيغة JSON
    created_at TIMESTAMP DEFAULT now()
);

-- SETTINGS
CREATE TABLE settings (
    id SERIAL PRIMARY KEY,
    key VARCHAR(100) UNIQUE NOT NULL,
    value TEXT
);

-- =======================================
-- VIEWS
-- =======================================

-- View لمديونية العملاء
CREATE OR REPLACE VIEW customer_debts AS
SELECT c.id AS customer_id, c.name AS customer_name,
       COALESCE(SUM(s.total),0) - COALESCE(SUM(p.amount),0) AS balance
FROM customers c
LEFT JOIN sales s ON s.customer_id = c.id
LEFT JOIN payments p ON p.customer_id = c.id AND p.payment_type='customer'
GROUP BY c.id, c.name;

-- View لمديونية الموردين
CREATE OR REPLACE VIEW supplier_debts AS
SELECT s.id AS supplier_id, s.name AS supplier_name,
       COALESCE(SUM(pu.total),0) - COALESCE(SUM(pm.amount),0) AS balance
FROM suppliers s
LEFT JOIN purchases pu ON pu.supplier_id = s.id
LEFT JOIN payments pm ON pm.supplier_id = s.id AND pm.payment_type='supplier'
GROUP BY s.id, s.name;

-- =======================================
-- SEARCH FUNCTIONS
-- =======================================

-- Search Customers
CREATE OR REPLACE FUNCTION search_customers(keyword TEXT)
RETURNS TABLE (id INT, code TEXT, name TEXT, phone TEXT, email TEXT, address TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT id, code, name, phone, email, address
    FROM customers
    WHERE code ILIKE '%'||keyword||'%'
       OR name ILIKE '%'||keyword||'%'
       OR phone ILIKE '%'||keyword||'%'
       OR email ILIKE '%'||keyword||'%'
       OR address ILIKE '%'||keyword||'%';
END; $$ LANGUAGE plpgsql;

-- Search Suppliers
CREATE OR REPLACE FUNCTION search_suppliers(keyword TEXT)
RETURNS TABLE (id INT, code TEXT, name TEXT, phone TEXT, email TEXT, address TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT id, code, name, phone, email, address
    FROM suppliers
    WHERE code ILIKE '%'||keyword||'%'
       OR name ILIKE '%'||keyword||'%'
       OR phone ILIKE '%'||keyword||'%'
       OR email ILIKE '%'||keyword||'%'
       OR address ILIKE '%'||keyword||'%';
END; $$ LANGUAGE plpgsql;

-- Search Products
CREATE OR REPLACE FUNCTION search_products(keyword TEXT)
RETURNS TABLE (id INT, sku TEXT, name TEXT, description TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT id, sku, name, description
    FROM products
    WHERE sku ILIKE '%'||keyword||'%'
       OR name ILIKE '%'||keyword||'%'
       OR description ILIKE '%'||keyword||'%';
END; $$ LANGUAGE plpgsql;

-- Search Sales
CREATE OR REPLACE FUNCTION search_sales(keyword TEXT)
RETURNS TABLE (id INT, invoice_number TEXT, customer_id INT, total NUMERIC, created_at TIMESTAMP) AS $$
BEGIN
    RETURN QUERY
    SELECT s.id, s.invoice_number, s.customer_id, s.total, s.created_at
    FROM sales s
    JOIN customers c ON c.id = s.customer_id
    WHERE s.invoice_number ILIKE '%'||keyword||'%'
       OR c.name ILIKE '%'||keyword||'%'
       OR CAST(s.total AS TEXT) ILIKE '%'||keyword||'%';
END; $$ LANGUAGE plpgsql;

-- Search Purchases
CREATE OR REPLACE FUNCTION search_purchases(keyword TEXT)
RETURNS TABLE (id INT, invoice_number TEXT, supplier_id INT, total NUMERIC, created_at TIMESTAMP) AS $$
BEGIN
    RETURN QUERY
    SELECT p.id, p.invoice_number, p.supplier_id, p.total, p.created_at
    FROM purchases p
    JOIN suppliers s ON s.id = p.supplier_id
    WHERE p.invoice_number ILIKE '%'||keyword||'%'
       OR s.name ILIKE '%'||keyword||'%'
       OR CAST(p.total AS TEXT) ILIKE '%'||keyword||'%';
END; $$ LANGUAGE plpgsql;

-- Search Returns
CREATE OR REPLACE FUNCTION search_returns(keyword TEXT)
RETURNS TABLE (id INT, type TEXT, related_invoice TEXT, reason TEXT, created_at TIMESTAMP) AS $$
BEGIN
    RETURN QUERY
    SELECT r.id, r.type, r.related_invoice, r.reason, r.created_at
    FROM returns r
    WHERE r.related_invoice ILIKE '%'||keyword||'%'
       OR r.reason ILIKE '%'||keyword||'%';
END; $$ LANGUAGE plpgsql;

-- Search Payments
CREATE OR REPLACE FUNCTION search_payments(keyword TEXT)
RETURNS TABLE (id INT, customer_id INT, supplier_id INT, related_invoice TEXT, amount NUMERIC, payment_type TEXT, created_at TIMESTAMP) AS $$
BEGIN
    RETURN QUERY
    SELECT p.id, p.customer_id, p.supplier_id, p.related_invoice, p.amount, p.payment_type, p.created_at
    FROM payments p
    WHERE p.related_invoice ILIKE '%'||keyword||'%'
       OR CAST(p.amount AS TEXT) ILIKE '%'||keyword||'%'
       OR p.payment_type ILIKE '%'||keyword||'%';
END; $$ LANGUAGE plpgsql;

-- =======================================
-- TRIGGERS (منع تعديل المخزون عند حذف المرتجعات)
-- =======================================
CREATE OR REPLACE FUNCTION prevent_stock_update_on_return_delete()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.is_deleted = FALSE AND NEW.is_deleted = TRUE THEN
        -- فقط وضع علامة حذف بدون تعديل المخزون
        RETURN NEW;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_returns_softdelete
BEFORE UPDATE ON returns
FOR EACH ROW EXECUTE FUNCTION prevent_stock_update_on_return_delete();
