# SQL Cheatsheet for Data Science Interview Practice

Oct 23, 2026 · @Armand

## 1. Read this first: how SQL actually runs

Most interview problems reduce to a join, a GROUP BY, or a window function, and most bugs come from forgetting the order SQL evaluates a query. Learn this order once and sections 3 to 9 become lookup material while you solve.

You write `SELECT` first, but the database runs a query in this order:

1. `FROM` / `JOIN`: build the working table
2. `WHERE`: filter individual rows (before any grouping)
3. `GROUP BY`: collapse rows into groups
4. `HAVING`: filter groups (after aggregation)
5. `SELECT`: compute columns, aggregates and window functions
6. `DISTINCT`: drop duplicate result rows
7. `ORDER BY`: sort (the only step that can use SELECT aliases everywhere)
8. `LIMIT` / `OFFSET` / `TOP`: trim the result

What this explains:

- You cannot filter on an aggregate in `WHERE`. Use `HAVING`.
- You cannot filter on a window function in `WHERE` (it runs later, in step 5). Compute it in a CTE or subquery, then filter outside.
- A column alias from `SELECT` generally can't be used in `WHERE`. Repeat the expression or wrap the query in a CTE.
- `WHERE` runs before the join result is grouped, so it changes what gets counted. `HAVING` does not.

**Solving routine that works for most problems:** (1) say in one sentence what one row of the output represents, (2) decide which table(s) and join(s) you need, (3) write the filters, (4) decide whether you need GROUP BY or a window function, (5) only then write the SELECT list.

## 2. Core query anatomy

Every query is some subset of this skeleton, in this written order.

```sql
SELECT   DISTINCT col1, col2 AS alias, expr
FROM     table_a a
JOIN     table_b b ON a.id = b.a_id
WHERE    condition
GROUP BY col1, col2
HAVING   aggregate_condition
ORDER BY col1 DESC, col2 ASC
LIMIT    10 OFFSET 20;   -- SQL Server: SELECT TOP 10 ... / OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY
```

**Filter operators**

| Need | Syntax | Watch out |
| --- | --- | --- |
| Equality, comparison | `=`, `<>` (or `!=`), `<`, `>=` | `= NULL` never matches; use `IS NULL` |
| Range (inclusive) | `x BETWEEN 5 AND 10` | Both ends included; with dates and timestamps the end-of-day matters |
| Membership | `x IN (1, 2, 3)` | `NOT IN` returns nothing if the list contains a NULL |
| Pattern | `name LIKE 'A%'`, `'%son'`, `'_ob'` | `%` = any length, `_` = exactly one character |
| Null check | `x IS NULL`, `x IS NOT NULL` |  |
| Combine | `AND`, `OR`, `NOT` | `AND` binds tighter than `OR`; add parentheses |

**Handy basics**

- `SELECT COUNT(*) FROM t;` counts rows. `SELECT DISTINCT col FROM t;` lists unique values.
- `ORDER BY 2 DESC` sorts by the second SELECT column (works, but avoid in real code).
- Always add a tiebreaker to `ORDER BY ... LIMIT` when ties matter, e.g. `ORDER BY score DESC, id ASC`.
- `ILIKE` is case-insensitive LIKE in PostgreSQL only. In MySQL, LIKE is usually case-insensitive already; elsewhere use `LOWER(col) LIKE ...`.
- Rename on the fly with `AS`. Table aliases (`FROM employees e`) are essential for joins.

## 3. Aggregation: GROUP BY and HAVING

Rule: every column in `SELECT` must either be inside an aggregate function or appear in `GROUP BY`.

```sql
SELECT department, COUNT(*) AS headcount, AVG(salary) AS avg_salary
FROM employees
WHERE active = 1               -- filters rows BEFORE grouping
GROUP BY department
HAVING COUNT(*) >= 5           -- filters groups AFTER aggregating
ORDER BY avg_salary DESC;
```

**The aggregates:** `COUNT`, `SUM`, `AVG`, `MIN`, `MAX`. All ignore NULLs, except `COUNT(*)`.

| Expression | Counts |
| --- | --- |
| `COUNT(*)` | All rows, including those with NULLs |
| `COUNT(col)` | Rows where `col` is not NULL |
| `COUNT(DISTINCT col)` | Unique non-NULL values of `col` |

**Conditional aggregation** is the most reusable trick in SQL interviews. It builds several filtered counts or sums in one pass, and it is also how you pivot rows into columns.

