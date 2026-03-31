-- Tier 1 Challenge 1: At-risk projects
SELECT 
    p.name AS project_name,
    p.budget,
    SUM(pa.hours_allocated) AS total_allocated_hours,
    p.budget * 0.8 AS risk_limit
FROM projects p
JOIN project_assignments pa
    ON p.project_id = pa.project_id
GROUP BY p.project_id, p.name, p.budget
HAVING SUM(pa.hours_allocated) > p.budget * 0.8
ORDER BY total_allocated_hours DESC;

-- Tier 1 Challenge 2: cross-department analysis
SELECT
    e.employee_id,
    e.first_name,
    e.last_name,
    e.department_id AS employee_department_id,
    p.project_id,
    p.name AS project_name,
    pa.role
FROM employees e
JOIN project_assignments pa
    ON e.employee_id = pa.employee_id
JOIN projects p
    ON pa.project_id = p.project_id
WHERE e.department_id IS NOT NULL
ORDER BY e.employee_id, p.project_id;

-- Tier 2: Department summary view
CREATE OR REPLACE VIEW department_summary_view AS
SELECT
    d.department_id,
    d.name AS department_name,
    COUNT(e.employee_id) AS employee_count,
    COALESCE(SUM(e.salary), 0) AS total_salary
FROM departments d
LEFT JOIN employees e
    ON d.department_id = e.department_id
GROUP BY d.department_id, d.name;

-- Tier 2: Project status view
CREATE OR REPLACE VIEW project_status_view AS
SELECT
    p.project_id,
    p.name AS project_name,
    p.budget,
    COALESCE(SUM(pa.hours_allocated), 0) AS total_allocated_hours,
    CASE
        WHEN COALESCE(SUM(pa.hours_allocated), 0) > p.budget * 0.8 THEN 'At Risk'
        ELSE 'Healthy'
    END AS project_status
FROM projects p
LEFT JOIN project_assignments pa
    ON p.project_id = pa.project_id
GROUP BY p.project_id, p.name, p.budget;

-- Tier 2: Function returning JSON
CREATE OR REPLACE FUNCTION get_department_report(dept_name TEXT)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    dept_id_var INT;
    emp_count INT;
    total_salary NUMERIC(12,2);
    active_projects_count INT;
BEGIN
    SELECT department_id
    INTO dept_id_var
    FROM departments
    WHERE name = dept_name;

    SELECT COUNT(*), COALESCE(SUM(salary), 0)
    INTO emp_count, total_salary
    FROM employees
    WHERE department_id = dept_id_var;

    SELECT COUNT(DISTINCT pa.project_id)
    INTO active_projects_count
    FROM employees e
    JOIN project_assignments pa
        ON e.employee_id = pa.employee_id
    WHERE e.department_id = dept_id_var;

    RETURN json_build_object(
        'employee_count', emp_count,
        'total_salary', total_salary,
        'active_projects', active_projects_count
    );
END;
$$;

-- Tier 3: salary_history table
DROP TABLE IF EXISTS salary_history;

CREATE TABLE salary_history (
    salary_history_id SERIAL PRIMARY KEY,
    employee_id INTEGER REFERENCES employees(employee_id),
    salary_amount NUMERIC(12,2) NOT NULL,
    effective_date DATE NOT NULL,
    end_date DATE
);

-- Tier 3: migration script
INSERT INTO salary_history (employee_id, salary_amount, effective_date, end_date)
SELECT
    employee_id,
    salary,
    hire_date,
    NULL
FROM employees;

-- Tier 3: salary growth by department over time
SELECT
    d.name AS department_name,
    EXTRACT(YEAR FROM sh.effective_date) AS salary_year,
    AVG(sh.salary_amount) AS avg_salary
FROM salary_history sh
JOIN employees e
    ON sh.employee_id = e.employee_id
JOIN departments d
    ON e.department_id = d.department_id
GROUP BY d.name, EXTRACT(YEAR FROM sh.effective_date)
ORDER BY d.name, salary_year;

-- Tier 3: employees due for salary review
SELECT
    e.employee_id,
    e.first_name,
    e.last_name,
    MAX(sh.effective_date) AS last_salary_change
FROM employees e
JOIN salary_history sh
    ON e.employee_id = sh.employee_id
GROUP BY e.employee_id, e.first_name, e.last_name
HAVING MAX(sh.effective_date) <= CURRENT_DATE - INTERVAL '12 months'
ORDER BY last_salary_change;

-- Tier 3 Challenge 4: Production Migration Plan
-- 1. Add the new salary_history table without removing the existing salary column.
-- 2. Backfill historical salary data in batches.
-- 3. Validate row counts, totals, and effective dates after each batch.
-- 4. Test the migration in a staging environment before production cutover.
-- 5. Mitigate risks: avoid duplicates, missing rows, incorrect dates, and handle live data changes carefully.
-- 6. Use transactions and backups where possible; switch application writes only after full verification.