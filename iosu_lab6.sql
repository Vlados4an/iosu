
CREATE OR REPLACE TYPE t_param_pair AS OBJECT (
                                                  param_name VARCHAR2(100),
                                                  param_value VARCHAR2(4000)
                                              );
/

CREATE OR REPLACE TYPE t_param_list IS TABLE OF t_param_pair;
/

CREATE OR REPLACE TYPE t_row_data AS TABLE OF VARCHAR2(4000);
/

CREATE OR REPLACE TYPE t_result_row AS OBJECT (
                                                  row_values t_row_data,
                                                  row_count NUMBER
                                              );
/

CREATE OR REPLACE TYPE t_result_collection IS TABLE OF t_result_row;
/

-- Динамическая процедура с DBMS_SQL (SELECT заранее неизвестен)
CREATE OR REPLACE PROCEDURE exec_dynamic_select(
    p_table_name IN VARCHAR2,
    p_params IN t_param_list DEFAULT NULL, -- Коллекция параметров (может быть пустой)
    p_result OUT t_result_collection
) AUTHID CURRENT_USER IS
    l_query VARCHAR2(4000);
    l_where VARCHAR2(2000) := '';
    l_cursor INTEGER;
    l_col_cnt INTEGER;
    l_desc_tab DBMS_SQL.DESC_TAB;
    l_varchar VARCHAR2(4000);
    l_status INTEGER;
    l_row_data t_row_data;
    l_row_count NUMBER := 0;
