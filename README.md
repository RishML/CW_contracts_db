# База данных для автоматизации договорной работы ООО "Трубовик"

## Описание проекта
Разработка базы данных для учета договоров с поставщиками и покупателями, планирования платежей и контроля задолженности.

## Структура базы данных (9 таблиц)

| Таблица ----------| Назначение --------------------------|
|-------------------|--------------------------------------|
| organizations ----| Контрагенты (покупатели, поставщики) |
| contract_roles ---| Роли в договорах --------------------|
| contract_types ---| Типы договоров ----------------------|
| execution_stages -| Стадии исполнения -------------------|
| vat_rates --------| Ставки НДС --------------------------|
| payment_types ----| Виды оплат --------------------------|
| contracts --------| Договоры ----------------------------|
| contract_stages --| Этапы договоров ---------------------|
| payments----------| Оплаты ------------------------------|

## Связи между таблицами
- contracts → organizations (customer_id, executor_id)
- contracts → contract_types, execution_stages, vat_rates, contract_roles
- contract_stages → contracts, execution_stages
- payments → contracts, payment_types

## Реализованные ограничения
- PRIMARY KEY (во всех таблицах)
- FOREIGN KEY (все связи)
- UNIQUE (contract_number, inn, справочники)
- CHECK (amount >= 0, valid_dates, different_orgs)
- DEFAULT (created_at, total_amount)

## Индексы
Созданы индексы для ускорения поиска по:
- customer_id, executor_id, contract_date
- payments.contract_id
- organizations.inn
  
## Представления (VIEW)
active_contracts - активные договоры
contract_details - детальная информация
contract_statistics - статистика по годам
report_contract_details - все этапы, оплаты, задолженность
report_supplier_payments_plan - график платежей поставщикам
report_customer_payments_actual - график поступлений от покупателей
debt_receivable - дебиторская задолженность
debt_payable - кредиторская задолженность

## Триггер
Автоматический пересчет общей суммы договора при изменении этапов:

```sql
CREATE TRIGGER trg_contract_stages_changes
AFTER INSERT OR UPDATE OR DELETE ON contract_stages
EXECUTE FUNCTION update_contract_total();


