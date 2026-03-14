CREATE TABLE contract_roles (
    role_id SERIAL PRIMARY KEY,
    role_name VARCHAR(50) NOT NULL UNIQUE,
    role_description VARCHAR(200)
);
CREATE TABLE contract_types (
    type_id SERIAL PRIMARY KEY,
    type_name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT
);
CREATE TABLE execution_stages (
    stage_id SERIAL PRIMARY KEY,
    stage_name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT
);
CREATE TABLE vat_rates (
    rate_id SERIAL PRIMARY KEY,
    rate_percent DECIMAL(5,2),
    description VARCHAR(100),
    CONSTRAINT vat_check CHECK (rate_percent IS NULL OR rate_percent >= 0)
);
CREATE TABLE payment_types (
    payment_type_id SERIAL PRIMARY KEY,
    payment_type_name VARCHAR(100) NOT NULL UNIQUE
);
CREATE TABLE organizations (
    org_id SERIAL PRIMARY KEY,
    org_name VARCHAR(200) NOT NULL,
    inn VARCHAR(12) UNIQUE NOT NULL,
    kpp VARCHAR(9),
    address TEXT,
    phone VARCHAR(20),
    fax VARCHAR(20),
    bank_name VARCHAR(200),
    bank_account VARCHAR(20),
    corr_account VARCHAR(20),
    bik VARCHAR(9),
    okonh VARCHAR(10),
    okpo VARCHAR(10),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    CONSTRAINT inn_length CHECK (LENGTH(inn) IN (10, 12))
);

