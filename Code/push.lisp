(cl:in-package #:common-macros)

(defmethod expand (client (ast ico:push-ast) environment)
  (declare (ignore client))
  (multiple-value-bind
        (binding-asts store-variable-asts store-ast read-ast)
      (expand-place-ast (ico:place-ast ast) environment)
    (let ((item-var (gensym)))
      (node* (:let*)
        (1 :binding
           (make-let-binding-ast
            (make-variable-name-ast item-var) (ico:item-ast ast)))
        (* :binding binding-asts)
        (1 :binding
           (make-let-binding-ast
            (first store-variable-asts)
            (application 'cons (make-variable-name-ast item-var) read-ast)))
        (1 :form store-ast)))))