BEGIN
    l_query := 'SELECT * FROM ' || p_table_name;

    IF p_params IS NOT NULL AND p_params.COUNT > 0 THEN
        l_where := ' WHERE ';
        FOR i IN 1 .. p_params.COUNT LOOP
                IF i > 1 THEN
                    l_where := l_where || ' AND ';
                END IF;
                l_where := l_where || p_params(i).param_name || ' = ''' || p_params(i).param_value || '''';
            END LOOP;
        l_query := l_query || l_where;
    END IF;

    DBMS_OUTPUT.PUT_LINE('=================================');
    DBMS_OUTPUT.PUT_LINE('Количество параметров: ' || NVL(p_params.COUNT, 0));
    DBMS_OUTPUT.PUT_LINE('Запрос: ' || l_query);
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

    DBMS_OUTPUT.PUT_LINE('Найдено записей: ' || l_row_count);
    DBMS_SQL.CLOSE_CURSOR(l_cursor);

EXCEPTION
    WHEN OTHERS THEN
        IF DBMS_SQL.IS_OPEN(l_cursor) THEN
            DBMS_SQL.CLOSE_CURSOR(l_cursor);
        END IF;
        RAISE;
END exec_dynamic_select;
/

DECLARE
    l_result t_result_collection;
    l_row t_result_row;
BEGIN
    exec_dynamic_select(
            p_table_name => 'CLIENT',
            p_params => t_param_list(),
            p_result => l_result
    );

    DBMS_OUTPUT.PUT_LINE('--- Результаты из коллекции ---');
    FOR i IN 1 .. l_result.COUNT LOOP
            l_row := l_result(i);
            DBMS_OUTPUT.PUT_LINE('Строка ' || i || ':');
            FOR j IN 1 .. l_row.row_values.COUNT LOOP
                    DBMS_OUTPUT.PUT_LINE('  ' || l_row.row_values(j));
                END LOOP;
            DBMS_OUTPUT.PUT_LINE('---');
        END LOOP;
END;
/

DECLARE
    l_params t_param_list;
    l_result t_result_collection;
    l_row t_result_row;
BEGIN
    l_params := t_param_list(
            t_param_pair('CONTRACT_STATUS', 'Активен'),
            t_param_pair('AGENT_ID', '1')
                );

    exec_dynamic_select('INSURANCE_CONTRACT', l_params, l_result);

    DBMS_OUTPUT.PUT_LINE('--- Результаты из коллекции ---');
    FOR i IN 1 .. l_result.COUNT LOOP
            l_row := l_result(i);
            DBMS_OUTPUT.PUT_LINE('Строка ' || i || ':');
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
    p_new_name   IN VARCHAR2,
    p_src_table  IN VARCHAR2,
    p_columns    IN VARCHAR2,
    p_rowcount   IN NUMBER
) AUTHID CURRENT_USER IS
    l_cnt INTEGER;
    l_sql VARCHAR2(4000);
BEGIN
    -- проверка существования
    SELECT COUNT(*)
    INTO l_cnt
    FROM user_objects
    WHERE object_name = UPPER(p_new_name);

    IF l_cnt > 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Объект ' || p_new_name || ' уже существует');
    END IF;

    IF UPPER(p_obj_type) = 'VIEW' THEN
        l_sql := 'CREATE VIEW ' || p_new_name || ' AS SELECT ' || p_columns ||
                 ' FROM ' || p_src_table || ' WHERE ROWNUM <= ' || p_rowcount;
    ELSIF UPPER(p_obj_type) = 'TABLE' THEN
        l_sql := 'CREATE TABLE ' || p_new_name || ' AS SELECT ' || p_columns ||
                 ' FROM ' || p_src_table || ' WHERE ROWNUM <= ' || p_rowcount;
    ELSE
        RAISE_APPLICATION_ERROR(-20002, 'Тип объекта должен быть TABLE или VIEW');
    END IF;

    EXECUTE IMMEDIATE l_sql;
END;
/

BEGIN
    -- Создаём новую таблицу с 3 первыми строками из client
    create_object(
            p_obj_type  => 'TABLE',
            p_new_name  => 'CLIENT_COPY',
            p_src_table => 'CLIENT',
            p_columns   => 'id, first_name, last_name, phone_number',
            p_rowcount  => 3
    );

    -- Создаём новое представление
    create_object(
            p_obj_type  => 'VIEW',
            p_new_name  => 'CLIENT_VIEW',
            p_src_table => 'CLIENT',
            p_columns   => 'first_name, last_name',
            p_rowcount  => 5
    );
END;
/


-- Создать процедуру, которая принимает в качестве параметра имя таблицы и имя поля в этой таблице.
-- Процедура подсчитывает и выводит на экран статистику по этой таблице: количество записей, имя поля,
-- количество различных значений поля, количество null-значений.
CREATE OR REPLACE PROCEDURE get_column_stats(
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
    get_column_stats('CLIENT', 'PHONE_NUMBER');
END;
/


CREATE OR REPLACE PROCEDURE check_and_create_nested_table_dynamic(
    p_parent_table IN VARCHAR2,
    p_child_table  IN VARCHAR2
) AUTHID CURRENT_USER AS
    v_parent_col   VARCHAR2(100);
    v_child_col    VARCHAR2(100);
    v_new_table    VARCHAR2(100);
    v_sql_obj      CLOB;
    v_sql_table    CLOB;
    v_count        NUMBER;
    v_cols_obj     VARCHAR2(4000);
    v_cols_select  VARCHAR2(4000);
BEGIN
    -- 1. Находим FK "один ко многим"
    SELECT a.column_name, col_pk.column_name
    INTO   v_child_col, v_parent_col
    FROM   user_constraints c
               JOIN user_cons_columns a
                    ON c.constraint_name = a.constraint_name
               JOIN user_constraints c_pk
                    ON c.r_constraint_name = c_pk.constraint_name
               JOIN user_cons_columns col_pk
                    ON c_pk.constraint_name = col_pk.constraint_name
    WHERE  c.table_name = UPPER(p_child_table)
      AND  c.constraint_type = 'R'
      AND  c_pk.table_name = UPPER(p_parent_table)
      AND  ROWNUM = 1;

    DBMS_OUTPUT.put_line('Связь найдена: ' || p_parent_table || '.' || v_parent_col ||
                         ' -> ' || p_child_table || '.' || v_child_col);

    -- 2. Имя новой таблицы
    v_new_table := p_parent_table || '_NESTED';

    -- 3. Проверка на существование
    SELECT COUNT(*) INTO v_count FROM user_tables WHERE table_name = UPPER(v_new_table);
    IF v_count > 0 THEN
        EXECUTE IMMEDIATE 'DROP TABLE ' || v_new_table || ' PURGE';
    END IF;

    -- 4. Создаем объект дочерней таблицы динамически
    SELECT LISTAGG(column_name || ' ' || data_type ||
                   CASE
                       WHEN data_type LIKE 'VARCHAR2%' THEN '(' || data_length || ')'
                       WHEN data_type LIKE 'NUMBER%' AND data_precision IS NOT NULL THEN
                           '(' || data_precision || NVL2(data_scale, ',' || data_scale, '') || ')'
                       ELSE ''
                       END
               , ', ')
                   WITHIN GROUP (ORDER BY column_id)
    INTO v_cols_obj
    FROM user_tab_columns
    WHERE table_name = UPPER(p_child_table);

    v_sql_obj := 'CREATE OR REPLACE TYPE t_child_obj AS OBJECT (' || v_cols_obj || ')';
    BEGIN
        EXECUTE IMMEDIATE v_sql_obj;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Тип объекта уже существует или ошибка: ' || SQLERRM);
    END;

    -- 5. Создаем коллекцию объектов
    BEGIN
        EXECUTE IMMEDIATE 'CREATE OR REPLACE TYPE t_child_records AS TABLE OF t_child_obj';
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Тип коллекции уже существует или ошибка: ' || SQLERRM);
    END;

    -- 6. Формируем SELECT для MULTISET
    SELECT LISTAGG('t_child_obj(' || column_name || ')', ', ')
                   WITHIN GROUP (ORDER BY column_id)
    INTO v_cols_select
    FROM user_tab_columns
    WHERE table_name = UPPER(p_child_table);

    -- 7. Создаем новую таблицу с nested column
    v_sql_table := 'CREATE TABLE ' || v_new_table || ' AS
                    SELECT p.*,
                           CAST(MULTISET(
                               SELECT ' || v_cols_select || '
                               FROM ' || p_child_table || ' c
                               WHERE c.' || v_child_col || ' = p.' || v_parent_col || '
                           ) AS t_child_records) AS child_records
                    FROM ' || p_parent_table || ' p';

    EXECUTE IMMEDIATE v_sql_table;

    DBMS_OUTPUT.put_line('Создана таблица: ' || v_new_table);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.put_line('Связь "один ко многим" между ' || p_parent_table ||
                             ' и ' || p_child_table || ' не найдена.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.put_line('Ошибка: ' || SQLERRM);
END;
/

CREATE OR REPLACE PROCEDURE analyze_and_create_nested_table(
    p_parent_table IN VARCHAR2,
    p_child_table IN VARCHAR2
) AUTHID CURRENT_USER IS
    l_constraint_name VARCHAR2(128);
    l_parent_column VARCHAR2(128);
    l_child_column VARCHAR2(128);
    l_sql VARCHAR2(4000);
    l_new_table_name VARCHAR2(128);
    l_exists NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('АНАЛИЗ СВЯЗИ МЕЖДУ ТАБЛИЦАМИ');

    BEGIN
        SELECT c.constraint_name,
               cc_parent.column_name AS parent_column,
               cc_child.column_name AS child_column
        INTO l_constraint_name, l_parent_column, l_child_column
        FROM user_constraints c
                 JOIN user_cons_columns cc_child ON c.constraint_name = cc_child.constraint_name
                 JOIN user_constraints c_parent ON c.r_constraint_name = c_parent.constraint_name
                 JOIN user_cons_columns cc_parent ON c_parent.constraint_name = cc_parent.constraint_name
        WHERE c.constraint_type = 'R'
          AND c.table_name = UPPER(p_child_table)
          AND c_parent.table_name = UPPER(p_parent_table)
          AND ROWNUM = 1;

        DBMS_OUTPUT.PUT_LINE('✓ Найдена связь ONE-TO-MANY:');
        DBMS_OUTPUT.PUT_LINE('  Родительская таблица: ' || p_parent_table || '(' || l_parent_column || ')');
        DBMS_OUTPUT.PUT_LINE('  Дочерняя таблица: ' || p_child_table || '(' || l_child_column || ')');
        DBMS_OUTPUT.PUT_LINE('  Constraint: ' || l_constraint_name);

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('✗ Связь между таблицами не найдена!');
            RETURN;
    END;

    l_new_table_name := p_parent_table || '_WITH_CHILDREN';

    SELECT COUNT(*) INTO l_exists
    FROM user_tables
    WHERE table_name = UPPER(l_new_table_name);

    IF l_exists > 0 THEN
        EXECUTE IMMEDIATE 'DROP TABLE ' || l_new_table_name;
        DBMS_OUTPUT.PUT_LINE('Старая таблица удалена.');
    END IF;

    l_sql := 'CREATE TABLE ' || l_new_table_name || ' AS SELECT * FROM ' || p_parent_table;
    EXECUTE IMMEDIATE l_sql;

    EXECUTE IMMEDIATE 'ALTER TABLE ' || l_new_table_name ||
                      ' ADD child_records CLOB';

    DBMS_OUTPUT.PUT_LINE('✓ Создана таблица: ' || l_new_table_name);

    DECLARE
        l_child_columns VARCHAR2(4000);
        l_first_cols VARCHAR2(1000) := '';
        l_col_list VARCHAR2(4000) := '';
        l_col_count NUMBER := 0;
    BEGIN
        FOR rec IN (
            SELECT column_name, column_id
            FROM user_tab_columns
            WHERE table_name = UPPER(p_child_table)
              AND column_name NOT IN ('ID', UPPER(l_child_column))
              AND column_id <= 5  -- берем первые 5 колонок
            ORDER BY column_id
            ) LOOP
                IF l_col_count > 0 THEN
                    l_col_list := l_col_list || ' || '', '' || ';
                END IF;
                l_col_list := l_col_list || 'NVL(TO_CHAR(c.' || rec.column_name || '), ''NULL'')';
                l_col_count := l_col_count + 1;
                EXIT WHEN l_col_count >= 3;
            END LOOP;

        IF l_col_list IS NULL THEN
            l_col_list := 'TO_CHAR(c.id)';
        ELSE
            l_col_list := '''['' || TO_CHAR(c.id) || ''] '' || ' || l_col_list;
        END IF;

        l_sql := 'MERGE INTO ' || l_new_table_name || ' t
                  USING (
                      SELECT p.' || l_parent_column || ',
                             LISTAGG(' || l_col_list || ', ''; '')
                             WITHIN GROUP (ORDER BY c.id) as child_data
                      FROM ' || p_parent_table || ' p
                      LEFT JOIN ' || p_child_table || ' c
                         ON p.' || l_parent_column || ' = c.' || l_child_column || '
                      GROUP BY p.' || l_parent_column || '
                  ) s
                  ON (t.' || l_parent_column || ' = s.' || l_parent_column || ')
                  WHEN MATCHED THEN UPDATE SET t.child_records = s.child_data';

        DBMS_OUTPUT.PUT_LINE('Формат записи: [ID] поле1, поле2, поле3');
        EXECUTE IMMEDIATE l_sql;
    END;
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('✓ Данные перенесены с агрегацией дочерних записей');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ОШИБКА: ' || SQLERRM);
        RAISE;
END analyze_and_create_nested_table;
/

BEGIN
    -- Пример: parent = CLIENT, child = PAYMENT
    analyze_and_create_nested_table(
            p_parent_table => 'CLIENT',
            p_child_table  => 'INSURANCE_CONTRACT'
    );
END;
/



