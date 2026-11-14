# Write your MySQL query statement below
SELECT unique_id, name
#start with employee, glue employeeuni column on to it
FROM Employees
#need join because unique_id is from other table
LEFT JOIN EmployeeUNI
#look for rows with same id
ON Employees.id = EmployeeUNI.id
