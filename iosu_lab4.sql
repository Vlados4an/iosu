-- Вариант 16. Создать процедуру, увеличивающую на заданный процент заработную плату агентам, которые заключили наибольшее количество страхо-вых договоров.
-- Написать функцию, возвращающую количество клиентов, у которых срок страхования подходит к концу. Вывести список клиентов и дату окончания кон-тракта.

--Создание процедуры
-- Процедура увеличивает зарплату агентам с наибольшим количеством договоров
CREATE OR REPLACE PROCEDURE increase_top_agents_salary(
    p_percentage IN NUMBER,
    p_top_count IN NUMBER DEFAULT 3
)
    IS
    CURSOR top_agents_cursor IS
        SELECT a.id,
               a.first_name,
               a.last_name,
               a.salary        AS current_salary,
               COUNT(ic.id)    AS contract_count,
               SUM(ic.premium) AS total_premium
        FROM agent a
                 JOIN insurance_contract ic ON a.id = ic.agent_id
        GROUP BY a.id, a.first_name, a.last_name, a.salary
        ORDER BY contract_count DESC, total_premium DESC
            FETCH FIRST p_top_count ROWS
        WITH TIES;
    v_updated_count NUMBER := 0;
    v_invalid_percentage EXCEPTION;
    v_new_salary NUMBER;
BEGIN
    IF p_percentage <= 0 OR p_percentage > 100 THEN
        RAISE v_invalid_percentage;
    END IF;

    IF p_top_count <= 0 THEN
        RAISE_APPLICATION_ERROR(-20010, 'Количество топ-агентов должно быть положительным числом');
    END IF;

    DBMS_OUTPUT.PUT_LINE('=== ПОВЫШЕНИЕ ЗАРПЛАТЫ ТОП-' || p_top_count || ' АГЕНТОВ НА ' || p_percentage || '% ===');

    FOR agent_rec IN top_agents_cursor
        LOOP
            BEGIN
                v_new_salary := agent_rec.current_salary * (1 + p_percentage / 100);

                UPDATE agent
                SET salary = v_new_salary
                WHERE id = agent_rec.id;

                v_updated_count := v_updated_count + 1;

                DBMS_OUTPUT.PUT_LINE('Агент: ' || agent_rec.first_name || ' ' || agent_rec.last_name ||
                                     ', Контрактов: ' || agent_rec.contract_count ||
                                     ', Прежняя зарплата: ' || agent_rec.current_salary ||
                                     ', Новая зарплата: ' || ROUND(v_new_salary, 2));

            EXCEPTION
                WHEN OTHERS THEN
                    DBMS_OUTPUT.PUT_LINE('Ошибка при обновлении агента ' || agent_rec.id || ': ' || SQLERRM);
            END;
        END LOOP;

    IF top_agents_cursor%ISOPEN THEN
        CLOSE top_agents_cursor;
    END IF;

    DBMS_OUTPUT.PUT_LINE('=== ОБНОВЛЕНО АГЕНТОВ: ' || v_updated_count || ' ===');

EXCEPTION
    WHEN v_invalid_percentage THEN
        RAISE_APPLICATION_ERROR(-20011, 'Процент повышения должен быть между 0 и 100');
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Не найдено агентов с договорами');
    WHEN TOO_MANY_ROWS THEN
        DBMS_OUTPUT.PUT_LINE('Найдено больше строк чем ожидалось');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Непредвиденная ошибка: ' || SQLERRM);
        RAISE;
END increase_top_agents_salary;
/

-- BEGIN
--     increase_top_agents_salary(p_percentage => 10, p_top_count => 3);
-- END;

--Создание функции
-- Функция возвращает количество клиентов с истекающими сроками оплаты по договорам
CREATE OR REPLACE FUNCTION get_expiring_contracts_count(
    p_days_threshold IN NUMBER DEFAULT 30
) RETURN NUMBER
    IS
    v_client_count   NUMBER := 0;
    TYPE client_cursor_type IS REF CURSOR;
    client_cursor    client_cursor_type;
    v_client_id      client.id%TYPE;
    v_first_name     client.first_name%TYPE;
    v_last_name      client.last_name%TYPE;
    v_contract_date  insurance_contract.contract_date%TYPE;
    v_deadline_date  DATE;
    v_days_remaining NUMBER;