```sql
SELECT
  user_id,
  COUNT(*)                                   AS total_orders,
  SUM(CASE WHEN status = 'returned' THEN 1 ELSE 0 END) AS returned_orders,
  AVG(CASE WHEN status = 'returned' THEN 1.0 ELSE 0 END) AS return_rate,
  SUM(CASE WHEN category = 'A' THEN amount ELSE 0 END) AS a_revenue
FROM orders
GROUP BY user_id;
```

**Gotchas**

- Integer division truncates in PostgreSQL, SQL Server and others. Use `1.0 * a / b` or `CAST(a AS DECIMAL) / b` for percentages.
- `AVG` over a column with NULLs averages only the non-NULL rows. If NULL should count as zero, use `AVG(COALESCE(col, 0))`.
- To find the group with the max count, you cannot nest aggregates. Use `ORDER BY COUNT(*) DESC LIMIT 1`, or a window function (section 6) if ties matter.
- `GROUP BY` multiple columns groups by the unique combination of them.
- A group with zero rows does not exist. To show zeros (e.g. customers with no orders), start from the full table with a `LEFT JOIN`.

## 4. Joins

Pick the join by asking which table's rows must all survive.

| Join | Keeps | Typical use |
| --- | --- | --- |
| `INNER JOIN` | Only rows that match in both tables | Orders with their customer details |
| `LEFT JOIN` | All left rows; right columns are NULL when no match | Customers including those with no orders |
| `RIGHT JOIN` | All right rows (rarely used; swap the tables and use LEFT) |  |
| `FULL OUTER JOIN` | All rows from both sides | Reconciling two lists. Not in MySQL |
| `CROSS JOIN` | Every left row paired with every right row | Generating combinations, date spines |

```sql
-- Customers and their order totals, including customers with no orders
SELECT c.customer_id, c.name, COALESCE(SUM(o.amount), 0) AS total
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.name;
```

**Anti-join: rows in A with no match in B** (very common: "customers who never ordered")

```sql
SELECT c.*
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.customer_id IS NULL;

-- equivalent, often clearer:
SELECT * FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id);
```

**Self-join: comparing rows within one table** (employees vs their managers, consecutive days, pairs)

```sql
SELECT e.name AS employee, m.name AS manager
FROM employees e
LEFT JOIN employees m ON e.manager_id = m.employee_id;

-- employees earning more than their manager
SELECT e.name
FROM employees e JOIN employees m ON e.manager_id = m.employee_id
WHERE e.salary > m.salary;
```

**Gotchas**

- A filter on the right table in `WHERE` turns a `LEFT JOIN` into an inner join, because the NULL rows get filtered out. Put the condition in the `ON` clause to keep unmatched rows: `LEFT JOIN orders o ON o.customer_id = c.id AND o.status = 'paid'`.
- Row explosion: joining one-to-many tables (orders and order\_items) multiplies rows. Aggregate before joining, or count with `COUNT(DISTINCT ...)`.
- Joining on a column that has NULLs never matches those rows (`NULL = NULL` is not true).
- `USING (col)` is shorthand for `ON a.col = b.col` when both tables share the column name (not in SQL Server).

## 5. Subqueries and CTEs

A CTE (`WITH`) is a named subquery. Prefer it over nested subqueries: it reads top to bottom and you can test each step on its own.

```sql
WITH dept_avg AS (
  SELECT department_id, AVG(salary) AS avg_sal
  FROM employees
  GROUP BY department_id
),
above_avg AS (
  SELECT e.*
  FROM employees e
  JOIN dept_avg d ON d.department_id = e.department_id
  WHERE e.salary > d.avg_sal
)
SELECT * FROM above_avg;
```

**Where a subquery can appear**

| Location | Example | Must return |
| --- | --- | --- |
| `WHERE` (scalar) | `WHERE salary > (SELECT AVG(salary) FROM employees)` | Exactly one value |
| `WHERE ... IN` | `WHERE id IN (SELECT user_id FROM orders)` | One column |
| `WHERE EXISTS` | `WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id)` | Anything (only existence matters) |
| `FROM` (derived table) | `FROM (SELECT ... ) t` | A table; needs an alias |
| `SELECT` | `SELECT name, (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id) FROM users u` | One value per row |

