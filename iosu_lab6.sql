DROP TYPE t_join_list;
DROP TYPE t_join_pair;
/

CREATE OR REPLACE TYPE t_table_list IS TABLE OF VARCHAR2(100);
/

CREATE OR REPLACE TYPE t_join_pair AS OBJECT
(
    table1    VARCHAR2(100),
    table2    VARCHAR2(100),
    column1   VARCHAR2(100),
    column2   VARCHAR2(100),
    join_type VARCHAR2(10)
);
/

CREATE OR REPLACE TYPE t_join_list IS TABLE OF t_join_pair;
/

CREATE OR REPLACE PROCEDURE exec_dynamic_join_select(
    p_tables     IN t_table_list,
    p_params     IN t_param_list DEFAULT NULL,
    p_join_type  IN VARCHAR2 DEFAULT 'INNER',
    p_result     OUT t_result_collection
) AUTHID CURRENT_USER IS
    l_query        VARCHAR2(32767);
    l_from         VARCHAR2(32767) := '';
    l_where        VARCHAR2(4000) := '';
    l_cursor       INTEGER;
    l_col_cnt      INTEGER;
    l_desc_tab     DBMS_SQL.DESC_TAB;
    l_varchar      VARCHAR2(4000);
    l_status       INTEGER;
    l_row_data     t_row_data;
    l_row_count    NUMBER := 0;
    l_join_found   BOOLEAN := FALSE;
    l_join_type    VARCHAR2(20);
    l_condition_count INTEGER := 0;