BEGIN
    IF p_days_threshold <= 0 THEN
        RAISE_APPLICATION_ERROR(-20020, 'Пороговое значение дней должно быть положительным');
    END IF;

    DBMS_OUTPUT.PUT_LINE('=== КЛИЕНТЫ С ИСТЕКАЮЩИМИ СРОКАМИ ОПЛАТЫ (меньше ' || p_days_threshold || ' дней) ===');

    OPEN client_cursor FOR
        SELECT DISTINCT c.id,
                        c.first_name,
                        c.last_name,
                        ic.contract_date,
                        (ic.contract_date + ic.payout_deadline)                  AS deadline_date,
                        TRUNC((ic.contract_date + ic.payout_deadline) - SYSDATE) AS days_remaining
        FROM client c
                 JOIN insurance_contract ic ON c.id = ic.client_id
        WHERE ic.contract_status = 'Активен'
          AND TRUNC((ic.contract_date + ic.payout_deadline) - SYSDATE) < p_days_threshold
          AND TRUNC((ic.contract_date + ic.payout_deadline) - SYSDATE) >= 0
        ORDER BY days_remaining ASC;

    LOOP
        FETCH client_cursor INTO v_client_id, v_first_name, v_last_name, v_contract_date, v_deadline_date, v_days_remaining;
        EXIT WHEN client_cursor%NOTFOUND;

        v_client_count := v_client_count + 1;

        DBMS_OUTPUT.PUT_LINE('Клиент: ' || v_first_name || ' ' || v_last_name ||
                             ', Дата договора: ' || TO_CHAR(v_contract_date, 'DD.MM.YYYY') ||
                             ', Крайний срок оплаты: ' || TO_CHAR(v_deadline_date, 'DD.MM.YYYY') ||
                             ', Осталось дней: ' || v_days_remaining);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Обработано записей: ' || v_client_count);

    CLOSE client_cursor;

    RETURN v_client_count;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 0;
    WHEN OTHERS THEN
        IF client_cursor%ISOPEN THEN
            CLOSE client_cursor;
        END IF;
        DBMS_OUTPUT.PUT_LINE('Ошибка в функции: ' || SQLERRM);
        RAISE;
END get_expiring_contracts_count;
/


DECLARE
    v_count NUMBER;
BEGIN
    v_count := get_expiring_contracts_count(30);
    DBMS_OUTPUT.PUT_LINE('Найдено клиентов: ' || v_count);
END;

-- Создать локальную программу, изменив код ранее написанной проце-дуры или функции.
CREATE OR REPLACE PROCEDURE increase_top_agents_salary_local(
    p_percentage IN NUMBER,
    p_top_count IN NUMBER DEFAULT 3
)
    IS
    CURSOR top_agents_cursor IS
        SELECT a.id,
               a.first_name,
               a.last_name,
               a.salary        AS current_salary,
               COUNT(ic.id)    AS contract_count,
               SUM(ic.premium) AS total_premium
        FROM agent a
                 JOIN insurance_contract ic ON a.id = ic.agent_id
        GROUP BY a.id, a.first_name, a.last_name, a.salary
        ORDER BY contract_count DESC, total_premium DESC
            FETCH FIRST p_top_count ROWS ONLY;
    v_updated_count NUMBER := 0;
    v_new_salary    NUMBER;
    v_invalid_percentage EXCEPTION;

    -- Локальная процедура для валидации входных параметров
    PROCEDURE validate_parameters IS
    BEGIN
        IF p_percentage <= 0 OR p_percentage > 100 THEN
            RAISE v_invalid_percentage;
        END IF;

        IF p_top_count <= 0 THEN
            RAISE_APPLICATION_ERROR(-20010, 'Количество топ-агентов должно быть положительным числом');
        END IF;
    END validate_parameters;

    -- Локальная функция для расчета новой зарплаты
    FUNCTION calculate_new_salary(
        p_current_salary IN NUMBER
    ) RETURN NUMBER IS
    BEGIN
        RETURN p_current_salary * (1 + p_percentage / 100);
    END calculate_new_salary;

    -- Локальная процедура для обновления зарплаты агента
    PROCEDURE update_agent_salary(
        p_agent_id IN NUMBER,
        p_new_salary IN NUMBER
    ) IS
    BEGIN
        UPDATE agent
        SET salary = p_new_salary
        WHERE id = p_agent_id;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20012, 'Агент с ID ' || p_agent_id || ' не найден');
        END IF;
    END update_agent_salary;

    -- Локальная процедура для логирования информации об агенте
    PROCEDURE log_agent_info(
        p_first_name IN VARCHAR2,
        p_last_name IN VARCHAR2,
        p_contract_count IN NUMBER,
        p_current_salary IN NUMBER,
        p_new_salary IN NUMBER
    ) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('Агент: ' || p_first_name || ' ' || p_last_name ||
                             ', Контрактов: ' || p_contract_count ||
                             ', Прежняя зарплата: ' || p_current_salary ||
                             ', Новая зарплата: ' || ROUND(p_new_salary, 2));
    END log_agent_info;

