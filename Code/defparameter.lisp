(cl:in-package #:common-macros)

;;; This code is inspred by the dictionary page on DEFPARAMETER in the
;;; Common Lisp standard.

(defmethod expand (client (ast ico:defparameter-ast) environment)
  (declare (ignore client environment))
  (let ((variable-name-ast (ico:variable-name-ast ast))
        (form-ast (ico:form-ast ast))
        (documentation-ast (ico:documentation-ast ast)))
    (node* (:progn)
      (1 :form
         (node* (:declaim)
           (1 :declaration-specifier
              (node* (:declaration-specifier :kind 'special)
                (1 :argument variable-name-ast)))))
      (1 :form
         (node* (:setf)
           (1 :name variable-name-ast)
           (1 :value form-ast)))
      (abp:? :form
             (if (null documentation-ast)
                 nil
                 (node* (:setf)
                   (1 :place
                      (application 'documentation variable-name-ast
                                   (node* (:quote :object 'variable))))
                   (1 :value documentation-ast))))
      (1 :form variable-name-ast))))