BEGIN
    l_join_type := UPPER(TRIM(p_join_type));

    IF l_join_type NOT IN ('INNER', 'LEFT', 'RIGHT', 'FULL', 'FULL OUTER', 'CROSS') THEN
        DBMS_OUTPUT.PUT_LINE('⚠️ Некорректный тип JOIN "' || p_join_type || '", заменён на INNER');
        l_join_type := 'INNER';
    END IF;

    IF p_tables.COUNT = 1 THEN
        l_from := p_tables(1);
    ELSE
        l_from := p_tables(1);

        FOR i IN 2 .. p_tables.COUNT LOOP
                l_join_found := FALSE;

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
                        IF l_join_type = 'CROSS' THEN
                            DBMS_OUTPUT.PUT_LINE('⚠️ CROSS JOIN не может использоваться при наличии внешних ключей между ' ||
                                                 fk_row.child_table || ' и ' || fk_row.parent_table ||
                                                 '. Используется INNER JOIN.');
                            l_join_type := 'INNER';
                        END IF;

                        l_from := l_from || ' ' || l_join_type || ' JOIN ' || p_tables(i) ||
                                  ' ON ' || fk_row.child_table || '.' || fk_row.child_column ||
                                  ' = ' || fk_row.parent_table || '.' || fk_row.parent_column;

                        l_join_found := TRUE;
                        EXIT;
                    END LOOP;

                IF NOT l_join_found THEN
                    IF l_join_type IN ('CROSS') THEN
                        l_from := l_from || ' CROSS JOIN ' || p_tables(i);
                        DBMS_OUTPUT.PUT_LINE('ℹ️ Добавлен CROSS JOIN между ' ||
                                             p_tables(i - 1) || ' и ' || p_tables(i));
                    ELSE
                        DBMS_OUTPUT.PUT_LINE('⚠️ Не удалось автоматически связать ' ||
                                             p_tables(i - 1) || ' и ' || p_tables(i) ||
                                             '. CROSS JOIN не используется.');
                    END IF;
                END IF;
            END LOOP;
    END IF;

    IF p_params IS NOT NULL AND p_params.COUNT > 0 THEN
        FOR i IN 1 .. p_params.COUNT LOOP
                DECLARE
                    l_table_name  VARCHAR2(100);
                    l_column_name VARCHAR2(100);
                    l_param_valid BOOLEAN := FALSE;
                BEGIN
                    l_table_name := SUBSTR(p_params(i).param_name, 1, INSTR(p_params(i).param_name, '.') - 1);
                    l_column_name := SUBSTR(p_params(i).param_name, INSTR(p_params(i).param_name, '.') + 1);

                    SELECT COUNT(*) INTO l_row_count
                    FROM user_tab_columns
                    WHERE table_name = UPPER(l_table_name)
                      AND column_name = UPPER(l_column_name);

                    IF l_row_count > 0 THEN
                        l_param_valid := TRUE;
                    ELSE
                        DBMS_OUTPUT.PUT_LINE('⚠️ Поле ' || p_params(i).param_name || ' не найдено, пропущено.');
                    END IF;

                    IF l_param_valid THEN
                        IF l_condition_count = 0 THEN
                            l_where := ' WHERE ';
                        ELSE
                            l_where := l_where || ' AND ';
                        END IF;
                        l_where := l_where || p_params(i).param_name || ' = ''' || p_params(i).param_value || '''';
                        l_condition_count := l_condition_count + 1;
                    END IF;
                END;
            END LOOP;
    END IF;

    l_query := 'SELECT * FROM ' || l_from || l_where;
    DBMS_OUTPUT.PUT_LINE('=================================');
    DBMS_OUTPUT.PUT_LINE('SQL: ' || l_query);
    DBMS_OUTPUT.PUT_LINE('=================================');

    l_cursor := DBMS_SQL.OPEN_CURSOR;
    DBMS_SQL.PARSE(l_cursor, l_query, DBMS_SQL.NATIVE);
    DBMS_SQL.DESCRIBE_COLUMNS(l_cursor, l_col_cnt, l_desc_tab);
    FOR i IN 1 .. l_col_cnt LOOP
            DBMS_SQL.DEFINE_COLUMN(l_cursor, i, l_varchar, 4000);
        END LOOP;
    l_status := DBMS_SQL.EXECUTE(l_cursor);

    p_result := t_result_collection();
    WHILE DBMS_SQL.FETCH_ROWS(l_cursor) > 0 LOOP
            l_row_data := t_row_data();
            l_row_data.EXTEND(l_col_cnt);
            FOR i IN 1 .. l_col_cnt LOOP
                    DBMS_SQL.COLUMN_VALUE(l_cursor, i, l_varchar);
                    l_row_data(i) := l_desc_tab(i).col_name || '=' || NVL(l_varchar, 'NULL');
                END LOOP;
            p_result.EXTEND;
            p_result(p_result.COUNT) := t_result_row(l_row_data, p_result.COUNT);
        END LOOP;

    DBMS_OUTPUT.PUT_LINE('Найдено строк: ' || NVL(p_result.COUNT, 0));
    DBMS_SQL.CLOSE_CURSOR(l_cursor);

EXCEPTION
    WHEN OTHERS THEN
        IF DBMS_SQL.IS_OPEN(l_cursor) THEN
            DBMS_SQL.CLOSE_CURSOR(l_cursor);
        END IF;
        DBMS_OUTPUT.PUT_LINE('❌ Ошибка: ' || SQLERRM);
END exec_dynamic_join_select;
/

DECLARE
    l_tables t_table_list := t_table_list('INSURANCE_CONTRACT', 'COMPENSATION_CLAIM', 'INSURANCE_CASE');
    l_params t_param_list := t_param_list(
            t_param_pair('INSURANCE_CONTRACT.CONTRACTS_STATUS', 'Активен')
                             );
    l_result t_result_collection;
    l_row    t_result_row;
BEGIN
    exec_dynamic_join_select(
            p_tables => l_tables,
            p_params => l_params,
            p_join_type => 'FULL OUTER',
            p_result => l_result
    );

    DBMS_OUTPUT.PUT_LINE('--- Результаты ---');
    FOR i IN 1 .. l_result.COUNT
        LOOP
            l_row := l_result(i);
            DBMS_OUTPUT.PUT_LINE('Строка ' || i);
            FOR j IN 1 .. l_row.row_values.COUNT
                LOOP
                    DBMS_OUTPUT.PUT_LINE('  ' || l_row.row_values(j));
                END LOOP;
            DBMS_OUTPUT.PUT_LINE('---');
        END LOOP;
END;
/



CREATE OR REPLACE PROCEDURE create_object(
    p_obj_type IN VARCHAR2,
    p_src_table IN VARCHAR2,
    p_columns IN VARCHAR2,
    p_rowcount IN NUMBER
) AUTHID CURRENT_USER IS
    l_cnt            INTEGER;
    l_sql            VARCHAR2(4000);
    l_new_name       VARCHAR2(200);
    l_base_name      VARCHAR2(200);
    l_suffix         INTEGER := 1;
    l_rows_inserted  INTEGER := 0;
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
        EXECUTE IMMEDIATE l_sql;
        l_rows_inserted := SQL%ROWCOUNT;

    ELSE
        l_sql := 'CREATE VIEW ' || l_new_name || ' AS SELECT ' || p_columns ||
                 ' FROM ' || p_src_table || ' WHERE ROWNUM <= ' || p_rowcount;
        EXECUTE IMMEDIATE l_sql;

        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || l_new_name
            INTO l_rows_inserted;
    END IF;

    DBMS_OUTPUT.PUT_LINE('Объект "' || l_new_name || '" успешно создан.');
    DBMS_OUTPUT.PUT_LINE('Количество скопированных строк: ' || l_rows_inserted);
END;
/




BEGIN
    create_object(
            p_obj_type => 'TABLE',
            p_src_table => 'CLIENT',
            p_columns => 'id, first_name, last_name, phone_number',
            p_rowcount => 3
    );

    create_object(
            p_obj_type => 'VIEW',
            p_src_table => 'CLIENT',
            p_columns => 'first_name, last_name',
            p_rowcount => 5
    );
END;
/

CREATE OR REPLACE PROCEDURE get_column_stats(
    p_table_name IN VARCHAR2,
    p_column_name IN VARCHAR2
) AUTHID DEFINER IS
    l_sql      VARCHAR2(4000);
    l_cnt      NUMBER;
    l_distinct NUMBER;
    l_nulls    NUMBER;
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


-- Создать процедуру, которая принимает в качестве параметра имя таблицы и имя поля в этой таблице.
-- Процедура подсчитывает и выводит на экран статистику по этой таблице: количество записей, имя поля,
-- количество различных значений поля, количество null-значений.
CREATE OR REPLACE PROCEDURE get_column_stats_with_authid(
    p_table_name IN VARCHAR2,
    p_column_name IN VARCHAR2
) AUTHID CURRENT_USER IS
    l_sql      VARCHAR2(4000);
    l_cnt      NUMBER;
    l_distinct NUMBER;
    l_nulls    NUMBER;
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

GRANT EXECUTE ON get_column_stats_with_authid TO USER2;
GRANT EXECUTE ON get_column_stats_with_authid TO USER2;

BEGIN
    EVLAD.get_column_stats('EVLAD.CLIENT', 'PHONE_NUMBER'); -- сработает у User2 хотя у того нет прав на select client
END;
/

BEGIN
    EVLAD.get_column_stats_with_authid('EVLAD.CLIENT', 'PHONE_NUMBER'); -- тут у user2 не сработает если у него нет прав на select client
END;
/

GRANT SELECT ON CLIENT TO USER2; --если так сделать то get_column_stats_with_authid выполнится успешно
REVOKE SELECT ON CLIENT FROM USER2;

-- ============================================================================
-- ПРОЦЕДУРА: Анализ связи ONE-TO-MANY и создание таблицы с JSON-коллекциями
-- ============================================================================
CREATE OR REPLACE PROCEDURE analyze_and_create_nested_table_json(
    p_parent_table IN VARCHAR2,
    p_child_table IN VARCHAR2
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

    l_columns_json := '';
    l_column_count := 0;
    FOR rec IN c_child_columns
        LOOP
            l_column_count := l_column_count + 1;
            IF l_columns_json IS NOT NULL THEN
                l_columns_json := l_columns_json || ',';
            END IF;

            IF rec.data_type LIKE '%DATE%' THEN
                l_columns_json := l_columns_json ||
                                  '''' || rec.column_name || ''' VALUE TO_CHAR(c.' || rec.column_name ||
                                  ',''YYYY-MM-DD HH24:MI:SS'')';
            ELSE
                l_columns_json := l_columns_json ||
                                  '''' || rec.column_name || ''' VALUE c.' || rec.column_name;
            END IF;
        END LOOP;

    DBMS_OUTPUT.PUT_LINE('✓ Определены столбцы дочерней таблицы (' || l_column_count || ' шт.)');
    DBMS_OUTPUT.PUT_LINE('');

    l_new_table_name := UPPER(SUBSTR(p_parent_table || '_WITH_' || p_child_table, 1, 100));

    SELECT COUNT(*)
    INTO l_exists
    FROM user_tables
    WHERE table_name = UPPER(l_new_table_name);

    IF l_exists > 0 THEN
        EXECUTE IMMEDIATE 'DROP TABLE ' || l_new_table_name || ' PURGE';
        DBMS_OUTPUT.PUT_LINE('⚠ Старая таблица удалена: ' || l_new_table_name);
    END IF;

    l_sql := 'CREATE TABLE ' || l_new_table_name || ' AS
              SELECT p.*, TO_CLOB(NULL) AS child_records
              FROM ' || p_parent_table || ' p';
    EXECUTE IMMEDIATE l_sql;
    DBMS_OUTPUT.PUT_LINE('✓ Создана таблица: ' || l_new_table_name);

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
            p_child_table => 'INSURANCE_CONTRACT'
    );