BEGIN
    -- Валидация параметров
    validate_parameters;

    DBMS_OUTPUT.PUT_LINE('=== ПОВЫШЕНИЕ ЗАРПЛАТЫ ТОП-' || p_top_count || ' АГЕНТОВ НА ' || p_percentage || '% ===');

    -- Обработка топ-агентов
    FOR agent_rec IN top_agents_cursor
        LOOP
            BEGIN
                -- Расчет новой зарплаты
                v_new_salary := calculate_new_salary(agent_rec.current_salary);

                -- Обновление зарплаты
                update_agent_salary(agent_rec.id, v_new_salary);

                -- Логирование
                log_agent_info(
                        agent_rec.first_name,
                        agent_rec.last_name,
                        agent_rec.contract_count,
                        agent_rec.current_salary,
                        v_new_salary
                );

                v_updated_count := v_updated_count + 1;

            EXCEPTION
                WHEN OTHERS THEN
                    DBMS_OUTPUT.PUT_LINE('Ошибка при обновлении агента ' || agent_rec.id || ': ' || SQLERRM);
            END;
        END LOOP;

    -- Закрытие курсора (автоматически закрывается в FOR LOOP, но для безопасности)
    IF top_agents_cursor%ISOPEN THEN
        CLOSE top_agents_cursor;
    END IF;

    DBMS_OUTPUT.PUT_LINE('=== ОБНОВЛЕНО АГЕНТОВ: ' || v_updated_count || ' ===');

EXCEPTION
    WHEN v_invalid_percentage THEN
        RAISE_APPLICATION_ERROR(-20011, 'Процент повышения должен быть между 0 и 100');
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Не найдено агентов с договорами');
    WHEN TOO_MANY_ROWS THEN
        DBMS_OUTPUT.PUT_LINE('Найдено больше строк чем ожидалось');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Непредвиденная ошибка: ' || SQLERRM);
        RAISE;
END increase_top_agents_salary_local;
/

-- BEGIN
--     increase_top_agents_salary(p_percentage => 10, p_top_count => 3);
-- END;


-- Повышение зарплаты конкретного агента по фамилии (перегрузка)
CREATE OR REPLACE PROCEDURE increase_top_agents_salary(
    p_percentage IN NUMBER,
    p_agent_last_name IN VARCHAR2
) IS
    v_old_salary NUMBER;
    v_new_salary NUMBER;
BEGIN
    SELECT salary INTO v_old_salary FROM agent WHERE last_name = p_agent_last_name;

    v_new_salary := v_old_salary * (1 + p_percentage / 100);

    UPDATE agent
    SET salary = v_new_salary
    WHERE last_name = p_agent_last_name;

    DBMS_OUTPUT.PUT_LINE('Агент ' || p_agent_last_name || ': ' ||
                         v_old_salary || ' -> ' || v_new_salary);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Агент с id ' || p_agent_last_name || ' не найден');
END increase_top_agents_salary;
/

-- BEGIN
--     increase_top_agents_salary(p_percentage => 10, p_agent_last_name => 'Иванов');
-- END;

