
CREATE OR REPLACE TYPE t_table_list IS TABLE OF VARCHAR2(100);
/

CREATE OR REPLACE TYPE t_join_pair AS OBJECT (
                                                 table1 VARCHAR2(100),
                                                 table2 VARCHAR2(100),
                                                 column1 VARCHAR2(100),
                                                 column2 VARCHAR2(100)
                                             );
/

CREATE OR REPLACE TYPE t_join_list IS TABLE OF t_join_pair;
/

CREATE OR REPLACE PROCEDURE exec_dynamic_join_select(
    p_tables  IN t_table_list,
    p_params  IN t_param_list DEFAULT NULL,
    p_joins   IN t_join_list  DEFAULT NULL,
    p_result  OUT t_result_collection
) AUTHID CURRENT_USER IS
    l_query      VARCHAR2(32767);
    l_from       VARCHAR2(32767) := '';
    l_where      VARCHAR2(4000) := '';
    l_cursor     INTEGER;
    l_col_cnt    INTEGER;
    l_desc_tab   DBMS_SQL.DESC_TAB;
    l_varchar    VARCHAR2(4000);
    l_status     INTEGER;
    l_row_data   t_row_data;
    l_row_count  NUMBER := 0;
    l_join_found BOOLEAN := FALSE;
BEGIN
    -- Формируем FROM с JOIN'ами (авто-связывание по FK или через p_joins)
    IF p_tables.COUNT = 1 THEN
        l_from := p_tables(1);
    ELSE
        l_from := p_tables(1);

        FOR i IN 2 .. p_tables.COUNT LOOP
                l_join_found := FALSE;

                -- 1) Пытаемся найти FK в словаре данных и правильно сопоставить колонки
                FOR fk_row IN (
                    SELECT
                        a.table_name  AS child_table,
                        a.column_name AS child_column,
                        p_col.table_name  AS parent_table,
                        p_col.column_name AS parent_column
                    FROM user_constraints c
                             JOIN user_cons_columns a
                                  ON c.constraint_name = a.constraint_name
                             JOIN user_cons_columns p_col
                                  ON c.r_constraint_name = p_col.constraint_name
                                      AND a.position = p_col.position
                    WHERE c.constraint_type = 'R'
                      AND (
                        (a.table_name = UPPER(p_tables(i)) AND p_col.table_name = UPPER(p_tables(i - 1)))
                            OR (a.table_name = UPPER(p_tables(i - 1)) AND p_col.table_name = UPPER(p_tables(i)))
                        )
                    ) LOOP
                        -- Ключевая правка: всегда присоединяем p_tables(i) (таблицу, которую добавляем в FROM)
                        IF fk_row.child_table = UPPER(p_tables(i)) AND fk_row.parent_table = UPPER(p_tables(i-1)) THEN
                            l_from := l_from || ' JOIN ' || p_tables(i) ||
                                      ' ON ' || fk_row.child_table || '.' || fk_row.child_column ||
                                      ' = ' || fk_row.parent_table || '.' || fk_row.parent_column;
                        ELSE
                            -- обратный порядок (child в предыдущей таблице)
                            l_from := l_from || ' JOIN ' || p_tables(i) ||
                                      ' ON ' || fk_row.parent_table || '.' || fk_row.parent_column ||
                                      ' = ' || fk_row.child_table || '.' || fk_row.child_column;
                        END IF;

                        l_join_found := TRUE;
                        EXIT; -- достаточно одного FK между текущими таблицами
                    END LOOP;

                -- 2) Если FK не найден — пробуем явно переданные джойны
                IF NOT l_join_found AND p_joins IS NOT NULL THEN
                    FOR j IN 1 .. p_joins.COUNT LOOP
                            IF (UPPER(p_joins(j).table1) = UPPER(p_tables(i)) AND UPPER(p_joins(j).table2) = UPPER(p_tables(i - 1)))
                                OR (UPPER(p_joins(j).table2) = UPPER(p_tables(i)) AND UPPER(p_joins(j).table1) = UPPER(p_tables(i - 1))) THEN

                                -- Собираем JOIN: присоединяем p_tables(i), но ON строим по p_joins
                                l_from := l_from || ' JOIN ' || p_tables(i) ||
                                          ' ON ' || p_joins(j).table1 || '.' || p_joins(j).column1 ||
                                          ' = ' || p_joins(j).table2 || '.' || p_joins(j).column2;
                                l_join_found := TRUE;
                                EXIT;
                            END IF;
                        END LOOP;
                END IF;

                IF NOT l_join_found THEN
                    DBMS_OUTPUT.PUT_LINE('⚠️ Не удалось автоматически связать ' || p_tables(i - 1) || ' и ' || p_tables(i));
                    -- при необходимости: RAISE_APPLICATION_ERROR(...)
                END IF;
            END LOOP;
    END IF;

    -- WHERE из параметров (как было)
    IF p_params IS NOT NULL AND p_params.COUNT > 0 THEN
        l_where := ' WHERE ';
        FOR i IN 1 .. p_params.COUNT LOOP
                IF i > 1 THEN
                    l_where := l_where || ' AND ';
                END IF;
                l_where := l_where || p_params(i).param_name || ' = ''' || p_params(i).param_value || '''';
            END LOOP;
    END IF;

    -- Финальный запрос
    l_query := 'SELECT * FROM ' || l_from || l_where;

    DBMS_OUTPUT.PUT_LINE('=================================');
    DBMS_OUTPUT.PUT_LINE('SQL: ' || l_query);
    DBMS_OUTPUT.PUT_LINE('=================================');

    -- Выполнение через DBMS_SQL
    l_cursor := DBMS_SQL.OPEN_CURSOR;
    DBMS_SQL.PARSE(l_cursor, l_query, DBMS_SQL.NATIVE);

    DBMS_SQL.DESCRIBE_COLUMNS(l_cursor, l_col_cnt, l_desc_tab);
    FOR i IN 1 .. l_col_cnt LOOP
            DBMS_SQL.DEFINE_COLUMN(l_cursor, i, l_varchar, 4000);
        END LOOP;

    l_status := DBMS_SQL.EXECUTE(l_cursor);
    p_result := t_result_collection();

    WHILE DBMS_SQL.FETCH_ROWS(l_cursor) > 0 LOOP
            l_row_count := l_row_count + 1;
            l_row_data := t_row_data();
            l_row_data.EXTEND(l_col_cnt);

            FOR i IN 1 .. l_col_cnt LOOP
                    DBMS_SQL.COLUMN_VALUE(l_cursor, i, l_varchar);
                    l_row_data(i) := l_desc_tab(i).col_name || '=' || NVL(l_varchar, 'NULL');
                END LOOP;

            p_result.EXTEND;
            p_result(p_result.COUNT) := t_result_row(l_row_data, l_row_count);
        END LOOP;

    DBMS_OUTPUT.PUT_LINE('Найдено строк: ' || l_row_count);
    DBMS_SQL.CLOSE_CURSOR(l_cursor);

EXCEPTION
    WHEN OTHERS THEN
        IF DBMS_SQL.IS_OPEN(l_cursor) THEN
            DBMS_SQL.CLOSE_CURSOR(l_cursor);
        END IF;
        RAISE;
END exec_dynamic_join_select;
/

DECLARE
    l_tables t_table_list := t_table_list('INSURANCE_CONTRACT', 'COMPENSATION_CLAIM', 'INSURANCE_CASE');
    l_params t_param_list := t_param_list(
            t_param_pair('INSURANCE_CONTRACT.CONTRACT_STATUS', 'Активен')
                             );
    l_result t_result_collection;
    l_row t_result_row;
BEGIN
    exec_dynamic_join_select(l_tables, l_params, NULL, l_result);

    DBMS_OUTPUT.PUT_LINE('--- Результаты ---');
    FOR i IN 1 .. l_result.COUNT LOOP
            l_row := l_result(i);
            DBMS_OUTPUT.PUT_LINE('Строка ' || i);
            FOR j IN 1 .. l_row.row_values.COUNT LOOP
                    DBMS_OUTPUT.PUT_LINE('  ' || l_row.row_values(j));
                END LOOP;
            DBMS_OUTPUT.PUT_LINE('---');
        END LOOP;
END;
/




DECLARE
    l_tables t_table_list := t_table_list('INSURANCE_CONTRACT', 'CLIENT');
    l_joins t_join_list := t_join_list(
            t_join_pair('INSURANCE_CONTRACT', 'CLIENT', 'ID', 'CLIENT_ID')
                           );
    l_result t_result_collection;
    l_row t_result_row;
BEGIN
    exec_dynamic_join_select(l_tables, NULL, l_joins, l_result);

    DBMS_OUTPUT.PUT_LINE('--- Результаты ---');
    FOR i IN 1 .. l_result.COUNT LOOP
            l_row := l_result(i);
            DBMS_OUTPUT.PUT_LINE('Строка ' || i);
            FOR j IN 1 .. l_row.row_values.COUNT LOOP
                    DBMS_OUTPUT.PUT_LINE('  ' || l_row.row_values(j));
                END LOOP;
            DBMS_OUTPUT.PUT_LINE('---');
        END LOOP;
END;
/






-- Создание нового объекта динамически (таблицы или представления)
CREATE OR REPLACE PROCEDURE create_object(
    p_obj_type   IN VARCHAR2,
    p_src_table  IN VARCHAR2,
    p_columns    IN VARCHAR2,
    p_rowcount   IN NUMBER
) AUTHID CURRENT_USER IS
    l_cnt       INTEGER;
    l_sql       VARCHAR2(4000);
    l_new_name  VARCHAR2(200);
    l_base_name VARCHAR2(200);
    l_suffix    INTEGER := 1;
BEGIN
    IF UPPER(p_obj_type) = 'TABLE' THEN
        l_base_name := 'T_' || UPPER(p_src_table) || '_COPY_' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS');
    ELSIF UPPER(p_obj_type) = 'VIEW' THEN
        l_base_name := 'V_' || UPPER(p_src_table) || '_VIEW_' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS');
    ELSE
        RAISE_APPLICATION_ERROR(-20002, 'Тип объекта должен быть TABLE или VIEW');
    END IF;

    l_new_name := l_base_name;

    LOOP
        SELECT COUNT(*)
        INTO l_cnt
        FROM user_objects
        WHERE object_name = l_new_name;

        EXIT WHEN l_cnt = 0;
        l_new_name := l_base_name || '_' || l_suffix;
        l_suffix := l_suffix + 1;
    END LOOP;

    IF UPPER(p_obj_type) = 'TABLE' THEN
        l_sql := 'CREATE TABLE ' || l_new_name || ' AS SELECT ' || p_columns ||
                 ' FROM ' || p_src_table || ' WHERE ROWNUM <= ' || p_rowcount;
    ELSE
        l_sql := 'CREATE VIEW ' || l_new_name || ' AS SELECT ' || p_columns ||
                 ' FROM ' || p_src_table || ' WHERE ROWNUM <= ' || p_rowcount;
    END IF;

    EXECUTE IMMEDIATE l_sql;

    DBMS_OUTPUT.PUT_LINE('Объект "' || l_new_name || '" успешно создан.');
END;
/



BEGIN
    create_object(
            p_obj_type  => 'TABLE',
            p_src_table => 'CLIENT',
            p_columns   => 'id, first_name, last_name, phone_number',
            p_rowcount  => 3
    );

    create_object(
            p_obj_type  => 'VIEW',
            p_src_table => 'CLIENT',
            p_columns   => 'first_name, last_name',
            p_rowcount  => 5
    );
END;
/

CREATE OR REPLACE PROCEDURE get_column_stats(
    p_table_name IN VARCHAR2,
    p_column_name IN VARCHAR2
) AUTHID DEFINER  IS
    l_sql       VARCHAR2(4000);
    l_cnt       NUMBER;
    l_distinct  NUMBER;
    l_nulls     NUMBER;
BEGIN
    l_sql := 'SELECT COUNT(*), COUNT(DISTINCT ' || p_column_name || '), ' ||
             'SUM(CASE WHEN ' || p_column_name || ' IS NULL THEN 1 ELSE 0 END) ' ||
             'FROM ' || p_table_name;

    EXECUTE IMMEDIATE l_sql INTO l_cnt, l_distinct, l_nulls;

    DBMS_OUTPUT.PUT_LINE('Таблица: ' || p_table_name);
    DBMS_OUTPUT.PUT_LINE('Поле: ' || p_column_name);
    DBMS_OUTPUT.PUT_LINE('Всего записей: ' || l_cnt);
    DBMS_OUTPUT.PUT_LINE('Уникальных значений: ' || l_distinct);
    DBMS_OUTPUT.PUT_LINE('NULL значений: ' || l_nulls);
END;
/

SELECT * FROM EVLAD.CLIENT;

-- GRANT EXECUTE ON get_column_stats_with_authid TO USER2;

BEGIN
    EVLAD.get_column_stats('CLIENT', 'PHONE_NUMBER');
END;
/


-- Создать процедуру, которая принимает в качестве параметра имя таблицы и имя поля в этой таблице.
-- Процедура подсчитывает и выводит на экран статистику по этой таблице: количество записей, имя поля,
-- количество различных значений поля, количество null-значений.
CREATE OR REPLACE PROCEDURE get_column_stats_with_authid(
    p_table_name IN VARCHAR2,
    p_column_name IN VARCHAR2
) AUTHID CURRENT_USER IS
    l_sql       VARCHAR2(4000);
    l_cnt       NUMBER;
    l_distinct  NUMBER;
    l_nulls     NUMBER;
BEGIN
    l_sql := 'SELECT COUNT(*), COUNT(DISTINCT ' || p_column_name || '), ' ||
             'SUM(CASE WHEN ' || p_column_name || ' IS NULL THEN 1 ELSE 0 END) ' ||
             'FROM ' || p_table_name;

    EXECUTE IMMEDIATE l_sql INTO l_cnt, l_distinct, l_nulls;

    DBMS_OUTPUT.PUT_LINE('Таблица: ' || p_table_name);
    DBMS_OUTPUT.PUT_LINE('Поле: ' || p_column_name);
    DBMS_OUTPUT.PUT_LINE('Всего записей: ' || l_cnt);
    DBMS_OUTPUT.PUT_LINE('Уникальных значений: ' || l_distinct);
    DBMS_OUTPUT.PUT_LINE('NULL значений: ' || l_nulls);
END;
/

BEGIN
    EVLAD.get_column_stats_with_authid('CLIENT', 'PHONE_NUMBER');
END;
/

-- ============================================================================
-- ПРОЦЕДУРА: Анализ связи ONE-TO-MANY и создание таблицы с JSON-коллекциями
-- ============================================================================
CREATE OR REPLACE PROCEDURE analyze_and_create_nested_table_json(
    p_parent_table IN VARCHAR2,
    p_child_table  IN VARCHAR2
) AUTHID CURRENT_USER IS
    l_constraint_name VARCHAR2(128);
    l_parent_column   VARCHAR2(128);
    l_child_column    VARCHAR2(128);
    l_sql             CLOB;
    l_new_table_name  VARCHAR2(128);
    l_exists          NUMBER;
    l_columns_json    VARCHAR2(4000);
    l_columns_list    VARCHAR2(4000);
    l_column_count    NUMBER := 0;

    CURSOR c_child_columns IS
        SELECT column_name, data_type
        FROM user_tab_columns
        WHERE table_name = UPPER(p_child_table)
        ORDER BY column_id;
BEGIN
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE('  АНАЛИЗ СВЯЗИ МЕЖДУ ТАБЛИЦАМИ');
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE('');

    -- 1️⃣ Находим внешний ключ
    BEGIN
        SELECT c.constraint_name,
               cc_parent.column_name AS parent_column,
               cc_child.column_name  AS child_column
        INTO l_constraint_name, l_parent_column, l_child_column
        FROM user_constraints c
                 JOIN user_cons_columns cc_child
                      ON c.constraint_name = cc_child.constraint_name
                 JOIN user_constraints c_parent
                      ON c.r_constraint_name = c_parent.constraint_name
                 JOIN user_cons_columns cc_parent
                      ON c_parent.constraint_name = cc_parent.constraint_name
        WHERE c.constraint_type = 'R'
          AND c.table_name = UPPER(p_child_table)
          AND c_parent.table_name = UPPER(p_parent_table)
          AND ROWNUM = 1;

        DBMS_OUTPUT.PUT_LINE('✓ Найдена связь ONE-TO-MANY:');
        DBMS_OUTPUT.PUT_LINE('  ├─ Родительская таблица: ' || p_parent_table || ' (' || l_parent_column || ')');
        DBMS_OUTPUT.PUT_LINE('  ├─ Дочерняя таблица:     ' || p_child_table || ' (' || l_child_column || ')');
        DBMS_OUTPUT.PUT_LINE('  └─ Constraint:           ' || l_constraint_name);
        DBMS_OUTPUT.PUT_LINE('');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('✗ ОШИБКА: Связь между таблицами не найдена!');
            DBMS_OUTPUT.PUT_LINE('  Проверьте наличие внешнего ключа между таблицами.');
            RETURN;
    END;

    -- 2️⃣ Динамическое формирование JSON для всех столбцов дочерней таблицы
    l_columns_json := '';
    l_column_count := 0;
    FOR rec IN c_child_columns LOOP
            l_column_count := l_column_count + 1;
            IF l_columns_json IS NOT NULL THEN
                l_columns_json := l_columns_json || ',';
            END IF;

            -- Обработка разных типов данных
            IF rec.data_type LIKE '%DATE%' THEN
                l_columns_json := l_columns_json ||
                                  '''' || rec.column_name || ''' VALUE TO_CHAR(c.' || rec.column_name || ',''YYYY-MM-DD HH24:MI:SS'')';
            ELSE
                l_columns_json := l_columns_json ||
                                  '''' || rec.column_name || ''' VALUE c.' || rec.column_name;
            END IF;
        END LOOP;

    DBMS_OUTPUT.PUT_LINE('✓ Определены столбцы дочерней таблицы (' || l_column_count || ' шт.)');
    DBMS_OUTPUT.PUT_LINE('');

    -- 3️⃣ Создаём новую таблицу с JSON-полем
    l_new_table_name := UPPER(SUBSTR(p_parent_table || '_WITH_' || p_child_table, 1, 100));

    SELECT COUNT(*) INTO l_exists
    FROM user_tables
    WHERE table_name = UPPER(l_new_table_name);

    IF l_exists > 0 THEN
        EXECUTE IMMEDIATE 'DROP TABLE ' || l_new_table_name || ' PURGE';
        DBMS_OUTPUT.PUT_LINE('⚠ Старая таблица удалена: ' || l_new_table_name);
    END IF;

    -- Создаём таблицу с полем child_records (CLOB для JSON)
    l_sql := 'CREATE TABLE ' || l_new_table_name || ' AS
              SELECT p.*, TO_CLOB(NULL) AS child_records
              FROM ' || p_parent_table || ' p';
    EXECUTE IMMEDIATE l_sql;
    DBMS_OUTPUT.PUT_LINE('✓ Создана таблица: ' || l_new_table_name);

    -- 4️⃣ Формируем JSON с дочерними записями
    l_sql := 'MERGE INTO ' || l_new_table_name || ' t
              USING (
                  SELECT p.' || l_parent_column || ' AS pid,
                         JSON_ARRAYAGG(
                             JSON_OBJECT(' || l_columns_json || ')
                         RETURNING CLOB) AS child_json
                  FROM ' || p_parent_table || ' p
                  LEFT JOIN ' || p_child_table || ' c
                         ON p.' || l_parent_column || ' = c.' || l_child_column || '
                  GROUP BY p.' || l_parent_column || '
              ) s
              ON (t.' || l_parent_column || ' = s.pid)
              WHEN MATCHED THEN UPDATE SET t.child_records = s.child_json';

    EXECUTE IMMEDIATE l_sql;
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('✓ Данные перенесены с JSON-подколлекциями');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE('  РЕЗУЛЬТАТ: Таблица ' || l_new_table_name || ' создана!');
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════════════');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('✗ КРИТИЧЕСКАЯ ОШИБКА:');
        DBMS_OUTPUT.PUT_LINE('  ' || SQLERRM);
        ROLLBACK;
        RAISE;