**Correlated subquery:** it references the outer query and conceptually runs once per outer row. Fine for interview problems, but a join or window function is usually faster.

**IN vs EXISTS**

- `EXISTS` stops at the first match and is safe with NULLs.
- `NOT IN` breaks if the subquery returns any NULL (the whole condition becomes unknown and returns no rows). Prefer `NOT EXISTS` or filter with `WHERE col IS NOT NULL` inside.

**Recursive CTE** (hierarchies, generating number or date series): an anchor query `UNION ALL` a query that references the CTE itself.

```sql
WITH RECURSIVE org AS (          -- SQL Server and Oracle omit the word RECURSIVE
  SELECT employee_id, manager_id, 1 AS depth
  FROM employees WHERE manager_id IS NULL
  UNION ALL
  SELECT e.employee_id, e.manager_id, o.depth + 1
  FROM employees e JOIN org o ON e.manager_id = o.employee_id
)
SELECT * FROM org;
```

## 6. Window functions

A window function computes a value across a set of related rows without collapsing them, so you keep every row. This is the section most worth practicing: it unlocks top-N per group, running totals, period-over-period change and streak problems.

```sql
function() OVER (
  PARTITION BY col      -- restart the calculation per group (optional)
  ORDER BY col          -- ordering inside the group (needed for ranking, LAG, running totals)
  ROWS BETWEEN ... AND ...   -- frame (optional)
)
```

**Ranking functions** (example: salaries 100, 100, 90)

| Function | Result for the three rows | Behavior on ties |
| --- | --- | --- |
| `ROW_NUMBER()` | 1, 2, 3 | Arbitrary but unique; no ties |
| `RANK()` | 1, 1, 3 | Ties share a rank, then a gap |
| `DENSE_RANK()` | 1, 1, 2 | Ties share a rank, no gap |
| `NTILE(n)` | Buckets 1 to n | Splits rows into n roughly equal groups (quartiles, deciles) |

**Row-to-row functions**

```sql
LAG(revenue, 1)  OVER (PARTITION BY store ORDER BY month)  -- previous row's value
LEAD(revenue, 1) OVER (PARTITION BY store ORDER BY month)  -- next row's value
FIRST_VALUE(price) OVER (PARTITION BY user_id ORDER BY ts)
LAG(revenue, 1, 0) OVER (...)   -- third argument = default instead of NULL
```

**Aggregates as window functions**

```sql
SUM(amount) OVER (PARTITION BY user_id)                       -- group total on every row
SUM(amount) OVER (PARTITION BY user_id ORDER BY order_date)   -- running total
AVG(amount) OVER (ORDER BY order_date
                  ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)   -- 7-row moving average
amount * 1.0 / SUM(amount) OVER ()                            -- share of grand total
```

**Frames, in short**

- With `ORDER BY` and no explicit frame, the default frame is `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. Rows with the same ORDER BY value are treated as peers, so a running total jumps by all tied rows at once. Add `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` for a strict row-by-row total.
- `LAG`, `LEAD` and ranking functions ignore frames.
- `LAST_VALUE` needs an explicit frame ending at `UNBOUNDED FOLLOWING`, or it just returns the current row.

**You cannot filter on a window function in `WHERE`.** Wrap it:

```sql
WITH ranked AS (
  SELECT *, DENSE_RANK() OVER (PARTITION BY department_id ORDER BY salary DESC) AS rnk
  FROM employees
)
SELECT * FROM ranked WHERE rnk <= 3;
```

Availability: MySQL 8.0+, PostgreSQL, SQL Server and Oracle all support window functions. MySQL 5.7 does not, which matters on older LeetCode problem sets.

## 7. NULLs, CASE, strings and dates

**NULL rules**

- Any comparison with NULL is unknown, not true: `NULL = NULL` and `NULL <> 5` both filter the row out. Test with `IS NULL`.
- `COALESCE(a, b, 0)` returns the first non-NULL argument. Use it to default missing values.
- `NULLIF(a, b)` returns NULL when `a = b`. Classic use: `x / NULLIF(y, 0)` to avoid division by zero.
- Aggregates skip NULLs (except `COUNT(*)`). `SUM` of an all-NULL group is NULL, not 0.
- Sorting: PostgreSQL puts NULLs last on `ASC` (control with `NULLS FIRST` / `NULLS LAST`). MySQL puts them first on `ASC`.

**CASE** works anywhere an expression does: SELECT, WHERE, ORDER BY, inside aggregates.

```sql
CASE
  WHEN score >= 90 THEN 'A'
  WHEN score >= 80 THEN 'B'
  ELSE 'C'                     -- without ELSE, unmatched rows give NULL