CREATE TABLE contracts (
    contract_id SERIAL PRIMARY KEY,
    contract_number VARCHAR(50) NOT NULL,
    contract_date DATE NOT NULL DEFAULT CURRENT_DATE,
    customer_id INTEGER NOT NULL REFERENCES organizations(org_id),
    executor_id INTEGER NOT NULL REFERENCES organizations(org_id),
    type_id INTEGER NOT NULL REFERENCES contract_types(type_id),
    stage_id INTEGER NOT NULL REFERENCES execution_stages(stage_id),
    vat_rate_id INTEGER NOT NULL REFERENCES vat_rates(rate_id),
    role_id INTEGER NOT NULL REFERENCES contract_roles(role_id), -- Наша роль
    execution_date DATE,
    topic VARCHAR(500),
    notes TEXT,
    total_amount DECIMAL(15,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_dates CHECK (execution_date >= contract_date OR execution_date IS NULL),
    CONSTRAINT different_orgs CHECK (customer_id != executor_id),
    CONSTRAINT contract_number_unique UNIQUE (contract_number)
);
CREATE TABLE contract_stages (
    contract_id INTEGER REFERENCES contracts(contract_id) ON DELETE CASCADE,
    stage_number INTEGER NOT NULL,
    stage_id INTEGER NOT NULL REFERENCES execution_stages(stage_id),
    planned_date DATE NOT NULL,
    actual_date DATE,
    amount DECIMAL(15,2) NOT NULL CHECK (amount >= 0),
    advance_amount DECIMAL(15,2) DEFAULT 0 CHECK (advance_amount >= 0),
    topic VARCHAR(500),
    notes TEXT,
    PRIMARY KEY (contract_id, stage_number)
);
CREATE TABLE payments (
    payment_id SERIAL PRIMARY KEY,
    contract_id INTEGER NOT NULL REFERENCES contracts(contract_id) ON DELETE CASCADE,
    payment_date DATE NOT NULL,
    amount DECIMAL(15,2) NOT NULL CHECK (amount > 0),
    payment_type_id INTEGER NOT NULL REFERENCES payment_types(payment_type_id),
    document_number VARCHAR(50),
    document_date DATE,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_contracts_customer ON contracts(customer_id);
CREATE INDEX idx_contracts_executor ON contracts(executor_id);
CREATE INDEX idx_contracts_date ON contracts(contract_date);
CREATE INDEX idx_organizations_inn ON organizations(inn);

CREATE OR REPLACE FUNCTION update_contract_total()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE contracts
    SET total_amount = (
        SELECT COALESCE(SUM(amount), 0)
        FROM contract_stages
        WHERE contract_id = COALESCE(NEW.contract_id, OLD.contract_id)
    ),
    updated_at = CURRENT_TIMESTAMP
    WHERE contract_id = COALESCE(NEW.contract_id, OLD.contract_id);
    RETURN COALESCE(NEW, OLD);
END;

CREATE TRIGGER trg_contract_stages_changes
AFTER INSERT OR UPDATE OR DELETE ON contract_stages
FOR EACH ROW
EXECUTE FUNCTION update_contract_total();
$$ LANGUAGE plpgsql;

SELECT version();
DROP TRIGGER IF EXISTS trg_contract_stages_changes ON contract_stages;
DROP FUNCTION IF EXISTS update_contract_total();

CREATE OR REPLACE FUNCTION update_contract_total()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE contracts 
    SET total_amount = (
        SELECT COALESCE(SUM(amount), 0)
        FROM contract_stages
        WHERE contract_id = COALESCE(NEW.contract_id, OLD.contract_id)
    ),
    updated_at = CURRENT_TIMESTAMP
    WHERE contract_id = COALESCE(NEW.contract_id, OLD.contract_id);
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_contract_stages_changes
AFTER INSERT OR UPDATE OR DELETE ON contract_stages
FOR EACH ROW
EXECUTE FUNCTION update_contract_total();

SELECT 
    tgname AS trigger_name,
    pg_get_triggerdef(oid) AS trigger_definition
FROM pg_trigger
WHERE tgrelid = 'contract_stages'::regclass AND tgname = 'trg_contract_stages_changes';

INSERT INTO contract_roles (role_name, role_description) VALUES
('Поставщик/Испольнитель', 'Мы продаем товар или оказываем услугу'),
('Покупатель/Заказчик', 'Мы покупаем товар или заказываем услугу');

INSERT INTO contract_types (type_name, description) VALUES
('Поставка труб (покупка)', 'Мы закупаем трубы у поставщика'),
('Поставка труб (продажа)', 'Мы продаем трубы покупателю'),
('Аренда помещений (вх.)', 'Мы арендуем склад/офис'),
('Услуги рекламы (исх.)', 'Мы размещаем рекламу для клиента'),
('Бухгалтерское обслуживание (исх.)', 'Мы ведем бухгалтерию клиента'),
('Услуги связи (вх.)', 'Интернет, телефония для нас'),
('Коммунальные услуги (вх.)', 'Свет, вода для нас'),
('Канцелярские товары (вх.)', 'Закупка канцтоваров для офиса'),
('Спецодежда (вх.)', 'Закупка спецодежды для работников'),
('Юридические услуги (исх.)', 'Мы оказываем юр. консультации');

INSERT INTO execution_stages (stage_name, description) VALUES
('Черновик', 'Договор создан, но еще не в силе'),
('Действует', 'Договор подписан, исполняется'),
('Завершен', 'Все обязательства выполнены'),
('Расторгнут', 'Договор расторгнут'),
('Ожидает оплаты', 'Выставлен счет, ждем деньги');

INSERT INTO vat_rates (rate_percent, description) VALUES
(0, 'НДС 0% (экспорт)'),
(5, 'НДС 5% (льготная)'),
(7, 'НДС 7% (льготная)'),
(22, 'НДС 22% (основная)'),
(NULL, 'Без НДС (не является плательщиком)');

INSERT INTO payment_types (payment_type_name) VALUES
('Наличные'),
('Безналичный расчет'),
('Предоплата 100%'),
('Предоплата 50%'),
('Постоплата 100%');

TRUNCATE payment_types RESTART IDENTITY CASCADE;
INSERT INTO payment_types (payment_type_name) VALUES
('Наличные'),
('Безналичный расчет'),
('Предоплата 100%'),
('Предоплата 50%'),
('Постоплата 100%'),
('Постоплата в течение 5 дней'),
('Авансовый платеж'),
('Окончательный расчет');

INSERT INTO organizations (org_name, inn) VALUES
('ООО "Трубовик"', '7701123456'),  
('ПАО "Востоксталь"', '3528900597'),
('ООО "Металлоторгс"', '7725123456'),
('ООО "СтройИнвестМет"', '7703123456'),
('ООО "Рекламное агентство "Медиа-Старс"', '7715987654'),
('ИП Петров И.И.', '770212345678');

SELECT * FROM contract_roles;

SELECT org_id, org_name FROM organizations;
SELECT 'organizations' AS table_name, org_id, org_name FROM organizations;
SELECT 'contract_roles' AS table_name, role_id, role_name FROM contract_roles;
SELECT 'contract_types' AS table_name, type_id, type_name FROM contract_types;

-- Договор 1: Мы покупаем у Востоксталь (роль = Покупатель/Заказчик = ID 2)
INSERT INTO contracts (
    contract_number, contract_date, 
    customer_id, executor_id, 
    type_id, stage_id, vat_rate_id, 
    role_id, 
    topic, total_amount
) VALUES (
    'Д-2026-001', '2026-03-01', 
    1,  -- our_org_id (Трубовик) - мы
    2,  -- seller_org_id (Востоксталь) - поставщик
    1,  -- type_id 'Поставка труб (покупка)'
    2,  -- stage_id 'Действует' (узнай точный ID)
    4,  -- rate_id для 22%
    2,  -- role_id 'Покупатель/Заказчик'
    'Закупка труб стальных 219мм', 
    1500000
);

-- Договор 2: Мы продаем СтройИнвестМет (роль = Поставщик/Испольнитель = ID 1)
INSERT INTO contracts (
    contract_number, contract_date, 
    customer_id, executor_id, 
    type_id, stage_id, vat_rate_id, 
    role_id, 
    topic, total_amount
) VALUES (
    'Д-2026-002', '2026-03-05', 
    4,  -- buyer_org_id (СтройИнвестМет) - покупатель
    1,  -- our_org_id (Трубовик) - мы
    2,  -- type_id 'Поставка труб (продажа)'
    2,  -- stage_id 'Действует'
    4,  -- rate_id для 22%
    1,  -- role_id 'Поставщик/Испольнитель'
    'Продажа труб профильных', 
    2800000
);

SELECT stage_id FROM execution_stages WHERE stage_name = 'Действует';

SELECT contract_id, contract_number, customer_id, executor_id, role_id, topic 
FROM contracts 
ORDER BY contract_id DESC
LIMIT 2;

SELECT contract_id, contract_number, topic FROM contracts;

INSERT INTO contracts (
    contract_number, contract_date, 
    customer_id, executor_id, 
    type_id, stage_id, vat_rate_id, 
    role_id, 
    topic, total_amount
) VALUES (
    'Д-2026-001', '2026-03-01', 
    1,  -- ООО "Трубовик" (мы)
    2,  -- ПАО "Востоксталь" (поставщик)
    1,  -- 'Поставка труб (покупка)'
    2,  -- stage_id 'Действует'
    4,  -- rate_id для 22%
    2,  -- role_id 'Покупатель/Заказчик'
    'Закупка труб стальных 219мм', 
    1500000
);

SELECT contract_id, contract_number, topic FROM contracts;

SELECT 
    sequence_name,
    last_value
FROM information_schema.sequences
WHERE sequence_schema = 'public';

SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    c.topic,
    c.total_amount,
    ct.type_name
FROM contracts c
JOIN contract_types ct ON c.type_id = ct.type_id
WHERE ct.type_id = 9;

SELECT * FROM contract_types WHERE type_id = 9;

INSERT INTO contracts (
    contract_number, contract_date, 
    customer_id, executor_id, 
    type_id, stage_id, vat_rate_id, 
    role_id, 
    topic, total_amount
) VALUES (
    'Д-2026-003', '2026-03-10',
    1,  -- ООО "Трубовик" (мы)
    3,  -- ООО "Металлоторгс" (поставщик)
    9,  -- type_id для спецодежды
    2,  -- stage_id 'Действует'
    4,  -- rate_id для 22%
    2,  -- role_id 'Покупатель/Заказчик'
    'Закупка спецодежды для такелажной группы', 
    85000
);

SELECT 
    c.contract_id,
    c.contract_number,
    ct.type_name,
    c.topic
FROM contracts c
JOIN contract_types ct ON c.type_id = ct.type_id
WHERE ct.type_id = 9;

SELECT 
    c.contract_id,
    c.contract_number,
    ct.type_name,
    c.topic
FROM contracts c
RIGHT JOIN contract_types ct ON c.type_id = ct.type_id
ORDER BY ct.type_id;

SELECT MAX(contract_id) FROM contracts;

ALTER SEQUENCE contracts_contract_id_seq RESTART WITH 15;
SELECT nextval('contracts_contract_id_seq') as next_id;

-- Вставляем оплату для договора ID=2
INSERT INTO payments (
    contract_id, payment_date, amount, 
    payment_type_id, document_number, document_date
) VALUES (
    2,  -- ID договора Д-2026-002 (продажа)
    '2026-03-07', 
    1400000, 
    (SELECT payment_type_id FROM payment_types WHERE payment_type_name = 'Предоплата 50%'), 
    'ПП-0001',
    '2026-03-07'
);

SELECT contract_id, contract_number, topic FROM contracts;

INSERT INTO payments (
    contract_id, payment_date, amount, 
    payment_type_id, document_number, document_date
) VALUES (
    12,  -- ID договора Д-2026-002 (продажа)
    '2026-03-07', 
    1400000, 
    (SELECT payment_type_id FROM payment_types WHERE payment_type_name = 'Предоплата 50%'), 
    'ПП-0001',
    '2026-03-07'
);

SELECT 
    p.payment_id,
    c.contract_number,
    p.payment_date,
    p.amount,
    pt.payment_type_name,
    p.document_number
FROM payments p
JOIN contracts c ON p.contract_id = c.contract_id
JOIN payment_types pt ON p.payment_type_id = pt.payment_type_id
WHERE c.contract_id = 12;
-- Этап для договора закупки труб (ID=13)
INSERT INTO contract_stages (
    contract_id, stage_number, stage_id, 
    planned_date, amount, advance_amount, topic
) VALUES (
    13, 1,
    (SELECT stage_id FROM execution_stages WHERE stage_name = 'Ожидает оплаты'),
    '2026-03-15', 1500000, 750000,
    'Отгрузка первой партии труб от Востоксталь'
);
-- Этап для договора продажи (ID=12) 
INSERT INTO contract_stages (
    contract_id, stage_number, stage_id, 
    planned_date, amount, advance_amount, topic
) VALUES (
    12, 1,
    (SELECT stage_id FROM execution_stages WHERE stage_name = 'Ожидает оплаты'),
    '2026-03-20', 1400000, 1400000,
    'Предоплата 50% по договору продажи'
);
INSERT INTO contract_stages (
    contract_id, stage_number, stage_id, 
    planned_date, amount, advance_amount, topic
) VALUES (
    12, 2,
    (SELECT stage_id FROM execution_stages WHERE stage_name = 'Ожидает оплаты'),
    '2026-03-25', 1400000, 0,
    'Постоплата после отгрузки'
);
SELECT contract_id, contract_number, total_amount FROM contracts;
ALTER SEQUENCE contracts_contract_id_seq RESTART WITH 1;
DELETE FROM payments;
DELETE FROM contract_stages;
DELETE FROM contracts;

INSERT INTO contracts (contract_id, contract_number, contract_date, customer_id, executor_id, type_id, stage_id, vat_rate_id, role_id, topic, total_amount) VALUES
(1, 'Д-2026-001', '2026-03-01', 1, 2, 1, 2, 4, 2, 'Закупка труб стальных 219мм (Востоксталь)', 1500000),
(2, 'Д-2026-002', '2026-03-05', 4, 1, 2, 2, 4, 1, 'Продажа труб профильных (СтройИнвестМет)', 2800000),
(3, 'Д-2026-003', '2026-03-10', 1, 3, 9, 2, 4, 2, 'Закупка спецодежды для такелажной группы', 85000),
(4, 'Д-2026-004', '2026-03-12', 5, 1, 4, 2, 4, 1, 'Размещение рекламы на баннерах (Медиа-Старс)', 450000),
(5, 'Д-2026-005', '2026-03-15', 6, 1, 5, 2, 4, 1, 'Бухгалтерское обслуживание (ИП Петров)', 120000),
(6, 'Д-2026-006', '2026-03-18', 1, 5, 6, 2, 4, 2, 'Услуги связи (интернет, телефония)', 36000),
(7, 'Д-2026-007', '2026-03-20', 1, 5, 7, 2, 4, 2, 'Коммунальные услуги (электричество, вода)', 45000),
(8, 'Д-2026-008', '2026-03-22', 1, 3, 8, 2, 4, 2, 'Канцелярские товары для офиса', 25000),
(9, 'Д-2026-009', '2026-03-25', 6, 1, 10, 2, 4, 1, 'Юридические услуги (консультации)', 75000),
(10, 'Д-2026-010', '2026-03-28', 1, 2, 3, 2, 4, 2, 'Аренда складского помещения №3', 300000),
(11, 'Д-2026-011', '2026-03-30', 4, 1, 2, 2, 5, 1, 'Продажа труб (льготная ставка НДС 7%)', 950000);

SELECT stage_id, stage_name FROM execution_stages;
INSERT INTO contract_stages (contract_id, stage_number, stage_id, planned_date, amount, advance_amount, topic) VALUES
(1, 1, 5, '2026-03-15', 1500000, 750000, 'Отгрузка труб от Востоксталь');
-- Этапы для договора 2 (продажа труб)
INSERT INTO contract_stages (contract_id, stage_number, stage_id, planned_date, amount, advance_amount, topic) VALUES
(2, 1, 5, '2026-03-20', 1400000, 1400000, 'Предоплата 50%'),
(2, 2, 5, '2026-03-25', 1400000, 0, 'Постоплата после отгрузки');

-- Этапы для договора 3 (спецодежда)
INSERT INTO contract_stages (contract_id, stage_number, stage_id, planned_date, amount, advance_amount, topic) VALUES
(3, 1, 5, '2026-03-20', 85000, 85000, 'Полная предоплата за спецодежду');

-- Этапы для договора 4 (реклама)
INSERT INTO contract_stages (contract_id, stage_number, stage_id, planned_date, amount, advance_amount, topic) VALUES
(4, 1, 5, '2026-04-01', 150000, 150000, 'Аренда баннера январь'),
(4, 2, 5, '2026-05-01', 150000, 0, 'Аренда баннера февраль'),
(4, 3, 5, '2026-06-01', 150000, 0, 'Аренда баннера март');

-- Этапы для договора 5 (бухгалтерия)
INSERT INTO contract_stages (contract_id, stage_number, stage_id, planned_date, amount, advance_amount, topic) VALUES
(5, 1, 5, '2026-04-05', 40000, 40000, 'Бух.обслуживание январь'),
(5, 2, 5, '2026-05-05', 40000, 0, 'Бух.обслуживание февраль'),
(5, 3, 5, '2026-06-05', 40000, 0, 'Бух.обслуживание март');

-- Этапы для договора 6 (связь)
INSERT INTO contract_stages (contract_id, stage_number, stage_id, planned_date, amount, advance_amount, topic) VALUES
(6, 1, 5, '2026-04-10', 36000, 36000, 'Оплата связи за квартал');

-- Этапы для договора 7 (коммунальные)
INSERT INTO contract_stages (contract_id, stage_number, stage_id, planned_date, amount, advance_amount, topic) VALUES
(7, 1, 5, '2026-04-15', 45000, 45000, 'Коммунальные платежи март');

-- Этапы для договора 8 (канцтовары)
INSERT INTO contract_stages (contract_id, stage_number, stage_id, planned_date, amount, advance_amount, topic) VALUES
(8, 1, 5, '2026-04-01', 25000, 25000, 'Поставка канцтоваров');

-- Этапы для договора 9 (юридические)
INSERT INTO contract_stages (contract_id, stage_number, stage_id, planned_date, amount, advance_amount, topic) VALUES
(9, 1, 5, '2026-04-10', 25000, 25000, 'Юр.консультация январь'),
(9, 2, 5, '2026-05-10', 25000, 0, 'Юр.консультация февраль'),
(9, 3, 5, '2026-06-10', 25000, 0, 'Юр.консультация март');

-- Этапы для договора 10 (аренда)
INSERT INTO contract_stages (contract_id, stage_number, stage_id, planned_date, amount, advance_amount, topic) VALUES
(10, 1, 5, '2026-04-05', 100000, 100000, 'Аренда март'),
(10, 2, 5, '2026-05-05', 100000, 0, 'Аренда апрель'),
(10, 3, 5, '2026-06-05', 100000, 0, 'Аренда май');

-- Этапы для договора 11 (продажа льготная)
INSERT INTO contract_stages (contract_id, stage_number, stage_id, planned_date, amount, advance_amount, topic) VALUES
(11, 1, 5, '2026-04-10', 475000, 475000, 'Предоплата 50%'),
(11, 2, 5, '2026-04-20', 475000, 0, 'Постоплата после отгрузки');

SELECT 
    c.contract_number,
    cs.stage_number,
    es.stage_name,
    cs.amount,
    cs.advance_amount,
    cs.planned_date
FROM contract_stages cs
JOIN contracts c ON cs.contract_id = c.contract_id
JOIN execution_stages es ON cs.stage_id = es.stage_id
ORDER BY c.contract_id, cs.stage_number;

INSERT INTO payments (contract_id, payment_date, amount, payment_type_id, document_number) VALUES
(1, '2026-03-10', 750000, 4, 'ПП-0010'),  -- аванс по договору 1
(2, '2026-03-15', 1400000, 4, 'ПП-0011'),  -- предоплата 50% по договору 2
(3, '2026-03-18', 85000, 3, 'ПП-0012'),   -- полная предоплата по договору 3
(4, '2026-03-25', 150000, 4, 'ПП-0013'),  -- аванс по рекламе (январь)
(5, '2026-03-30', 40000, 4, 'ПП-0014'),   -- аванс по бухгалтерии (январь)
(6, '2026-04-05', 36000, 3, 'ПП-0015'),   -- полная оплата связи
(7, '2026-04-10', 45000, 3, 'ПП-0016'),   -- полная оплата коммунальных
(8, '2026-03-28', 25000, 3, 'ПП-0017'),   -- полная оплата канцтоваров
(9, '2026-04-05', 25000, 4, 'ПП-0018'),   -- аванс по юр.услугам (январь)
(10, '2026-03-30', 100000, 4, 'ПП-0019'), -- аванс по аренде (март)
(11, '2026-04-05', 475000, 4, 'ПП-0020'); -- предоплата 50% по договору 11

SELECT 
    c.contract_number,
    p.payment_date,
    p.amount,
    pt.payment_type_name,
    p.document_number
FROM payments p
JOIN contracts c ON p.contract_id = c.contract_id
JOIN payment_types pt ON p.payment_type_id = pt.payment_type_id
ORDER BY p.payment_date;

SELECT * FROM contract_roles;
SELECT * FROM contract_types ORDER BY type_id;
SELECT * FROM execution_stages ORDER BY stage_id;
SELECT * FROM vat_rates ORDER BY rate_id;
SELECT * FROM payment_types ORDER BY payment_type_id;
SELECT org_id, org_name, inn FROM organizations ORDER BY org_id;
SELECT 
    contract_id, 
    contract_number, 
    contract_date,
    customer_id,
    executor_id,
    type_id,
    stage_id,
    vat_rate_id,
    role_id,
    topic,
    total_amount
FROM contracts 
ORDER BY contract_id;

SELECT 
    contract_id,
    contract_number,
    total_amount
FROM contracts
ORDER BY contract_id;

SELECT 
    contract_id,
    stage_number,
    stage_id,
    planned_date,
    actual_date,
    amount,
    advance_amount,
    topic
FROM contract_stages 
ORDER BY contract_id, stage_number;

SELECT 
    payment_id,
    contract_id,
    payment_date,
    amount,
    payment_type_id,
    document_number
FROM payments 
ORDER BY payment_date;

SELECT 'contract_roles' AS table_name, COUNT(*) AS records FROM contract_roles
UNION ALL
SELECT 'contract_types', COUNT(*) FROM contract_types
UNION ALL
SELECT 'execution_stages', COUNT(*) FROM execution_stages
UNION ALL
SELECT 'vat_rates', COUNT(*) FROM vat_rates
UNION ALL
SELECT 'payment_types', COUNT(*) FROM payment_types
UNION ALL
SELECT 'organizations', COUNT(*) FROM organizations
UNION ALL
SELECT 'contracts', COUNT(*) FROM contracts
UNION ALL
SELECT 'contract_stages', COUNT(*) FROM contract_stages
UNION ALL
SELECT 'payments', COUNT(*) FROM payments
ORDER BY table_name;

SELECT 
    org_id AS "Код организации",
    org_name AS "Наименование",
    inn AS "ИНН",
    kpp AS "КПП",
    address AS "Адрес",
    phone AS "Телефон",
    fax AS "Факс",
    bank_name AS "Банк",
    bank_account AS "Расч. счет",
    corr_account AS "Корр. счет",
    bik AS "БИК",
    okonh AS "ОКОНХ",
    okpo AS "ОКПО"
FROM organizations 
ORDER BY org_id;

SELECT 
    c.contract_id AS "Код договора",
    c.contract_number AS "Номер договора",
    c.contract_date AS "Дата",
    cust.org_name AS "Заказчик (покупатель)",
    cust.inn AS "ИНН заказчика",
    exec.org_name AS "Исполнитель (поставщик)",
    exec.inn AS "ИНН исполнителя",
    ct.type_name AS "Тип договора",
    es.stage_name AS "Стадия",
    vr.rate_percent AS "НДС, %",
    c.total_amount AS "Сумма",
    c.topic AS "Тема"
FROM contracts c
LEFT JOIN organizations cust ON c.customer_id = cust.org_id
LEFT JOIN organizations exec ON c.executor_id = exec.org_id
LEFT JOIN contract_types ct ON c.type_id = ct.type_id
LEFT JOIN execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN vat_rates vr ON c.vat_rate_id = vr.rate_id
ORDER BY c.contract_id;

CREATE OR REPLACE VIEW report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    
    -- Информация по этапам
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    
    -- Оплаты
    p.payment_date,
    p.amount AS payment_amount,
    pt.payment_type_name,
    p.document_number,
    
    -- Расчет задолженности
    c.total_amount - COALESCE(
        (SELECT SUM(amount) FROM payments WHERE contract_id = c.contract_id), 0
    ) AS debt_amount
FROM contracts c
LEFT JOIN organizations cust ON c.customer_id = cust.org_id
LEFT JOIN organizations exec ON c.executor_id = exec.org_id
LEFT JOIN contract_types ct ON c.type_id = ct.type_id
LEFT JOIN execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN payments p ON c.contract_id = p.contract_id
LEFT JOIN payment_types pt ON p.payment_type_id = pt.payment_type_id
ORDER BY c.contract_id, cs.stage_number, p.payment_date;

UPDATE organizations 
SET 
    inn = '7701123456',
    kpp = '770101001',
    address = 'г. Москва, ул. Строителей, д. 15, офис 305',
    phone = '+7 (495) 123-45-67',
    fax = '+7 (495) 123-45-68',
    bank_name = 'ПАО "Сбербанк"',
    bank_account = '40702810123456789012',
    corr_account = '30101810123456789012',
    bik = '044525225',
    okonh = '51200',
    okpo = '12345678'
WHERE org_name = 'ООО "Трубовик"';

UPDATE organizations 
SET 
    inn = '3528000597',
    kpp = '352801001',
    address = 'г. Череповец, ул. Металлургов, д. 30',
    phone = '+7 (8202) 53-70-50',
    fax = '+7 (8202) 53-70-51',
    bank_name = 'ПАО "ВТБ"',
    bank_account = '40702810234567890123',
    corr_account = '30101810345678901234',
    bik = '044525123',
    okonh = '27100',
    okpo = '98765432'
WHERE org_name = 'ПАО "Востоксталь"';

UPDATE organizations 
SET 
    inn = '7725123456',
    kpp = '772501001',
    address = 'г. Москва, ул. Промышленная, д. 10',
    phone = '+7 (495) 987-65-43',
    fax = '+7 (495) 987-65-44',
    bank_name = 'АО "Альфа-Банк"',
    bank_account = '40702810345678901234',
    corr_account = '30101810456789012345',
    bik = '044525234',
    okonh = '51300',
    okpo = '87654321'
WHERE org_name = 'ООО "Металлоторгс"';

UPDATE organizations 
SET 
    inn = '7703123456',
    kpp = '770301001',
    address = 'г. Москва, ул. Строительная, д. 20',
    phone = '+7 (495) 777-88-99',
    fax = '+7 (495) 777-88-90',
    bank_name = 'ПАО "Банк Открытие"',
    bank_account = '40702810789012345678',
    corr_account = '30101810890123456789',
    bik = '044525567',
    okonh = '45200',
    okpo = '33445566'
WHERE org_name = 'ООО "СтройИнвестМет"';

UPDATE organizations 
SET 
    inn = '7715987654',
    kpp = '771501001',
    address = 'г. Москва, ул. Тверская, д. 25',
    phone = '+7 (495) 555-66-77',
    fax = '+7 (495) 555-66-78',
    bank_name = 'АО "Тинькофф Банк"',
    bank_account = '40702810567890123456',
    corr_account = '30101810678901234567',
    bik = '044525456',
    okonh = '87100',
    okpo = '11223344'
WHERE org_name = 'ООО "Рекламное агентство "Медиа-Старс"';

UPDATE organizations 
SET 
    inn = '770212345678',
    kpp = NULL,
    address = 'г. Москва, ул. Ленина, д. 5, кв. 12',
    phone = '+7 (903) 111-22-33',
    fax = NULL,
    bank_name = 'ПАО "Сбербанк"',
    bank_account = '40802810678901234567',
    corr_account = '30101810789012345678',
    bik = '044525225',
    okonh = '92300',
    okpo = '22334455'
WHERE org_name = 'ИП Петров И.И.';

CREATE OR REPLACE VIEW customers_list AS
SELECT 
    org_id AS "Код покупателя",
    org_name AS "Наименование",
    inn AS "ИНН",
    kpp AS "КПП",
    address AS "Адрес",
    phone AS "Телефон",
    fax AS "Факс",
    bank_name AS "Банк",
    bank_account AS "Расчетный счет",
    corr_account AS "Корр. счет",
    bik AS "БИК"
FROM organizations
WHERE org_id IN (
    SELECT DISTINCT customer_id 
    FROM contracts 
    WHERE customer_id != 1  -- не наша организация
)
ORDER BY org_name;

CREATE OR REPLACE VIEW suppliers_list AS
SELECT 
    org_id AS "Код поставщика",
    org_name AS "Наименование",
    inn AS "ИНН",
    kpp AS "КПП",
    address AS "Адрес",
    phone AS "Телефон",
    fax AS "Факс",
    bank_name AS "Банк",
    bank_account AS "Расчетный счет",
    corr_account AS "Корр. счет",
    bik AS "БИК"
FROM organizations
WHERE org_id IN (
    SELECT DISTINCT executor_id 
    FROM contracts 
    WHERE executor_id != 1  -- не наша организация
)
ORDER BY org_name;

CREATE OR REPLACE VIEW our_company_info AS
SELECT 
    org_id AS "Код",
    org_name AS "Наименование",
    inn AS "ИНН",
    kpp AS "КПП",
    address AS "Адрес",
    phone AS "Телефон",
    fax AS "Факс",
    bank_name AS "Банк",
    bank_account AS "Расчетный счет",
    corr_account AS "Корр. счет",
    bik AS "БИК",
    okonh AS "ОКОНХ",
    okpo AS "ОКПО"
FROM organizations
WHERE org_name = 'ООО "Трубовик"';

SELECT * FROM our_company_info;

SELECT * FROM customers_list;

SELECT * FROM suppliers_list;

SELECT 
    'Наша компания' AS type,
    COUNT(*) AS count
FROM our_company_info
UNION ALL
SELECT 
    'Покупатели',
    COUNT(*)
FROM customers_list
UNION ALL
SELECT 
    'Поставщики',
    COUNT(*)
FROM suppliers_list;

DROP VIEW IF EXISTS report_contract_details CASCADE;

DROP VIEW IF EXISTS report_contract_details CASCADE;
CREATE OR REPLACE VIEW report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date
FROM contracts c;

SELECT current_user;

CREATE OR REPLACE VIEW report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name
FROM contracts c
LEFT JOIN organizations cust ON c.customer_id = cust.org_id;

CREATE OR REPLACE VIEW report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name
FROM contracts c
LEFT JOIN organizations cust ON c.customer_id = cust.org_id
LEFT JOIN organizations exec ON c.executor_id = exec.org_id;

CREATE OR REPLACE VIEW report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type
FROM contracts c
LEFT JOIN organizations cust ON c.customer_id = cust.org_id
LEFT JOIN organizations exec ON c.executor_id = exec.org_id
LEFT JOIN contract_types ct ON c.type_id = ct.type_id;

CREATE OR REPLACE VIEW report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage
FROM contracts c
LEFT JOIN organizations cust ON c.customer_id = cust.org_id
LEFT JOIN organizations exec ON c.executor_id = exec.org_id
LEFT JOIN contract_types ct ON c.type_id = ct.type_id
LEFT JOIN execution_stages es ON c.stage_id = es.stage_id;

CREATE OR REPLACE VIEW report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount
FROM contracts c
LEFT JOIN organizations cust ON c.customer_id = cust.org_id
LEFT JOIN organizations exec ON c.executor_id = exec.org_id
LEFT JOIN contract_types ct ON c.type_id = ct.type_id
LEFT JOIN execution_stages es ON c.stage_id = es.stage_id;


SELECT table_name, table_schema 
FROM information_schema.tables 
WHERE table_name LIKE '%contract%';

SELECT contract_id, contract_number 
FROM public.contracts 
LIMIT 5;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    contract_id,
    contract_number,
    contract_date
FROM public.contracts;

SELECT * FROM public.report_contract_details LIMIT 5;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id;

SELECT * FROM public.report_contract_details LIMIT 5;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id;

SELECT * FROM public.report_contract_details LIMIT 5;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id;

SELECT * FROM public.report_contract_details LIMIT 5;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id;

SELECT * FROM public.report_contract_details LIMIT 5;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    contract_id,
    contract_number,
    contract_date
FROM public.contracts;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id;

SELECT * FROM public.report_contract_details LIMIT 5;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id;

SELECT * FROM public.report_contract_details LIMIT 5;
DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id;

SELECT * FROM public.report_contract_details LIMIT 5;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id;
SELECT * FROM public.report_contract_details LIMIT 5;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

SELECT * FROM public.contract_stages LIMIT 5;
DROP VIEW IF EXISTS public.report_contract_details CASCADE;
CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    cs.stage_number
FROM public.contracts c
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    cs.stage_number,
    cs.amount AS stage_amount
FROM public.contracts c
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount
FROM public.contracts c
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date
FROM public.contracts c
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date
FROM public.contracts c
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date
FROM public.contracts c
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;
CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date
FROM public.contracts c
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date
FROM public.contracts c
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;
CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date
FROM public.contracts c
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    p.document_number
FROM public.contracts c
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    pt.payment_type_name,
    p.document_number
FROM public.contracts c
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id
LEFT JOIN public.payment_types pt ON p.payment_type_id = pt.payment_type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    pt.payment_type_name,
    p.document_number
FROM public.contracts c
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id
LEFT JOIN public.payment_types pt ON p.payment_type_id = pt.payment_type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;
DROP VIEW IF EXISTS public.report_contract_details CASCADE;
DROP VIEW IF EXISTS public.report_contract_details CASCADE;
DROP VIEW IF EXISTS public.report_contract_details CASCADE;
CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    contract_id,
    contract_number
FROM public.contracts;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    contract_id,
    contract_number,
    contract_date
FROM public.contracts;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;


CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date
FROM public.contracts c;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction
FROM public.contracts c;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;
CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;
CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    pt.payment_type_name,
    p.document_number
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id
LEFT JOIN public.payment_types pt ON p.payment_type_id = pt.payment_type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;
SELECT 
    contract_id,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LIMIT 5;
DROP VIEW IF EXISTS public.report_contract_details CASCADE;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;


DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;
CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;
CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    pt.payment_type_name,
    p.document_number,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id
LEFT JOIN public.payment_types pt ON p.payment_type_id = pt.payment_type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    pt.payment_type_name,
    p.document_number,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid,
    c.total_amount - (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS debt_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id
LEFT JOIN public.payment_types pt ON p.payment_type_id = pt.payment_type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    pt.payment_type_name,
    p.document_number,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid,
    c.total_amount - (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS debt_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id
LEFT JOIN public.payment_types pt ON p.payment_type_id = pt.payment_type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;
DROP VIEW IF EXISTS public.report_contract_details CASCADE;
DROP VIEW IF EXISTS public.report_contract_details CASCADE;
DROP VIEW IF EXISTS public.report_contract_details CASCADE;
DROP VIEW IF EXISTS public.report_contract_details CASCADE;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id
FROM public.contracts c;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number
FROM public.contracts c;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date
FROM public.contracts c;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;
CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction
FROM public.contracts c;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;
CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    pt.payment_type_name,
    p.document_number
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id
LEFT JOIN public.payment_types pt ON p.payment_type_id = pt.payment_type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    pt.payment_type_name,
    p.document_number,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id
LEFT JOIN public.payment_types pt ON p.payment_type_id = pt.payment_type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    pt.payment_type_name,
    p.document_number,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid,
    c.total_amount - (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS debt_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id
LEFT JOIN public.payment_types pt ON p.payment_type_id = pt.payment_type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

SELECT 
    contract_id,
    role_id,
    total_amount
FROM public.contracts
LIMIT 5;

SELECT 
    contract_id,
    role_id,
    total_amount,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid
FROM public.contracts c
LIMIT 5;

SELECT 
    contract_id,
    role_id,
    total_amount,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid,
    total_amount - (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS debt_amount
FROM public.contracts c
LIMIT 5;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    pt.payment_type_name,
    p.document_number,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid,
    c.total_amount - (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS debt_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id
LEFT JOIN public.payment_types pt ON p.payment_type_id = pt.payment_type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    pt.payment_type_name,
    p.document_number,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid,
    c.total_amount - (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS debt_amount,
    c.role_id AS role_id_check
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id
LEFT JOIN public.payment_types pt ON p.payment_type_id = pt.payment_type_id
LIMIT 5;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    pt.payment_type_name,
    p.document_number,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid,
    c.total_amount - (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS debt_amount,
    c.role_id AS role_id_check
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id
LEFT JOIN public.payment_types pt ON p.payment_type_id = pt.payment_type_id;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

DROP VIEW IF EXISTS public.report_contract_details CASCADE;

CREATE OR REPLACE VIEW public.report_contract_details AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    CASE 
        WHEN c.role_id = 1 THEN 'Реализация (исходящий договор)'
        ELSE 'Поступление (входящий договор)'
    END AS direction,
    cust.org_name AS customer_name,
    exec.org_name AS executor_name,
    ct.type_name AS contract_type,
    es.stage_name AS current_stage,
    c.topic,
    c.total_amount AS contract_amount,
    cs.stage_number,
    cs.amount AS stage_amount,
    cs.advance_amount,
    cs.planned_date AS stage_planned_date,
    p.payment_date,
    p.amount AS payment_amount,
    pt.payment_type_name,
    p.document_number,
    (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS total_paid,
    c.total_amount - (SELECT COALESCE(SUM(amount), 0) FROM public.payments WHERE contract_id = c.contract_id) AS debt_amount
FROM public.contracts c
LEFT JOIN public.organizations cust ON c.customer_id = cust.org_id
LEFT JOIN public.organizations exec ON c.executor_id = exec.org_id
LEFT JOIN public.contract_types ct ON c.type_id = ct.type_id
LEFT JOIN public.execution_stages es ON c.stage_id = es.stage_id
LEFT JOIN public.contract_stages cs ON c.contract_id = cs.contract_id
LEFT JOIN public.payments p ON c.contract_id = p.contract_id
LEFT JOIN public.payment_types pt ON p.payment_type_id = pt.payment_type_id;

SELECT 
    *,
    CASE 
        WHEN direction = 'Реализация (исходящий договор)' AND debt_amount > 0 THEN 'Дебиторская задолженность'
        WHEN direction = 'Поступление (входящий договор)' AND debt_amount > 0 THEN 'Кредиторская задолженность'
        ELSE 'Нет задолженности'
    END AS debt_type
FROM public.report_contract_details
ORDER BY contract_id, stage_number, payment_date;

SELECT * FROM public.report_contract_details 
WHERE direction = 'Реализация (исходящий договор)' 
  AND debt_amount > 0
ORDER BY contract_id, stage_number, payment_date;

SELECT 
    *,
    CASE 
        WHEN direction = 'Реализация (исходящий договор)' AND debt_amount > 0 THEN 'Дебиторская'
        WHEN direction = 'Поступление (входящий договор)' AND debt_amount > 0 THEN 'Кредиторская'
        ELSE 'Нет задолженности'
    END AS debt_type
FROM public.report_contract_details
WHERE direction = 'Реализация (исходящий договор)' 
  AND debt_amount > 0
ORDER BY contract_id, stage_number, payment_date;

CREATE OR REPLACE VIEW public.debt_receivable AS
SELECT * FROM public.report_contract_details 
WHERE direction = 'Реализация (исходящий договор)' 
  AND debt_amount > 0;

SELECT * FROM public.debt_receivable 
ORDER BY contract_id, stage_number, payment_date;

SELECT * FROM public.report_contract_details 
WHERE direction = 'Поступление (входящий договор)' 
  AND debt_amount > 0
ORDER BY debt_amount DESC, contract_id;

CREATE OR REPLACE VIEW public.debt_payable AS
SELECT * FROM public.report_contract_details 
WHERE direction = 'Поступление (входящий договор)' 
  AND debt_amount > 0;

SELECT * FROM public.debt_payable 
ORDER BY debt_amount DESC;

SELECT SUM(debt_amount) AS total_debt_payable 
FROM public.debt_payable;

SELECT SUM(debt_amount) AS total_debt_receivable 
FROM public.debt_receivable;

SELECT 
    'Дебиторская (нам должны)' AS debt_type,
    COUNT(*) AS contracts_count,
    SUM(debt_amount) AS total_amount
FROM public.report_contract_details 
WHERE direction = 'Реализация (исходящий договор)' AND debt_amount > 0

UNION ALL

SELECT 
    'Кредиторская (мы должны)' AS debt_type,
    COUNT(*) AS contracts_count,
    SUM(debt_amount) AS total_amount
FROM public.report_contract_details 
WHERE direction = 'Поступление (входящий договор)' AND debt_amount > 0;

CREATE OR REPLACE VIEW report_supplier_payments_plan AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    'Входящий договор (с поставщиком)' AS contract_direction,
    exec.org_name AS supplier_name,
    exec.inn AS supplier_inn,
    ct.type_name AS goods_type,
    cs.stage_number,
    cs.planned_date AS planned_payment_date,
    cs.amount AS planned_amount,
    cs.advance_amount,
    CASE 
        WHEN cs.advance_amount = cs.amount THEN '100% предоплата'
        WHEN cs.advance_amount > 0 AND cs.advance_amount < cs.amount THEN 'Частичная предоплата'
        ELSE 'Постоплата'
    END AS payment_terms,
    EXTRACT(YEAR FROM cs.planned_date) AS plan_year,
    EXTRACT(MONTH FROM cs.planned_date) AS plan_month,
    TO_CHAR(cs.planned_date, 'YYYY-MM') AS plan_month_year
FROM contracts c
JOIN contract_stages cs ON c.contract_id = cs.contract_id
JOIN organizations exec ON c.executor_id = exec.org_id
JOIN contract_types ct ON c.type_id = ct.type_id
WHERE c.role_id = 2  -- Исходящий договор (мы покупатели)
ORDER BY cs.planned_date;

CREATE OR REPLACE VIEW report_customer_payments_actual AS
SELECT 
    c.contract_id,
    c.contract_number,
    c.contract_date,
    'Исходящий договор (с покупателем)' AS contract_direction,
    cust.org_name AS customer_name,
    cust.inn AS customer_inn,
    ct.type_name AS goods_type,
    p.payment_date,
    p.amount AS actual_amount,
    pt.payment_type_name,
    p.document_number,
    EXTRACT(YEAR FROM p.payment_date) AS payment_year,
    EXTRACT(MONTH FROM p.payment_date) AS payment_month,
    TO_CHAR(p.payment_date, 'YYYY-MM') AS payment_month_year,
    CASE 
        WHEN pt.payment_type_name = 'Предоплата 100%' THEN 'Полная предоплата'
        WHEN pt.payment_type_name = 'Предоплата 50%' THEN 'Частичная предоплата'
        ELSE 'Постоплата'
    END AS payment_terms
FROM payments p
JOIN contracts c ON p.contract_id = c.contract_id
JOIN organizations cust ON c.customer_id = cust.org_id
JOIN contract_types ct ON c.type_id = ct.type_id
JOIN payment_types pt ON p.payment_type_id = pt.payment_type_id
WHERE c.role_id = 1  -- Исходящий договор (мы поставщики)
ORDER BY p.payment_date;

SELECT * FROM report_supplier_payments_plan;

SELECT * FROM report_customer_payments_actual;
SELECT * FROM report_supplier_payments_plan LIMIT 1;

SELECT column_name 
FROM information_schema.columns 
WHERE table_name = 'report_supplier_payments_plan'
ORDER BY ordinal_position;

SELECT 
    plan_month_year,
    payment_terms,
    COUNT(*) AS operations,
    SUM(planned_amount) AS total_plan
FROM report_supplier_payments_plan
GROUP BY plan_month_year, payment_terms
ORDER BY plan_month_year, payment_terms;

SELECT column_name 
FROM information_schema.columns 
WHERE table_name = 'report_customer_payments_actual'
ORDER BY ordinal_position;

SELECT 
    plan_month_year,
    payment_terms,
    COUNT(*) AS operations,
    SUM(planned_amount) AS total_plan
FROM report_supplier_payments_plan
GROUP BY plan_month_year, payment_terms
ORDER BY plan_month_year, payment_terms;

SELECT 
    payment_month_year,
    payment_terms,
    COUNT(*) AS operations,
    SUM(actual_amount) AS total_fact
FROM report_customer_payments_actual
GROUP BY payment_month_year, payment_terms
ORDER BY payment_month_year, payment_terms;

SELECT 
    COALESCE(s.plan_month_year, c.payment_month_year) AS month,
    s.total_plan AS payments_to_suppliers,
    c.total_fact AS receipts_from_customers,
    c.total_fact - COALESCE(s.total_plan, 0) AS net_cash_flow
FROM 
    (SELECT plan_month_year, SUM(planned_amount) AS total_plan 
     FROM report_supplier_payments_plan 
     GROUP BY plan_month_year) s
FULL JOIN 
    (SELECT payment_month_year, SUM(actual_amount) AS total_fact 
     FROM report_customer_payments_actual 
     GROUP BY payment_month_year) c
    ON s.plan_month_year = c.payment_month_year
ORDER BY month;

SELECT 
    s.contract_number,
    s.supplier_name,
    s.planned_payment_date AS plan_date,
    s.planned_amount,
    c.payment_date AS fact_date,
    c.actual_amount,
    CASE 
        WHEN c.actual_amount IS NULL THEN 'Не оплачено'
        WHEN c.actual_amount >= s.planned_amount THEN 'Оплачено полностью'
        ELSE 'Оплачено частично'
    END AS payment_status
FROM report_supplier_payments_plan s
LEFT JOIN report_customer_payments_actual c ON s.contract_number = c.contract_number
ORDER BY s.planned_payment_date;