END;
/

select *
from CLIENT_WITH_INSURANCE_CONTRACT;

-- 2. Просмотр результатов (базовый вариант)
SELECT c.ID                                    AS client_id,
       c.FIRST_NAME,
       c.LAST_NAME,
       c.PHONE_NUMBER,
       JSON_QUERY(c.CHILD_RECORDS, '$' PRETTY) AS insurance_contracts
FROM CLIENT_WITH_INSURANCE_CONTRACT c
WHERE c.CHILD_RECORDS IS NOT NULL
ORDER BY c.ID;

-- 3. Развёртывание JSON в строки (детальный вариант)
SELECT p.ID AS parent_id,
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
            )
                     ) jt
WHERE p.CHILD_RECORDS IS NOT NULL
ORDER BY p.ID, jt.contract_id;

-- ============================================================================
-- ПРОЦЕДУРА: Анализ связи ONE-TO-MANY и создание таблицы с JSON-коллекциями
-- ============================================================================
CREATE OR REPLACE PROCEDURE analyze_and_create_nested_table_json(
    p_parent_table IN VARCHAR2,
    p_child_table  IN VARCHAR2
) AUTHID CURRENT_USER IS
    l_constraint_name  VARCHAR2(128);
    l_parent_column    VARCHAR2(128);
    l_child_column     VARCHAR2(128);
    l_sql              CLOB;
    l_new_table_name   VARCHAR2(128);
    l_exists           NUMBER;
    l_columns_json     VARCHAR2(4000);
    l_column_count     NUMBER := 0;

    CURSOR c_child_columns IS
        SELECT column_name, data_type
        FROM user_tab_columns
        WHERE table_name = UPPER(p_child_table)
        ORDER BY column_id;