END AS grade
```

**String functions**

| Task | Common syntax | Dialect notes |
| --- | --- | --- |
| Concatenate | `CONCAT(a, ' ', b)` | `a \|\| b` in PostgreSQL and Oracle; `+` in SQL Server |
| Length | `LENGTH(s)` | `LEN(s)` in SQL Server |
| Substring | `SUBSTRING(s, start, len)` | 1-indexed. Oracle uses `SUBSTR` |
| First or last n chars | `LEFT(s, n)`, `RIGHT(s, n)` |  |
| Case, whitespace | `UPPER`, `LOWER`, `TRIM`, `LTRIM`, `RTRIM` |  |
| Replace | `REPLACE(s, 'old', 'new')` |  |
| Find position | `POSITION('x' IN s)` | `INSTR(s, 'x')` MySQL; `CHARINDEX('x', s)` SQL Server |
| Split on delimiter | `SPLIT_PART(s, ',', 2)` | PostgreSQL. MySQL: `SUBSTRING_INDEX` |
| Join values into one string | `STRING_AGG(name, ', ')` | `GROUP_CONCAT(name SEPARATOR ', ')` in MySQL |
| Regex match | `s ~ 'pattern'` | `REGEXP` in MySQL |

**Dates and times** are where dialects differ most. Check which database the site uses.

| Task | PostgreSQL | MySQL | SQL Server |
| --- | --- | --- | --- |
| Today | `CURRENT_DATE` | `CURDATE()` | `CAST(GETDATE() AS DATE)` |
| Extract year or month | `EXTRACT(YEAR FROM d)` | `YEAR(d)`, `MONTH(d)` | `YEAR(d)`, `MONTH(d)` |
| Truncate to month | `DATE_TRUNC('month', d)` | `DATE_FORMAT(d, '%Y-%m-01')` | `DATEFROMPARTS(YEAR(d), MONTH(d), 1)` |
| Add 7 days | `d + INTERVAL '7 days'` | `DATE_ADD(d, INTERVAL 7 DAY)` | `DATEADD(day, 7, d)` |
| Days between | `d2 - d1` (for DATE types) | `DATEDIFF(d2, d1)` | `DATEDIFF(day, d1, d2)` |
| Format as text | `TO_CHAR(d, 'YYYY-MM')` | `DATE_FORMAT(d, '%Y-%m')` | `FORMAT(d, 'yyyy-MM')` |

Note the argument order: MySQL's `DATEDIFF(end, start)` versus SQL Server's `DATEDIFF(unit, start, end)`.

**Casting:** `CAST(x AS INT)` works everywhere. PostgreSQL also accepts `x::int`. Cast a timestamp to a date with `CAST(ts AS DATE)` to group by day.

## 8. Set operations

Set operations stack the results of two queries that have the same number of columns with compatible types. Column names come from the first query.

| Operator | Returns | Notes |
| --- | --- | --- |
| `UNION ALL` | All rows from both queries | Fastest; keeps duplicates. Default choice |
| `UNION` | Rows from both, duplicates removed | Does a sort or hash to dedupe |
| `INTERSECT` | Rows present in both | Not in older MySQL (before 8.0.31) |
| `EXCEPT` | Rows in the first but not the second | Called `MINUS` in Oracle. Not in older MySQL |

```sql
-- all people who either bought or returned something, once each
SELECT user_id FROM purchases
UNION
SELECT user_id FROM returns;