--Объединить все процедуры и функции, в том числе перегруженные, в пакет.
-- Спецификация пакета
CREATE OR REPLACE PACKAGE insurance_pkg IS
    -- Основная процедура: повышение зарплаты топ-N агентов
    PROCEDURE increase_top_agents_salary(
        p_percentage IN NUMBER,
        p_top_count IN NUMBER DEFAULT 3
    );

    -- Локальная версия с логированием
    PROCEDURE increase_top_agents_salary_local(
        p_percentage IN NUMBER,
        p_top_count IN NUMBER DEFAULT 3
    );

    -- Перегрузка – повышение зарплаты по фамилии агента
    PROCEDURE increase_top_agents_salary(
        p_percentage IN NUMBER,
        p_agent_last_name IN VARCHAR2
    );

    -- Функция для подсчёта клиентов с истекающими договорами
    FUNCTION get_expiring_contracts_count(
        p_days_threshold IN NUMBER DEFAULT 30
    ) RETURN NUMBER;
END insurance_pkg;
/

-- Тело пакета
CREATE OR REPLACE PACKAGE BODY insurance_pkg IS

    -- === Процедура 1: повышение зарплаты топ-N агентов ===
    PROCEDURE increase_top_agents_salary(
        p_percentage IN NUMBER,
        p_top_count IN NUMBER DEFAULT 3
    )
        IS
        v_updated_count NUMBER := 0;
        v_invalid_percentage EXCEPTION;
        v_invalid_top_count EXCEPTION;
        v_new_salary NUMBER;
        v_min_agent_id NUMBER; -- для проверки
    BEGIN
        -- Проверка параметров
        IF p_percentage <= 0 OR p_percentage > 100 THEN
            RAISE v_invalid_percentage;
        END IF;

        IF p_top_count <= 0 THEN
            RAISE v_invalid_top_count;
        END IF;

        DBMS_OUTPUT.PUT_LINE('=== Повышение зарплаты ТОП-' || p_top_count || ' агентов на ' || p_percentage || '% ===');

        IF p_top_count >= 100 THEN
            SELECT id
            INTO v_min_agent_id
            FROM (
                     SELECT a.id,
                            ROW_NUMBER() OVER (ORDER BY COUNT(ic.id) DESC, SUM(ic.premium) DESC) AS rn
                     FROM agent a
                              JOIN insurance_contract ic ON a.id = ic.agent_id
                     GROUP BY a.id
                 )
            WHERE rn = p_top_count;
        END IF;

        -- Обновляем через цикл
        FOR agent_rec IN (
            SELECT a.id,
                   a.first_name,
                   a.last_name,
                   a.salary        AS current_salary,
                   COUNT(ic.id)    AS contract_count,
                   SUM(ic.premium) AS total_premium
            FROM agent a
                     JOIN insurance_contract ic ON a.id = ic.agent_id
            GROUP BY a.id, a.first_name, a.last_name, a.salary
            ORDER BY contract_count DESC, total_premium DESC
                FETCH FIRST p_top_count ROWS ONLY
            )
            LOOP
                v_new_salary := agent_rec.current_salary * (1 + p_percentage / 100);

                UPDATE agent
                SET salary = v_new_salary
                WHERE id = agent_rec.id;

                v_updated_count := v_updated_count + 1;

                DBMS_OUTPUT.PUT_LINE('Агент: ' || agent_rec.first_name || ' ' || agent_rec.last_name ||
                                     ', Прежняя зарплата: ' || agent_rec.current_salary ||
                                     ', Новая зарплата: ' || ROUND(v_new_salary, 2));
            END LOOP;

        DBMS_OUTPUT.PUT_LINE('=== Обновлено агентов: ' || v_updated_count || ' ===');

    EXCEPTION
        WHEN v_invalid_percentage THEN
            DBMS_OUTPUT.PUT_LINE('❌ Ошибка: процент повышения должен быть между 0 и 100');
        WHEN v_invalid_top_count THEN
            DBMS_OUTPUT.PUT_LINE('❌ Ошибка: количество топ-агентов должно быть положительным');
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('❌ Предустановленное исключение: агентов для обновления не найдено');
        WHEN TOO_MANY_ROWS THEN
            DBMS_OUTPUT.PUT_LINE('❌ Предустановленное исключение: найдено больше строк, чем ожидалось');
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('❌ Непредвиденная ошибка: ' || SQLERRM);
    END increase_top_agents_salary;



