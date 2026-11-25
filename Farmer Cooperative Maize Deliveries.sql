DROP SCHEMA IF EXISTS q9 CASCADE; CREATE SCHEMA q9; SET search_path TO q9;

CREATE TABLE farmers (
  farmer_id SERIAL PRIMARY KEY, farmer_number VARCHAR(20) NOT NULL UNIQUE, full_name VARCHAR(100) NOT NULL);
CREATE TABLE deliveries (
  delivery_id SERIAL PRIMARY KEY, farmer_id INT NOT NULL REFERENCES farmers,
  grade CHAR(1) NOT NULL CHECK (grade IN ('A','B','C')),
  weight_kg NUMERIC(10,2) NOT NULL, unit_rate NUMERIC(8,2) NOT NULL, total_value NUMERIC(12,2) NOT NULL,
  delivered_on DATE NOT NULL, is_paid BOOLEAN NOT NULL DEFAULT FALSE);
CREATE TABLE daily_purchases (
  purchase_date DATE PRIMARY KEY, total_weight NUMERIC(12,2) NOT NULL, total_value NUMERIC(14,2) NOT NULL);

CREATE FUNCTION fn_maize_rate(p_grade TEXT) RETURNS NUMERIC AS $$
DECLARE g TEXT;
BEGIN
  IF p_grade IS NULL THEN RAISE EXCEPTION 'Grade must not be NULL'; END IF;
  g := UPPER(TRIM(p_grade));
  IF g = 'A' THEN RETURN 5.00; ELSIF g = 'B' THEN RETURN 4.00; ELSIF g = 'C' THEN RETURN 3.00; END IF;
  RAISE EXCEPTION 'Unsupported grade %', p_grade;
END $$ LANGUAGE plpgsql IMMUTABLE;

CREATE FUNCTION trg_fn_price_delivery() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.weight_kg IS NULL OR NEW.weight_kg <= 0 THEN RAISE EXCEPTION 'Weight must be positive'; END IF;
  NEW.unit_rate   := fn_maize_rate(NEW.grade);
  NEW.total_value := ROUND(NEW.weight_kg * NEW.unit_rate, 2);
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_price_delivery BEFORE INSERT OR UPDATE ON deliveries
FOR EACH ROW EXECUTE FUNCTION trg_fn_price_delivery();

CREATE PROCEDURE pr_receive_delivery(p_farmer_id INT, p_grade TEXT, p_weight NUMERIC, p_date DATE)
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM 1 FROM farmers WHERE farmer_id = p_farmer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown farmer %', p_farmer_id; END IF;
  IF p_weight IS NULL OR p_weight <= 0 THEN RAISE EXCEPTION 'Weight must be positive'; END IF;
  IF p_date IS NULL THEN RAISE EXCEPTION 'Date required'; END IF;
  PERFORM fn_maize_rate(p_grade);
  INSERT INTO deliveries(farmer_id, grade, weight_kg, unit_rate, total_value, delivered_on, is_paid)
  VALUES (p_farmer_id, UPPER(TRIM(p_grade)), p_weight, 0, 0, p_date, FALSE);
END $$;

CREATE PROCEDURE pr_refresh_purchases(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO daily_purchases
  SELECT p_day, COALESCE(SUM(weight_kg),0), COALESCE(SUM(total_value),0)
    FROM deliveries WHERE delivered_on = p_day
  ON CONFLICT (purchase_date) DO UPDATE
    SET total_weight = EXCLUDED.total_weight, total_value = EXCLUDED.total_value;
END $$;

INSERT INTO farmers(farmer_number, full_name) VALUES
 ('F001','Boniface Tembo'), ('F002','Agnes Mulenga'), ('F003','Rodgers Sinkala');
CALL pr_receive_delivery(1,'A',100,CURRENT_DATE-1);
CALL pr_receive_delivery(1,'B',250.5,CURRENT_DATE);
CALL pr_receive_delivery(2,'C',400,CURRENT_DATE-1);
INSERT INTO deliveries(farmer_id, grade, weight_kg, unit_rate, total_value, delivered_on, is_paid) VALUES
 (2,'A',80,99,99,CURRENT_DATE,TRUE), (2,'B',120,0,0,CURRENT_DATE-1,TRUE), (1,'C',60,0,0,CURRENT_DATE-2,FALSE);
UPDATE deliveries SET is_paid = TRUE WHERE delivery_id IN (1,3);

CREATE VIEW v_farmer_amount_due AS
SELECT f.farmer_number, f.full_name,
       COALESCE(SUM(d.total_value) FILTER (WHERE NOT d.is_paid), 0) AS amount_due
  FROM farmers f LEFT JOIN deliveries d ON d.farmer_id = f.farmer_id
 GROUP BY f.farmer_id, f.farmer_number, f.full_name;

CREATE INDEX idx_deliv_farmer_date ON deliveries(farmer_id, delivered_on);
EXPLAIN SELECT * FROM deliveries WHERE farmer_id = 1 AND delivered_on BETWEEN CURRENT_DATE-7 AND CURRENT_DATE;

SELECT cron.schedule('q9_refresh_purchases', '30 1 * * *',
  $$SET search_path TO q9; CALL pr_refresh_purchases(CURRENT_DATE - 1)$$);