-- combine two event tables into one, tagging the source
SELECT user_id, ts, 'login'  AS event FROM logins
UNION ALL
SELECT user_id, ts, 'signup' AS event FROM signups;
```

If `INTERSECT` or `EXCEPT` is unavailable, use `IN` / `EXISTS` for intersection and `NOT EXISTS` / an anti-join for the difference.

`ORDER BY` goes once, at the very end, and applies to the whole combined result.

## 9. Interview patterns

Most LeetCode, StrataScratch and HackerRank problems are one of about a dozen patterns. Match the wording of the problem to the tool first, then adapt the template below.

| If the problem says... | Reach for |
| --- | --- |
| top N, Nth highest, ranked per group | `DENSE_RANK` or `ROW_NUMBER` in a CTE, filter outside |
| latest, first or most recent per user | `ROW_NUMBER() OVER (PARTITION BY user ORDER BY ts DESC)`, keep `rn = 1` |
| never, without any, not in | Anti-join (`LEFT JOIN ... IS NULL`) or `NOT EXISTS` |
| compared to the previous, change since, growth | `LAG` / `LEAD` |
| running, cumulative, moving average | `SUM` / `AVG` `OVER (ORDER BY ...)` with a frame |
| consecutive, streak, in a row | Row-number difference trick, or `LAG` / `LEAD` |
| percentage, share, rate | `AVG(CASE WHEN ... THEN 1.0 ELSE 0 END)` or `x / SUM(x) OVER ()` |
| users who did both A and B | `GROUP BY user HAVING COUNT(DISTINCT type) = 2` |
| duplicates | `GROUP BY ... HAVING COUNT(*) > 1` |
| per month, per day, per week | Truncate the date, then `GROUP BY` |
| above the average of their group | Window `AVG() OVER (PARTITION BY ...)` or CTE join |
| median | `PERCENTILE_CONT(0.5)` or the row-number method below |
| employee and manager, hierarchy | Self-join; recursive CTE for unknown depth |

**Nth highest value** (returns NULL if it does not exist, which many problems require)

```sql
SELECT (
  SELECT DISTINCT salary FROM employees
  ORDER BY salary DESC
  LIMIT 1 OFFSET 1            -- OFFSET = N - 1
) AS second_highest_salary;
```

**Find duplicates, and keep one row per key**

```sql
SELECT email, COUNT(*) FROM users GROUP BY email HAVING COUNT(*) > 1;

WITH t AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY id) AS rn
  FROM users
)
SELECT * FROM t WHERE rn = 1;   -- order by ts DESC instead to get the latest row per key
```

**Month-over-month change**

```sql
WITH monthly AS (
  SELECT DATE_TRUNC('month', order_date) AS month, SUM(amount) AS revenue
  FROM orders
  GROUP BY DATE_TRUNC('month', order_date)
),
with_prev AS (
  SELECT month, revenue, LAG(revenue) OVER (ORDER BY month) AS prev_revenue
  FROM monthly
)
SELECT month, revenue,
       ROUND(100.0 * (revenue - prev_revenue) / NULLIF(prev_revenue, 0), 1) AS pct_change
FROM with_prev;
```

**Consecutive streaks (gaps and islands).** Within an unbroken run of dates, `date - row_number` is constant, so it labels each run.

```sql
WITH d AS (SELECT DISTINCT user_id, login_date FROM logins),   -- dedupe first
g AS (
  SELECT user_id, login_date,
         login_date - (ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_date))::int AS grp
  FROM d                       -- PostgreSQL. MySQL: DATE_SUB(login_date, INTERVAL ROW_NUMBER() OVER (...) DAY)
)                              -- SQL Server: DATEADD(day, -ROW_NUMBER() OVER (...), login_date)
SELECT user_id, MIN(login_date) AS start_date, MAX(login_date) AS end_date, COUNT(*) AS streak_days
FROM g
GROUP BY user_id, grp
HAVING COUNT(*) >= 3;
```

For consecutive integer ids (e.g. three or more consecutive rows), use the same idea with `id - ROW_NUMBER() OVER (ORDER BY id)`.

**Next-day retention** (share of users who came back the day after their first activity)

```sql
WITH first_day AS (
  SELECT player_id, MIN(event_date) AS first_date FROM activity GROUP BY player_id
)
SELECT ROUND(COUNT(a.player_id) * 1.0 / COUNT(f.player_id), 2) AS fraction
FROM first_day f
LEFT JOIN activity a
  ON a.player_id = f.player_id
 AND a.event_date = f.first_date + INTERVAL '1 day';   -- other dialects: see section 7
```

**Users who did both A and B**

```sql
SELECT user_id
FROM events
WHERE event_type IN ('A', 'B')
GROUP BY user_id
HAVING COUNT(DISTINCT event_type) = 2;
```

**Median**

```sql
-- PostgreSQL and Oracle (SQL Server needs PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) OVER ())
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) FROM employees;