-- === Процедура 2: локальная версия с логированием ===
    PROCEDURE increase_top_agents_salary_local(
        p_percentage IN NUMBER,
        p_top_count IN NUMBER DEFAULT 3
    )
        IS
        CURSOR top_agents_cursor IS
            SELECT a.id,
                   a.first_name,
                   a.last_name,
                   a.salary        AS current_salary,
                   COUNT(ic.id)    AS contract_count,
                   SUM(ic.premium) AS total_premium
            FROM agent a
                     JOIN insurance_contract ic ON a.id = ic.agent_id
            GROUP BY a.id, a.first_name, a.last_name, a.salary
            ORDER BY contract_count DESC, total_premium DESC
                FETCH FIRST p_top_count ROWS ONLY;
        v_updated_count NUMBER := 0;
        v_new_salary    NUMBER;
        v_invalid_percentage EXCEPTION;

        -- Локальная процедура для валидации входных параметров
        PROCEDURE validate_parameters IS
        BEGIN
            IF p_percentage <= 0 OR p_percentage > 100 THEN
                RAISE v_invalid_percentage;
            END IF;

            IF p_top_count <= 0 THEN
                RAISE_APPLICATION_ERROR(-20010, 'Количество топ-агентов должно быть положительным числом');
            END IF;
        END validate_parameters;

        -- Локальная функция для расчета новой зарплаты
        FUNCTION calculate_new_salary(
            p_current_salary IN NUMBER
        ) RETURN NUMBER IS
        BEGIN
            RETURN p_current_salary * (1 + p_percentage / 100);
        END calculate_new_salary;

        -- Локальная процедура для обновления зарплаты агента
        PROCEDURE update_agent_salary(
            p_agent_id IN NUMBER,
            p_new_salary IN NUMBER
        ) IS
        BEGIN
            UPDATE agent
            SET salary = p_new_salary
            WHERE id = p_agent_id;

            IF SQL%ROWCOUNT = 0 THEN
                RAISE_APPLICATION_ERROR(-20012, 'Агент с ID ' || p_agent_id || ' не найден');
            END IF;
        END update_agent_salary;

        -- Локальная процедура для логирования информации об агенте
        PROCEDURE log_agent_info(
            p_first_name IN VARCHAR2,
            p_last_name IN VARCHAR2,
            p_contract_count IN NUMBER,
            p_current_salary IN NUMBER,
            p_new_salary IN NUMBER
        ) IS
        BEGIN
            DBMS_OUTPUT.PUT_LINE('Агент: ' || p_first_name || ' ' || p_last_name ||
                                 ', Контрактов: ' || p_contract_count ||
                                 ', Прежняя зарплата: ' || p_current_salary ||
                                 ', Новая зарплата: ' || ROUND(p_new_salary, 2));
        END log_agent_info;

    BEGIN
        -- Валидация параметров
        validate_parameters;

        DBMS_OUTPUT.PUT_LINE('=== ПОВЫШЕНИЕ ЗАРПЛАТЫ ТОП-' || p_top_count || ' АГЕНТОВ НА ' || p_percentage || '% ===');

        -- Обработка топ-агентов
        FOR agent_rec IN top_agents_cursor
            LOOP
                BEGIN
                    -- Расчет новой зарплаты
                    v_new_salary := calculate_new_salary(agent_rec.current_salary);

                    -- Обновление зарплаты
                    update_agent_salary(agent_rec.id, v_new_salary);

                    -- Логирование
                    log_agent_info(
                            agent_rec.first_name,
                            agent_rec.last_name,
                            agent_rec.contract_count,
                            agent_rec.current_salary,
                            v_new_salary
                    );

                    v_updated_count := v_updated_count + 1;

                EXCEPTION
                    WHEN OTHERS THEN
                        DBMS_OUTPUT.PUT_LINE('Ошибка при обновлении агента ' || agent_rec.id || ': ' || SQLERRM);
                END;
            END LOOP;

        -- Закрытие курсора (автоматически закрывается в FOR LOOP, но для безопасности)
        IF top_agents_cursor%ISOPEN THEN
            CLOSE top_agents_cursor;
        END IF;

        DBMS_OUTPUT.PUT_LINE('=== ОБНОВЛЕНО АГЕНТОВ: ' || v_updated_count || ' ===');

    EXCEPTION
        WHEN v_invalid_percentage THEN
            RAISE_APPLICATION_ERROR(-20011, 'Процент повышения должен быть между 0 и 100');
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Не найдено агентов с договорами');
        WHEN TOO_MANY_ROWS THEN
            DBMS_OUTPUT.PUT_LINE('Найдено больше строк чем ожидалось');
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Непредвиденная ошибка: ' || SQLERRM);
            RAISE;
    END increase_top_agents_salary_local;


    -- === Процедура 3: перегрузка по фамилии агента ===
    PROCEDURE increase_top_agents_salary(
        p_percentage IN NUMBER,
        p_agent_last_name IN VARCHAR2
    ) IS
        v_old_salary NUMBER;
        v_new_salary NUMBER;
    BEGIN
        SELECT salary INTO v_old_salary FROM agent WHERE last_name = p_agent_last_name;

        v_new_salary := v_old_salary * (1 + p_percentage / 100);

        UPDATE agent
        SET salary = v_new_salary
        WHERE last_name = p_agent_last_name;

        DBMS_OUTPUT.PUT_LINE('Агент ' || p_agent_last_name || ': ' ||
                             v_old_salary || ' -> ' || v_new_salary);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Агент с id ' || p_agent_last_name || ' не найден');
    END increase_top_agents_salary;


    -- === Функция: клиенты с истекающими договорами ===
    FUNCTION get_expiring_contracts_count(
        p_days_threshold IN NUMBER DEFAULT 30
    ) RETURN NUMBER
        IS
        v_client_count   NUMBER := 0;
        TYPE client_cursor_type IS REF CURSOR;
        client_cursor    client_cursor_type;
        v_client_id      client.id%TYPE;
        v_first_name     client.first_name%TYPE;
        v_last_name      client.last_name%TYPE;
        v_contract_date  insurance_contract.contract_date%TYPE;
        v_deadline_date  DATE;
        v_days_remaining NUMBER;
    BEGIN
        IF p_days_threshold <= 0 THEN
            RAISE_APPLICATION_ERROR(-20020, 'Пороговое значение дней должно быть положительным');
        END IF;

        DBMS_OUTPUT.PUT_LINE('=== КЛИЕНТЫ С ИСТЕКАЮЩИМИ СРОКАМИ ОПЛАТЫ (меньше ' || p_days_threshold || ' дней) ===');

        OPEN client_cursor FOR
            SELECT DISTINCT c.id,
                            c.first_name,
                            c.last_name,
                            ic.contract_date,
                            (ic.contract_date + ic.payout_deadline)                  AS deadline_date,
                            TRUNC((ic.contract_date + ic.payout_deadline) - SYSDATE) AS days_remaining
            FROM client c
                     JOIN insurance_contract ic ON c.id = ic.client_id
            WHERE ic.contract_status = 'Активен'
              AND TRUNC((ic.contract_date + ic.payout_deadline) - SYSDATE) < p_days_threshold
              AND TRUNC((ic.contract_date + ic.payout_deadline) - SYSDATE) >= 0
            ORDER BY days_remaining ASC;

        LOOP
            FETCH client_cursor INTO v_client_id, v_first_name, v_last_name, v_contract_date, v_deadline_date, v_days_remaining;
            EXIT WHEN client_cursor%NOTFOUND;

            v_client_count := v_client_count + 1;

            DBMS_OUTPUT.PUT_LINE('Клиент: ' || v_first_name || ' ' || v_last_name ||
                                 ', Дата договора: ' || TO_CHAR(v_contract_date, 'DD.MM.YYYY') ||
                                 ', Крайний срок оплаты: ' || TO_CHAR(v_deadline_date, 'DD.MM.YYYY') ||
                                 ', Осталось дней: ' || v_days_remaining);
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('Обработано записей: ' || v_client_count);

        CLOSE client_cursor;

        RETURN v_client_count;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 0;
        WHEN OTHERS THEN
            IF client_cursor%ISOPEN THEN
                CLOSE client_cursor;
            END IF;
            DBMS_OUTPUT.PUT_LINE('Ошибка в функции: ' || SQLERRM);
            RAISE;
    END get_expiring_contracts_count;
