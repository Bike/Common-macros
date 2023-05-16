(cl:in-package #:common-macros)

(defmacro cond (&rest clauses)
  (labels ((aux (clauses)
             (if (null clauses)
                 nil
                 (let ((clause (car clauses)))
                   (if (not (and (proper-list-p clause)
                                 (not (null clause))))
                       (error 'malformed-cond-clause
                              :clause clause)
                       (if (null (cdr clause))
                           `(or ,(car clause)
                                ,(aux (cdr clauses)))
                           `(if ,(car clause)
                                (progn ,@(cdr clause))
                                ,(aux (cdr clauses)))))))))
    (unless (proper-list-p clauses)
      (error 'malformed-cond-clauses
             :clauses clauses))
    (aux clauses)))