-- works anywhere with window functions (MySQL 8 has no PERCENTILE_CONT)
WITH r AS (
  SELECT salary,
         ROW_NUMBER() OVER (ORDER BY salary) AS rn,
         COUNT(*) OVER () AS cnt
  FROM employees
)
SELECT AVG(salary) AS median
FROM r
WHERE rn IN (FLOOR((cnt + 1) / 2.0), CEILING((cnt + 1) / 2.0));
```

**Compare each row to its group** (no GROUP BY collapse)

```sql
SELECT name, department_id, salary,
       AVG(salary) OVER (PARTITION BY department_id) AS dept_avg,
       salary - AVG(salary) OVER (PARTITION BY department_id) AS diff_from_avg
FROM employees;
```

## 10. Dialect differences

Pick PostgreSQL as your default dialect. It is the closest to standard SQL, it has the richest feature set, and it is the flavor most data science interview platforms lean on. Each platform lets you choose a dialect per problem (the exact list varies and changes over time), so check the language selector before you start typing and note which one you used in your repo.

| Feature | PostgreSQL | MySQL 8 | SQL Server |
| --- | --- | --- | --- |
| Limit rows | `LIMIT n` | `LIMIT n` | `TOP n` or `OFFSET ... FETCH` |
| Quote an identifier | `"col"` | `` `col` `` | `[col]` |
| Concatenate strings | `a \|\| b` | `CONCAT(a, b)` | `a + b` or `CONCAT` |
| `FULL OUTER JOIN` | Yes | No (emulate: `LEFT JOIN UNION RIGHT JOIN`) | Yes |
| `INTERSECT` / `EXCEPT` | Yes | 8.0.31 and later | Yes |
| `5 / 2` | 2 (integer division) | 2.5 | 2 (integer division) |
| Replace NULL | `COALESCE` | `COALESCE`, `IFNULL` | `COALESCE`, `ISNULL` |
| Text comparison | Case-sensitive | Case-insensitive by default | Case-insensitive by default |
| Alias usable in `GROUP BY` | Yes | Yes | No |
| Recursive CTE | `WITH RECURSIVE` | `WITH RECURSIVE` | `WITH` (no keyword) |
| Median helper | `PERCENTILE_CONT ... WITHIN GROUP` | None; use the row-number method | `PERCENTILE_CONT ... OVER ()` |

If a query that looks right fails with a syntax error, the dialect is the first suspect.

## 11. Before you submit, and how to practice

**Check these before every submit** (they cause most wrong answers on otherwise correct queries)

- Does the output have exactly the columns, names and order the problem asks for?
- Are ties handled the way the problem says (`RANK` vs `DENSE_RANK` vs `ROW_NUMBER`)?
- Do customers or users with zero rows need to appear? If so, `LEFT JOIN`, and put right-table filters in `ON`.
- Did a join multiply rows? Check with `COUNT(*)` versus `COUNT(DISTINCT id)`.
- Could NULLs break it (`NOT IN`, `AVG`, `= NULL`, division by zero)?
- Is a percentage secretly integer division? Multiply by `1.0` first.
- Are dates truncated to the right unit, and is the end of a `BETWEEN` range inclusive of what you want?
- Does `ORDER BY` need a tiebreaker, and is `DISTINCT` hiding a bug rather than fixing one?

**When you are stuck without AI**

1. Write out in plain words what one row of the expected output means.
2. Build the query in layers: run the `FROM` / `JOIN` alone, add `WHERE`, add `GROUP BY`. In a CTE chain, `SELECT *` from each CTE to inspect it.
3. Compare your row count with the sample output. A mismatch usually means a join fan-out or a missing filter.
4. Google syntax, not solutions: search for "postgres date\_trunc week" or "mysql lag function", not the problem title. You learn the pattern and keep the problem yours.
5. After solving, rewrite once using a different tool (window function instead of subquery, or the reverse) and compare.

**Suggested order to practice** (move on when the easy problems in a tier feel automatic)

1. Filtering, sorting, `DISTINCT`, `LIKE`, `CASE`
2. `GROUP BY`, `HAVING`, conditional aggregation
3. Joins, especially `LEFT JOIN` with anti-join and self-join
4. Subqueries and CTEs
5. Window functions: ranking first, then `LAG` / `LEAD`, then running totals
6. The patterns in section 9, on medium and hard problems

For your repo, one file per problem (for example `leetcode/0184_department_highest_salary.sql`) with a short comment at the top giving the problem link, the dialect, and the pattern used. A line like that is what makes the repo useful when you revisit it before an interview.
