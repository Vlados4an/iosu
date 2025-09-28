-- 1. Клиенты (используем множественные INSERT)
INSERT INTO client (first_name, last_name, birth_date, phone_number) VALUES ('Иван', 'Петров', DATE '1985-03-15', '+375291234567');
INSERT INTO client (first_name, last_name, birth_date, phone_number) VALUES ('Мария', 'Сидорова', DATE '1990-07-22', '+375292345678');
INSERT INTO client (first_name, last_name, birth_date, phone_number) VALUES ('Алексей', 'Козлов', DATE '1978-11-30', '+375293456789');
INSERT INTO client (first_name, last_name, birth_date, phone_number) VALUES ('Елена', 'Николаева', DATE '1988-05-14', '+375294567890');
INSERT INTO client (first_name, last_name, birth_date, phone_number) VALUES ('Дмитрий', 'Васильев', DATE '1995-09-08', '+375295678901');
INSERT INTO client (first_name, last_name, birth_date, phone_number) VALUES ('Ольга', 'Павлова', DATE '1982-12-25', '+375296789012');
INSERT INTO client (first_name, last_name, birth_date, phone_number) VALUES ('Сергей', 'Смирнов', DATE '1975-04-18', '+375297890123');
INSERT INTO client (first_name, last_name, birth_date, phone_number) VALUES ('Анна', 'Федорова', DATE '1992-08-03', '+375298901234');
INSERT INTO client (first_name, last_name, birth_date, phone_number) VALUES ('Андрей', 'Морозов', DATE '1987-01-11', '+375299012345');
INSERT INTO client (first_name, last_name, birth_date, phone_number) VALUES ('Наталья', 'Захарова', DATE '1998-06-29', '+375291112233');

-- 3. Агенты
INSERT INTO agent (first_name, last_name, phone_number) VALUES ('Александр', 'Иванов', '+375291122334');
INSERT INTO agent (first_name, last_name, phone_number) VALUES ('Екатерина', 'Петрова', '+375291233445');
INSERT INTO agent (first_name, last_name, phone_number) VALUES ('Михаил', 'Сидоров', '+375291344556');
INSERT INTO agent (first_name, last_name, phone_number) VALUES ('Татьяна', 'Кузнецова', '+375291455667');
INSERT INTO agent (first_name, last_name, phone_number) VALUES ('Владимир', 'Попов', '+375291566778');
INSERT INTO agent (first_name, last_name, phone_number) VALUES ('Светлана', 'Лебедева', '+375291677889');
INSERT INTO agent (first_name, last_name, phone_number) VALUES ('Павел', 'Новиков', '+375291788990');
INSERT INTO agent (first_name, last_name, phone_number) VALUES ('Юлия', 'Волкова', '+375291899001');
INSERT INTO agent (first_name, last_name, phone_number) VALUES ('Игорь', 'Соловьев', '+375291900112');
INSERT INTO agent (first_name, last_name, phone_number) VALUES ('Людмила', 'Романова', '+375292011223');

-- 4. Договоры страхования (за последние 2 года)
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2024-03-25', 'Активен', 30, 1, 1, 1, 1200.00, 0.00);
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2024-03-20', 'Активен', 30, 2, 2, 1, 1500.00, 1500.00);
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2024-03-15', 'Активен', 30, 3, 3, 1, 1800.00, 0.00);
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2024-03-10', 'Активен', 30, 4, 4, 1, 900.00, 900.00);
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2024-03-05', 'Активен', 30, 5, 5, 1, 2000.00, 0.00);
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2024-02-28', 'Активен', 30, 6, 10, 2, 800.00, 0.00);
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2024-02-15', 'Активен', 30, 7, 10, 3, 2500.00, 2500.00);
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2024-01-20', 'Активен', 30, 8, 8, 4, 1200.00, 0.00);
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2024-01-10', 'Активен', 30, 9, 10, 5, 600.00, 600.00);
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2023-12-15', 'Активен', 30, 10, 10, 1, 1700.00, 0.00);
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2023-11-20', 'Активен', 30, 1, 1, 2, 950.00, 0.00);
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2023-10-25', 'Активен', 30, 2, 2, 3, 2200.00, 0.00);
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2023-09-30', 'Активен', 30, 3, 3, 4, 1100.00, 0.00);
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2023-08-15', 'Активен', 30, 4, 4, 5, 700.00, 0.00);
INSERT INTO insurance_contract (contract_date, contract_status, payout_deadline, agent_id, client_id, insurance_type_id, premium, unpaid_premium) VALUES (DATE '2023-07-10', 'Активен', 30, 5, 5, 1, 1600.00, 0.00);