END insurance_pkg;
/

-- Анонимный блок для тестирования пакета insurance_pkg
DECLARE
    v_expiring_count  NUMBER;
    v_test_agent_name VARCHAR2(30) := 'Сергеев';
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТИРОВАНИЕ ПАКЕТА INSURANCE_PKG ===');
    DBMS_OUTPUT.PUT_LINE('');

    -- Тест 1: Основная процедура с нормальными параметрами
    DBMS_OUTPUT.PUT_LINE('ТЕСТ 1: Повышение зарплаты топ-3 агентов на 10%');
    BEGIN
        insurance_pkg.increase_top_agents_salary(
                p_percentage => 10,
                p_top_count => 3
        );
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка в тесте 1: ' || SQLERRM);
    END;
    DBMS_OUTPUT.PUT_LINE('');

    -- Тест 2: Процедура с другим количеством агентов
    DBMS_OUTPUT.PUT_LINE('ТЕСТ 2: Повышение зарплаты топ-5 агентов на 5%');
    BEGIN
        insurance_pkg.increase_top_agents_salary(
                p_percentage => 5,
                p_top_count => 5
        );
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка в тесте 2: ' || SQLERRM);
    END;
    DBMS_OUTPUT.PUT_LINE('');

    -- Тест 3: Процедура с неверным процентом (должна вызвать ошибку)
    DBMS_OUTPUT.PUT_LINE('ТЕСТ 3: Попытка повышения на 0% (должна быть ошибка)');
    BEGIN
        insurance_pkg.increase_top_agents_salary(
                p_percentage => 0,
                p_top_count => 3
        );
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ожидаемая ошибка: ' || SQLERRM);
    END;
    DBMS_OUTPUT.PUT_LINE('');

    -- Тест 4: Процедура с отрицательным количеством агентов (должна вызвать ошибку)
    DBMS_OUTPUT.PUT_LINE('ТЕСТ 4: Попытка повышения для -1 агентов (должна быть ошибка)');
    BEGIN
        insurance_pkg.increase_top_agents_salary(
                p_percentage => 10,
                p_top_count => -1
        );
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ожидаемая ошибка: ' || SQLERRM);
    END;
    DBMS_OUTPUT.PUT_LINE('');

    -- Тест 5: Локальная версия с логированием
    DBMS_OUTPUT.PUT_LINE('ТЕСТ 5: Локальная версия с логированием');
    BEGIN
        insurance_pkg.increase_top_agents_salary_local(
                p_percentage => 8,
                p_top_count => 2
        );
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка в тесте 5: ' || SQLERRM);
    END;
    DBMS_OUTPUT.PUT_LINE('');

    -- Тест 6: Перегруженная процедура для конкретного агента
    DBMS_OUTPUT.PUT_LINE('ТЕСТ 6: Повышение зарплаты конкретному агенту (ID=' || v_test_agent_name || ')');
    BEGIN
        insurance_pkg.increase_top_agents_salary(
                p_percentage => 15,
                p_agent_last_name => v_test_agent_name
        );
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка в тесте 6: ' || SQLERRM);
    END;
    DBMS_OUTPUT.PUT_LINE('');

    -- Тест 7: Перегруженная процедура для несуществующего агента
    DBMS_OUTPUT.PUT_LINE('ТЕСТ 7: Попытка повышения для несуществующего агента (p_agent_last_name=Курапаткин)');
    BEGIN
        insurance_pkg.increase_top_agents_salary(
                p_percentage => 10,
                p_agent_last_name => 'Курапаткин'
        );
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка в тесте 7: ' || SQLERRM);
    END;
    DBMS_OUTPUT.PUT_LINE('');

    -- Тест 8: Функция подсчёта клиентов с истекающими договорами (стандартный порог)
    DBMS_OUTPUT.PUT_LINE('ТЕСТ 8: Клиенты с истекающими договорами (порог 30 дней)');
    BEGIN
        v_expiring_count := insurance_pkg.get_expiring_contracts_count(30);
        DBMS_OUTPUT.PUT_LINE('Найдено клиентов: ' || v_expiring_count);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка в тесте 8: ' || SQLERRM);
    END;
    DBMS_OUTPUT.PUT_LINE('');

    -- Тест 9: Функция с другим порогом
    DBMS_OUTPUT.PUT_LINE('ТЕСТ 9: Клиенты с истекающими договорами (порог 60 дней)');
    BEGIN
        v_expiring_count := insurance_pkg.get_expiring_contracts_count(60);
        DBMS_OUTPUT.PUT_LINE('Найдено клиентов: ' || v_expiring_count);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка в тесте 9: ' || SQLERRM);
    END;
    DBMS_OUTPUT.PUT_LINE('');

    -- Тест 10: Функция с порогом по умолчанию
    DBMS_OUTPUT.PUT_LINE('ТЕСТ 10: Клиенты с истекающими договорами (порог по умолчанию)');
    BEGIN
        v_expiring_count := insurance_pkg.get_expiring_contracts_count();
        DBMS_OUTPUT.PUT_LINE('Найдено клиентов: ' || v_expiring_count);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка в тесте 10: ' || SQLERRM);
    END;
    DBMS_OUTPUT.PUT_LINE('');

    -- Тест 11: Комплексный тест - несколько вызовов подряд
    DBMS_OUTPUT.PUT_LINE('ТЕСТ 11: Комплексный тест');
    BEGIN
        -- Повышение топ-агенту
        insurance_pkg.increase_top_agents_salary(20, v_test_agent_name);

        -- Проверка истекающих договоров
        v_expiring_count := insurance_pkg.get_expiring_contracts_count(45);
        DBMS_OUTPUT.PUT_LINE('Комплексный тест - истекающих договоров: ' || v_expiring_count);

        -- Повышение топ-агентам
        insurance_pkg.increase_top_agents_salary_local(7, 4);

        DBMS_OUTPUT.PUT_LINE('Комплексный тест завершен успешно');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка в комплексном тесте: ' || SQLERRM);
    END;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТИРОВАНИЕ ЗАВЕРШЕНО ===');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Критическая ошибка в анонимном блоке: ' || SQLERRM);
