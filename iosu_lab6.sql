-- Динамическая процедура с DBMS_SQL (SELECT заранее неизвестен)
CREATE OR REPLACE PROCEDURE exec_dynamic_select(p_query IN VARCHAR2) AUTHID CURRENT_USER IS
    l_cursor   INTEGER;
l_col_cnt  INTEGER;
l_desc_tab DBMS_SQL.DESC_TAB;
l_varchar  VARCHAR2(4000);
l_status   INTEGER;
BEGIN
l_cursor := DBMS_SQL.OPEN_CURSOR;
DBMS_SQL.PARSE(l_cursor, p_query, DBMS_SQL.NATIVE);

DBMS_SQL.DESCRIBE_COLUMNS(l_cursor, l_col_cnt, l_desc_tab);

    -- привязка всех колонок как строк
FOR i IN 1 .. l_col_cnt LOOP
        DBMS_SQL.DEFINE_COLUMN(l_cursor, i, l_varchar, 4000);
END LOOP;

l_status := DBMS_SQL.EXECUTE(l_cursor);

    -- выборка
WHILE DBMS_SQL.FETCH_ROWS(l_cursor) > 0 LOOP
        FOR i IN 1 .. l_col_cnt LOOP
            DBMS_SQL.COLUMN_VALUE(l_cursor, i, l_varchar);
DBMS_OUTPUT.PUT_LINE('col' || i || ' = ' || l_varchar);
END LOOP;
DBMS_OUTPUT.PUT_LINE('-------------------------');
END LOOP;

DBMS_SQL.CLOSE_CURSOR(l_cursor);
EXCEPTION
    WHEN OTHERS THEN
        IF DBMS_SQL.IS_OPEN(l_cursor) THEN
            DBMS_SQL.CLOSE_CURSOR(l_cursor);
END IF;
RAISE;
END;
/

BEGIN
    exec_dynamic_select('SELECT first_name, last_name FROM client WHERE ROWNUM <= 5');
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


-- Коллекция для хранения строк дочерней таблицы
CREATE OR REPLACE TYPE t_child_records AS TABLE OF VARCHAR2(4000);
/

CREATE OR REPLACE PROCEDURE check_and_create_nested_table(
    p_parent_table IN VARCHAR2,
    p_child_table  IN VARCHAR2
) AUTHID CURRENT_USER AS
    v_parent_col   VARCHAR2(100);
    v_child_col    VARCHAR2(100);
    v_new_table    VARCHAR2(100);
    v_sql          CLOB;
    v_count        NUMBER;
    v_cols         VARCHAR2(4000);
BEGIN
    -- 1. Проверка FK
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
    SELECT COUNT(*)
    INTO v_count
    FROM user_tables
    WHERE table_name = UPPER(v_new_table);

    IF v_count > 0 THEN
        EXECUTE IMMEDIATE 'DROP TABLE ' || v_new_table || ' PURGE';
    END IF;

    -- 4. Собираем список всех колонок дочерней таблицы
    SELECT LISTAGG('NVL(TO_CHAR(c.' || column_name || '),''NULL'')', ' || '':'' || ')
                   WITHIN GROUP (ORDER BY column_id)
    INTO v_cols
    FROM user_tab_columns
    WHERE table_name = UPPER(p_child_table);

    -- 5. Строим SQL для создания таблицы с nested column
    v_sql := 'CREATE TABLE ' || v_new_table || ' AS
              SELECT p.*,
                     CAST( MULTISET(
                        SELECT ' || v_cols || '
                        FROM ' || p_child_table || ' c
                        WHERE c.' || v_child_col || ' = p.' || v_parent_col || '
                     ) AS t_child_records) AS child_records
              FROM ' || p_parent_table || ' p';

    EXECUTE IMMEDIATE v_sql;

    DBMS_OUTPUT.put_line('Создана таблица: ' || v_new_table);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.put_line('Связь "один ко многим" между ' || p_parent_table ||
                             ' и ' || p_child_table || ' не найдена.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.put_line('Ошибка: ' || SQLERRM);
END;
/