-- 5. Страховые случаи
INSERT INTO insurance_case (description, title, urgency) VALUES ('ДТП на трассе М1', 'Дорожно-транспортное происшествие', '1');
INSERT INTO insurance_case (description, title, urgency) VALUES ('Пожар в квартире на кухне', 'Пожар в жилом помещении', '1');
INSERT INTO insurance_case (description, title, urgency) VALUES ('Экстренная операция аппендицита', 'Экстренная медицинская помощь', '1');
INSERT INTO insurance_case (description, title, urgency) VALUES ('Кража из автомобиля', 'Кража имущества', '0');
INSERT INTO insurance_case (description, title, urgency) VALUES ('Отмена поездки из-за болезни', 'Отмена путешествия', '0');
INSERT INTO insurance_case (description, title, urgency) VALUES ('Травма во время занятий спортом', 'Спортивная травма', '1');
INSERT INTO insurance_case (description, title, urgency) VALUES ('Затопление квартиры', 'Затопление жилья', '1');
INSERT INTO insurance_case (description, title, urgency) VALUES ('Потеря багажа во время перелета', 'Утеря багажа', '0');

-- 6. Заявки на выплаты
INSERT INTO compensation_claim (created_date, requested_amount, approved_amount, status, comment_text, case_id, insurance_contract_id, is_deleted) VALUES (DATE '2024-03-01', 5000.00, 5000.00, 'Одобрено', 'Полная компенсация одобрена', 1, 6, '0');
INSERT INTO compensation_claim (created_date, requested_amount, approved_amount, status, comment_text, case_id, insurance_contract_id, is_deleted) VALUES (DATE '2024-02-15', 15000.00, 12000.00, 'Одобрено', 'Частичная компенсация одобрена', 2, 7, '0');
INSERT INTO compensation_claim (created_date, requested_amount, approved_amount, status, comment_text, case_id, insurance_contract_id, is_deleted) VALUES (DATE '2024-01-20', 8000.00, 8000.00, 'Одобрено', 'Медицинские расходы покрыты', 3, 12, '0');
INSERT INTO compensation_claim (created_date, requested_amount, approved_amount, status, comment_text, case_id, insurance_contract_id, is_deleted) VALUES (DATE '2024-01-10', 3000.00, 0.00, 'Отклонено', 'Недостаточно документов', 4, 8, '0');
INSERT INTO compensation_claim (created_date, requested_amount, approved_amount, status, comment_text, case_id, insurance_contract_id, is_deleted) VALUES (DATE '2023-12-05', 2000.00, 2000.00, 'Одобрено', 'Расходы на поездку возмещены', 5, 9, '0');

-- 7. Платежи
INSERT INTO payment (amount, payment_date, insurance_contract_id) VALUES (1200.00, DATE '2024-03-25', 1);
INSERT INTO payment (amount, payment_date, insurance_contract_id) VALUES (1800.00, DATE '2024-03-16', 3);
INSERT INTO payment (amount, payment_date, insurance_contract_id) VALUES (2000.00, DATE '2024-03-05', 5);
INSERT INTO payment (amount, payment_date, insurance_contract_id) VALUES (800.00, DATE '2024-02-28', 6);
INSERT INTO payment (amount, payment_date, insurance_contract_id) VALUES (1200.00, DATE '2024-01-20', 8);
INSERT INTO payment (amount, payment_date, insurance_contract_id) VALUES (1700.00, DATE '2023-12-15', 10);
INSERT INTO payment (amount, payment_date, insurance_contract_id) VALUES (950.00, DATE '2023-11-20', 10);
INSERT INTO payment (amount, payment_date, insurance_contract_id) VALUES (2200.00, DATE '2023-10-25', 12);
INSERT INTO payment (amount, payment_date, insurance_contract_id) VALUES (1100.00, DATE '2023-09-30', 13);
INSERT INTO payment (amount, payment_date, insurance_contract_id) VALUES (700.00, DATE '2023-08-15', 14);
INSERT INTO payment (amount, payment_date, insurance_contract_id) VALUES (1600.00, DATE '2023-07-10', 15);