BEGIN
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE('           АНАЛИЗ СВЯЗИ МЕЖДУ ТАБЛИЦАМИ');
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE('');

    -- Поиск связи между таблицами
    BEGIN
        SELECT c.constraint_name,
               cc_parent.column_name AS parent_column,
               cc_child.column_name AS child_column
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
        DBMS_OUTPUT.PUT_LINE('  ├─ Дочерняя таблица: ' || p_child_table || ' (' || l_child_column || ')');
        DBMS_OUTPUT.PUT_LINE('  └─ Constraint: ' || l_constraint_name);
        DBMS_OUTPUT.PUT_LINE('');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('✗ ОШИБКА: Связь между таблицами не найдена!');
            DBMS_OUTPUT.PUT_LINE('  Проверьте наличие внешнего ключа между таблицами.');
            RETURN;
    END;

    -- Формирование JSON-структуры
    l_columns_json := '';
    l_column_count := 0;

    FOR rec IN c_child_columns LOOP
            l_column_count := l_column_count + 1;
            IF l_columns_json IS NOT NULL THEN
                l_columns_json := l_columns_json || ',';
            END IF;

            IF rec.data_type LIKE '%DATE%' THEN
                l_columns_json := l_columns_json || '''' || rec.column_name ||
                                  ''' VALUE TO_CHAR(c.' || rec.column_name || ',''YYYY-MM-DD HH24:MI:SS'')';
            ELSE
                l_columns_json := l_columns_json || '''' || rec.column_name ||
                                  ''' VALUE c.' || rec.column_name;
            END IF;
        END LOOP;

    DBMS_OUTPUT.PUT_LINE('✓ Определены столбцы дочерней таблицы (' || l_column_count || ' шт.)');
    DBMS_OUTPUT.PUT_LINE('');

    -- Создание новой таблицы
    l_new_table_name := UPPER(SUBSTR(p_parent_table || '_WITH_' || p_child_table, 1, 100));

    SELECT COUNT(*) INTO l_exists
    FROM user_tables
    WHERE table_name = UPPER(l_new_table_name);

    IF l_exists > 0 THEN
        EXECUTE IMMEDIATE 'DROP TABLE ' || l_new_table_name || ' PURGE';
        DBMS_OUTPUT.PUT_LINE('⚠ Старая таблица удалена: ' || l_new_table_name);
    END IF;

    l_sql := 'CREATE TABLE ' || l_new_table_name || ' AS
              SELECT p.*, TO_CLOB(NULL) AS child_records
              FROM ' || p_parent_table || ' p';
    EXECUTE IMMEDIATE l_sql;
    DBMS_OUTPUT.PUT_LINE('✓ Создана таблица: ' || l_new_table_name);

    -- Наполнение JSON-данными
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
              ) s ON (t.' || l_parent_column || ' = s.pid)
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