END analyze_and_create_nested_table_json;
/

-- 1. Запуск анализа и создания таблицы
BEGIN
    analyze_and_create_nested_table_json(
            p_parent_table => 'CLIENT',
            p_child_table  => 'INSURANCE_CONTRACT'
    );
END;
/

-- 2. Просмотр результатов (базовый вариант)
SELECT
    c.ID AS client_id,
    c.FIRST_NAME,
    c.LAST_NAME,
    c.PHONE_NUMBER,
    JSON_QUERY(c.CHILD_RECORDS, '$' PRETTY) AS insurance_contracts
FROM CLIENT_WITH_INSURANCE_CONTRACT c
WHERE c.CHILD_RECORDS IS NOT NULL
ORDER BY c.ID;

-- 3. Развёртывание JSON в строки (детальный вариант)
SELECT
    p.ID AS parent_id,
    p.FIRST_NAME,
    p.LAST_NAME,
    p.PHONE_NUMBER,
    jt.*
FROM CLIENT_WITH_INSURANCE_CONTRACT p
         CROSS APPLY JSON_TABLE(
        p.CHILD_RECORDS,
        '$[*]' COLUMNS (
            contract_id NUMBER PATH '$.ID',
            contract_date VARCHAR2(20) PATH '$.CONTRACT_DATE',
            contract_status VARCHAR2(50) PATH '$.CONTRACT_STATUS',
            contract_duration NUMBER PATH '$.PAYOUT_DEADLINE',
            client_id NUMBER PATH '$.CLIENT_ID'
            -- Добавьте здесь все столбцы из вашей дочерней таблицы
            )
                     ) jt
WHERE p.CHILD_RECORDS IS NOT NULL
ORDER BY p.ID, jt.contract_id;


select * from CLIENT_WITH_INSURANCE_CONTRACT