END;
/CREATE OR REPLACE VIEW clients_working_hours_view AS
SELECT id,
       first_name,
       last_name,
       birth_date,
       phone_number
FROM client
WHERE TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'Europe/Moscow', 'DY', 'NLS_DATE_LANGUAGE=RUSSIAN') NOT IN ('СБ', 'ВС')
  AND EXTRACT(HOUR FROM (SYSTIMESTAMP AT TIME ZONE 'Europe/Moscow')) BETWEEN 9 AND 22
WITH CHECK OPTION;


--по одному вызову
DECLARE
    v_count NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== Запуск всех процедур и функций из insurance_pkg ===');

    DBMS_OUTPUT.PUT_LINE('=== Тест 1: успешный вызов ===');
    insurance_pkg.increase_top_agents_salary(10, 3);

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== Тест 2: предустановленное исключение (NO_DATA_FOUND) ===');
    insurance_pkg.increase_top_agents_salary(10, 1000);

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== Тест 3: собственное исключение (v_invalid_percentage) ===');
    insurance_pkg.increase_top_agents_salary(200, 3);

    -- 2. Локальная версия процедуры с логированием
    insurance_pkg.increase_top_agents_salary_local(
            p_percentage => 8,
            p_top_count => 2
    );

    -- 3. Перегруженная процедура: повышение зарплаты по фамилии агента
    insurance_pkg.increase_top_agents_salary(
            p_percentage => 15,
            p_agent_last_name => 'Иванов'
    );

    -- 4. Функция: количество клиентов с истекающими договорами
    v_count := insurance_pkg.get_expiring_contracts_count(30);
    DBMS_OUTPUT.PUT_LINE('Клиентов с истекающими договорами (30 дней): ' || v_count);

    -- 5. Функция с параметром по умолчанию
    v_count := insurance_pkg.get_expiring_contracts_count;
    DBMS_OUTPUT.PUT_LINE('Клиентов с истекающими договорами (по умолчанию): ' || v_count);

    DBMS_OUTPUT.PUT_LINE('=== Все вызовы пакета выполнены ===');
END;
/