-- ============================================================================
-- ПРИМЕРЫ ИСПОЛЬЗОВАНИЯ
-- ============================================================================

-- 1. Запуск анализа и создания таблицы
BEGIN
    analyze_and_create_nested_table_json(
            p_parent_table => 'CLIENT',
            p_child_table  => 'INSURANCE_CONTRACT'
    );
END;
/

-- 2. Просмотр созданной таблицы
SELECT * FROM CLIENT_WITH_INSURANCE_CONTRACT;

SELECT
    p.ID AS parent_id,
    p.FIRST_NAME,
    p.LAST_NAME,
    p.PHONE_NUMBER,
    jt.contract_id,
    jt.contract_date,
    jt.contract_status,
    jt.contract_duration,
    jt.client_id
FROM CLIENT_WITH_INSURANCE_CONTRACT p
         CROSS APPLY JSON_TABLE(
        p.CHILD_RECORDS, '$[*]'
        COLUMNS (
            contract_id       NUMBER        PATH '$.ID',
            contract_date     VARCHAR2(20)  PATH '$.CONTRACT_DATE',
            contract_status   VARCHAR2(50)  PATH '$.CONTRACT_STATUS',
            contract_duration NUMBER        PATH '$.PAYOUT_DEADLINE',
            client_id         NUMBER        PATH '$.CLIENT_ID'
            )
                     ) jt
WHERE p.CHILD_RECORDS IS NOT NULL
ORDER BY p.ID, jt.contract_id;


WITH
    patterns AS (
        SELECT
            '"ID"\s*:\s*([0-9]+)' AS id_re,
            '"CONTRACT_DATE"\s*:\s*"([^"]+)"' AS date_re,
            '"CONTRACT_STATUS"\s*:\s*"([^"]+)"' AS status_re,
            '"PAYOUT_DEADLINE"\s*:\s*([0-9]+)' AS deadline_re,
            '"CLIENT_ID"\s*:\s*([0-9]+)' AS client_re
        FROM dual
    ),

    client_counts AS (
        SELECT
            p.ID,
            p.FIRST_NAME,
            p.LAST_NAME,
            p.PHONE_NUMBER,
            p.CHILD_RECORDS,
            REGEXP_COUNT(p.CHILD_RECORDS, '\{') AS obj_count
        FROM CLIENT_WITH_INSURANCE_CONTRACT p
        WHERE p.CHILD_RECORDS IS NOT NULL
    ),

    expanded_rows AS (
        SELECT
            c.ID AS parent_id,
            c.FIRST_NAME,
            c.LAST_NAME,
            c.PHONE_NUMBER,
            LEVEL AS n,
            REGEXP_SUBSTR(c.CHILD_RECORDS, '\{[^}]+\}', 1, LEVEL) AS json_obj
        FROM client_counts c
        CONNECT BY LEVEL <= c.obj_count
               AND PRIOR c.ID = c.ID
               AND PRIOR SYS_GUID() IS NOT NULL
    )

SELECT
    e.parent_id,
    e.FIRST_NAME,
    e.LAST_NAME,
    e.PHONE_NUMBER,

    TO_NUMBER(REGEXP_SUBSTR(e.json_obj, p.id_re, 1, 1, NULL, 1)) AS contract_id,
    REGEXP_SUBSTR(e.json_obj, p.date_re, 1, 1, NULL, 1) AS contract_date,
    REGEXP_SUBSTR(e.json_obj, p.status_re, 1, 1, NULL, 1) AS contract_status,
    TO_NUMBER(REGEXP_SUBSTR(e.json_obj, p.deadline_re, 1, 1, NULL, 1)) AS contract_duration,
    TO_NUMBER(REGEXP_SUBSTR(e.json_obj, p.client_re, 1, 1, NULL, 1)) AS client_id

FROM expanded_rows e
         CROSS JOIN patterns p
WHERE e.json_obj IS NOT NULL
ORDER BY e.parent_id, contract_id;



select * from CLIENT_WITH_CHILDREN





