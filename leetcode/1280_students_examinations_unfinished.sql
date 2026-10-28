# Write your MySQL query statement below
SELECT Examinations.student_id,
       Students.student_name,
       Subjects.subject_name,
       COUNT(Students.student_id) AS attended_exams
FROM Students, Examinations, Subjects
CROSS JOIN Subjects.subject_name
LEFT JOIN Examinations.subject_name
    ON Subjec
#idk how to finish ts bro
