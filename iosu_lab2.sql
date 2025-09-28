-- Вариант 16. Создайте запросы: «Клиенты, застраховавшие свою жизнь за
-- последний месяц» (условная выборка); «Сводка полученных/выплаченных сумм
-- страховок по клиентам» (итоговый запрос); «Объекты, застрахованные на задан-ную сумму» (параметрический запрос);
-- «Общий список клиентов и агентов с количеством договоров у каждого» (запрос на объединение);
-- «Заключенные до-говора по кварталам за два последних года» (запрос по полю с типом дата).

-- Клиенты, застраховавшие свою жизнь за последний месяц
SELECT
    c.first_name AS first_name,
    c.last_name AS last_name,
    c.birth_date AS birth_date,
    ic.contract_date AS contract_date,
    it.name AS insurance_type
FROM client c
         JOIN insurance_contract ic ON c.id = ic.client_id
         JOIN insurance_type it ON ic.insurance_type_id = it.id
WHERE it.name = 'Жизнь'
  AND ic.contract_date BETWEEN TRUNC(SYSDATE, 'MM') AND LAST_DAY(SYSDATE)
ORDER BY ic.contract_date DESC, c.last_name, c.first_name;

-- Сводка полученных/выплаченных сумм страховок по клиентам
SELECT
    c.first_name AS first_name,
    c.last_name AS last_name,
    SUM(ic.premium) AS total_premium,
    COALESCE(SUM(p.amount), 0) AS paid_premium
FROM client c
         JOIN insurance_contract ic ON c.id = ic.client_id
         LEFT JOIN payment p ON ic.id = p.insurance_contract_id
GROUP BY c.id, c.first_name, c.last_name
HAVING COUNT(ic.id) > 0
ORDER BY total_premium DESC, c.last_name, c.first_name;

-- Параметрический запрос: «Объекты, застрахованные на заданную сумму»
SELECT
    c.last_name AS client_last_name,
    c.first_name AS client_first_name,
    it.name AS insurance_type,
    ic.contract_date AS contract_date,
    it.max_payout AS max_payout
FROM insurance_contract ic
         JOIN client c ON ic.client_id = c.id
         JOIN insurance_type it ON ic.insurance_type_id = it.id
WHERE it.max_payout = :p_max_payout
  AND ic.contract_status = 'Активен'
ORDER BY c.last_name, c.first_name, ic.contract_date DESC;

-- Запрос на объединение: «Общий список клиентов и агентов с количеством договоров у каждого»
SELECT
    'Client' AS role,
    first_name AS first_name,
    last_name AS last_name,
    (SELECT COUNT(*) FROM insurance_contract WHERE client_id = c.id) AS contract_count
FROM client c
WHERE (SELECT COUNT(*) FROM insurance_contract WHERE client_id = c.id) > 0

UNION ALL

SELECT
    'Agent' AS role,
    first_name AS first_name,
    last_name AS last_name,
    (SELECT COUNT(*) FROM insurance_contract WHERE agent_id = a.id) AS contract_count
FROM agent a
WHERE (SELECT COUNT(*) FROM insurance_contract WHERE agent_id = a.id) > 0

ORDER BY role DESC, contract_count DESC, last_name, first_name;

-- «Заключенные до-говора по кварталам за два последних года» (запрос по полю с типом дата).
SELECT
    EXTRACT(YEAR FROM contract_date) AS year,
    'Q' || TO_CHAR(contract_date, 'Q') AS quarter,
    COUNT(*) AS contract_count
FROM insurance_contract
WHERE contract_date BETWEEN ADD_MONTHS(TRUNC(SYSDATE, 'YEAR'), -24) AND LAST_DAY(ADD_MONTHS(TRUNC(SYSDATE, 'YEAR'), -1))
GROUP BY EXTRACT(YEAR FROM contract_date), TO_CHAR(contract_date, 'Q')
HAVING COUNT(*) > 0
ORDER BY year DESC, quarter DESC;

