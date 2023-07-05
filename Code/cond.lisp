(cl:in-package #:common-macros)

(defmethod expand ((ast ico:cond-ast) environment)
  (declare (ignore environment))
  (let ((clause-asts (ico:clause-asts ast)))
    (abp:with-builder ((make-instance 'builder))
      (if (null clause-asts)
          (abp:node* (:unparsed :expression 'nil))
          (let* ((first-clause-ast (first clause-asts))
                 (origin (ico:origin first-clause-ast))
                 (test-ast (ico:test-ast first-clause-ast))
                 (form-asts (ico:form-asts first-clause-ast))
                 (remaining-cond-ast
                   (abp:node* (:cond) (* :clause (rest clause-asts)))))
            (if (null form-asts)
                (abp:node* (:or :source origin)
                  (* :form (list test-ast remaining-cond-ast)))
                (abp:node* (:if :source origin)
                  (1 :test test-ast)
                  (1 :then (abp:node* (:progn) (* :form form-asts)))
                  (1 :else remaining-cond-ast))))))))
