-- 2. В индивидуальной БД создать:
-- 2.1)	горизонтальное обновляемое представление с условием (WHERE);
-- 2.2)	проверить обновляемость горизонтального представления с фразой WITH CHECK OPTION при помощи одной из инструкций UPDATE, DELETE, INSERT (привести примеры выполняющихся и не выполняющихся инструкций, объяснить);
-- 2.3)	Создать вертикальное или смешанное необновляемое представле-ние, предназначенное для работы с основной таблицей БД (в представлении не должно быть ключевого атрибута, формирующегося с помощью автоинкремен-тации, а должны содержаться все сведения из основной дочерней таблицы и/или корзины (если есть), где вместо внешних ключей используются все связанные данные родительских таблиц (full join), понятные конечному пользователю представления);
-- 2.4) доказать необновляемость представления из предыдущего пункта, про-верив возможность выполнения инструкций UPDATE, DELETE, INSERT над представлением. Сохранить полученный результат (сообщение об ошибке или об успешном выполнении), объяснить причины;
-- 2.5) cоздать обновляемое представление для работы с одной из родитель-ских таблиц индивидуальной БД и через него разрешить работу с данными только в рабочие дни (с понедельника по пятницу) и в рабочие часы (с 9:00 до 17:00) с учетом часового пояса.

-- Горизонтальное представление: только активные договоры страхования жизни
CREATE OR REPLACE VIEW active_life_insurance_view AS
SELECT ic.id,
       ic.contract_date,
       ic.premium,
       ic.unpaid_premium,
       ic.agent_id,
       ic.client_id,
       ic.insurance_type_id
FROM insurance_contract ic
WHERE ic.contract_status = 'Активен'
  AND ic.insurance_type_id = (SELECT id FROM insurance_type WHERE name = 'Жизнь')
WITH CHECK OPTION;

-- Примеры выполняющихся операций:

-- 1. UPDATE - обновление существующей записи (соответствует условию WHERE)
UPDATE active_life_insurance_view
SET premium = premium * 1.1
WHERE id = 6;

-- 2. UPDATE - изменение данных, но не условий представления
UPDATE active_life_insurance_view
SET unpaid_premium = 0
WHERE client_id = 1;

-- Примеры не выполняющихся операций:

-- 1. INSERT - попытка вставить договор с неверным типом страхования
INSERT INTO active_life_insurance_view (id, contract_date, premium, unpaid_premium, agent_id, client_id,
                                        insurance_type_id)
VALUES (100, SYSDATE, 1000, 0, 1, 1, 2);
-- insurance_type_id = 2 (не "Жизнь")
-- Ошибка: "ORA-01733: виртуальный столбец здесь недопустим"

-- 2. UPDATE - попытка изменить тип страхования на невалидный
UPDATE active_life_insurance_view
SET insurance_type_id = 3 -- изменение на другой тип страхования
WHERE id = 6;
-- Ошибка: "ORA-01402: представление WITH CHECK OPTION не соответствует фразе WHERE"

-- 3. UPDATE - попытка изменить статус договора
UPDATE active_life_insurance_view
SET contract_status = 'Завершён' -- изменение статуса
WHERE id = 7;
-- Ошибка: "ORA-00904: "CONTRACT_STATUS": недопустимый идентификатор"

-- Вертикальное/смешанное необновляемое представление
-- Детальное представление договоров с полной информацией (без ID автоинкремента)
CREATE OR REPLACE VIEW insurance_contracts_detailed_view AS
SELECT ic.contract_date                    AS "Дата_договора",
       ic.contract_status                  AS "Статус",
       ic.premium                          AS "Премия",
       ic.unpaid_premium                   AS "Неуплаченная_премия",

       c.first_name                        AS "Имя_клиента",
       c.last_name                         AS "Фамилия_клиента",
       TO_CHAR(c.birth_date, 'DD.MM.YYYY') AS "Дата_рождения_клиента",
       c.phone_number                      AS "Телефон_клиента",

       a.first_name                        AS "Имя_агента",
       a.last_name                         AS "Фамилия_агента",
       a.phone_number                      AS "Телефон_агента",

       it.name                             AS "Тип_страхования",
       it.max_payout                       AS "Макс_выплата",
       it.age_limit                        AS "Возрастной_лимит"
