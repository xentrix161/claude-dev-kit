-- Zľava objednávky v percentách (0 = bez zľavy).
ALTER TABLE orders ADD COLUMN discount_percent SMALLINT NOT NULL DEFAULT 0;
