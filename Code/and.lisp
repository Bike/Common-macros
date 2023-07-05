(cl:in-package #:common-macros)

(defmethod expand ((ast ico:and-ast) environment)
  (declare (ignore environment))
  (let ((form-asts (ico:form-asts ast))
        (origin (ico:origin ast)))
    (abp:with-builder ((make-instance 'bld:builder))
      (cond ((null form-asts)
             (abp:node* (:literal :literal 't :source origin)))
            ((null (rest form-asts))
             (first form-asts))
            (t
             (abp:node* (:if :source origin)
               (1 :test (first form-asts))
               (1 :then
                  (abp:node* (:and :source origin)
                    (* :form (rest form-asts))))
               (1 :else
                  (abp:node* (:literal :literal 'nil :source origin)))))))))