FROM insurance_contract ic
         FULL JOIN client c ON ic.client_id = c.id
         FULL JOIN agent a ON ic.agent_id = a.id
         FULL JOIN insurance_type it ON ic.insurance_type_id = it.id
ORDER BY ic.contract_date DESC;

-- Доказательство необновляемости представления

-- 1. INSERT - попытка вставить новую запись
INSERT INTO insurance_contracts_detailed_view ("Дата_договора", "Статус", "Премия", "Имя_клиента", "Фамилия_клиента",
                                               "Имя_агента", "Фамилия_агента", "Тип_страхования")
VALUES (SYSDATE, 'Активен', 1500, 'Новый', 'Клиент', 'Новый', 'Агент', 'Жизнь');
-- Ошибка: "ORA-01733: виртуальный столбец здесь недопустим"

-- 2. UPDATE - попытка обновить данные
UPDATE insurance_contracts_detailed_view
SET "Премия" = 2000
WHERE "Фамилия_клиента" = 'Петров';
-- Ошибка: "ORA-01733: виртуальный столбец здесь недопустим"

-- 3. DELETE - попытка удалить запись
DELETE
FROM insurance_contracts_detailed_view
WHERE "Фамилия_клиента" = 'Сидорова';
-- Ошибка: "ORA-01752: не могу удалять из представления без таблицы, сохраняющей ключ"

-- Представление для работы с клиентами только в рабочие дни и часы
CREATE OR REPLACE VIEW clients_working_hours_view AS
SELECT
    id,
    first_name,
    last_name,
    birth_date,
    phone_number
FROM client
WITH CHECK OPTION;

-- Триггер для ограничения по времени работы
CREATE OR REPLACE TRIGGER clients_working_hours_trigger
    INSTEAD OF INSERT OR UPDATE OR DELETE ON clients_working_hours_view
    FOR EACH ROW
DECLARE
    v_current_day   VARCHAR2(20);
    v_current_hour  NUMBER;
    v_timezone      VARCHAR2(50);
    v_current_time  TIMESTAMP WITH TIME ZONE;
BEGIN
    SELECT DBTIMEZONE INTO v_timezone FROM dual;

    v_current_time := FROM_TZ(CAST(SYSDATE AS TIMESTAMP), v_timezone);
    v_current_day := TO_CHAR(v_current_time, 'DY', 'NLS_DATE_LANGUAGE=RUSSIAN');
    v_current_hour := EXTRACT(HOUR FROM v_current_time);

    IF v_current_day IN ('СБ','ВС') THEN
        RAISE_APPLICATION_ERROR(-20001,
                                'Операции разрешены только в рабочие дни (пн–пт). Сегодня: ' || v_current_day);
    END IF;

    IF v_current_hour < 9 OR v_current_hour >= 17 THEN
        RAISE_APPLICATION_ERROR(-20002,
                                'Операции разрешены только с 9:00 до 17:00. Сейчас: ' || v_current_hour || ':00');
    END IF;

    CASE
        WHEN INSERTING THEN
            INSERT INTO client (id, first_name, last_name, birth_date, phone_number)
            VALUES (:NEW.id, :NEW.first_name, :NEW.last_name, :NEW.birth_date, :NEW.phone_number);

        WHEN UPDATING THEN
            UPDATE client
            SET first_name   = :NEW.first_name,
                last_name    = :NEW.last_name,
                birth_date   = :NEW.birth_date,
                phone_number = :NEW.phone_number
            WHERE id = :OLD.id;

        WHEN DELETING THEN
            DELETE FROM client WHERE id = :OLD.id;
        END CASE;
END;

-- для проверки
INSERT INTO clients_working_hours_view (id, first_name, last_name, birth_date, phone_number)
VALUES (100, 'Тест', 'Тестов', DATE '1990-01-01', '+375291234599');

-- [2025-09-28 19:56:55] 	ORA-20001: Операции разрешены только в рабочие дни (пн–пт). Сегодня: ВС
-- [2025-09-28 19:56:55] 	ORA-06512: на  "EVLAD.CLIENTS_WORKING_HOURS_TRIGGER", line 19
-- [2025-09-28 19:56:55] 	ORA-04088: ошибка во время выполнения триггера 'EVLAD.CLIENTS_WORKING_HOURS_TRIGGER'





