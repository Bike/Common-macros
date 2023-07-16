(cl:in-package #:common-macros)

(defmethod expand (client (ast ico:defgeneric-ast) environment)
  (declare (ignore client environment))
  (node* (:progn)
    (1 :form
       (node* (:application)
         (1 :function-name (make-function-name-ast 'ensure-generic-function))
         (* :argument
            (list (node* (:literal :value ':lambda-list))
                  (node* (:quote :object (unparse (ico:lambda-list-ast ast))))))
         (* :argument
            (if (null (ico:argument-precedence-order-asts ast))
                '()
                (list (node* (:literal :value ':argument-precedence-order))
                      (node* (:quote
                              :object
                              (mapcar #'unparse
                                      (ico:argument-precedence-order-asts ast)))))))
         (* :argument
            (if (null (ico:documentation-ast ast))
                '()
                (list (node* (:literal :value ':documentation))
                      (unparse (ico:documentation-ast ast)))))
         (* :argument
            (if (null (ico:generic-function-class-ast ast))
                '()
                (list (node* (:literal :value ':generic-function-class))
                      (node* (:quote
                              :object
                              (unparse (ico:generic-function-class-ast ast)))))))
         (* :argument
            (if (null (ico:method-class-ast ast))
                '()
                (list (node* (:literal :value ':method-class))
                      (node* (:quote
                              :object
                              (unparse (ico:method-class-ast ast)))))))
         ;; The AMOP version of ENSURE-GENERIC-FUNCTION has a keyword
         ;; parameter DECLARATIONS, but the version in the Common Lisp
         ;; standard has a keyword parameter DECLARE.  Either way, we don't
         ;; handle this option yet.
         (* :argument
            (let ((name-and-arguments
                    (ico:method-combination-name-and-arguments-ast ast)))
              (if (null name-and-arguments)
                  '()
                  (list (node* (:literal :value ':method-combination))
                        (application
                         'find-method-combination
                         ;; We do not include the GENERIC-FUNCTION argument.
                         (node* (:quote :object (ico:name name-and-arguments)))
                         (node* (:quote
                                 :object
                                 (ico:method-combination-arguments
                                  name-and-arguments))))))))))
    (* :argument
       ;; This is not quite right.  We also need to register the
       ;; methods as having been defined as part of the DEFGENERIC
       ;; form, so that they can be removed if they are not present
       ;; in a new evaluation of the DEFGENERIC form.
       (loop for method-description-ast in (ico:method-description-asts ast)
             collect
             (node* (:defmethod)
               (1 :name (ico:name-ast ast))
               (* :method-qualifier (ico:method-qualifier-asts ast))
               (1 :lambda-list (ico:lambda-list-ast ast))
               (* :declaration (ico:declaration-asts ast))
               (* :documentation
                  (if (null (ico:documentation-ast ast))
                      '()
                      (list (ico:documentation-ast ast))))
               (* :form (ico:form-asts ast)))))))
                 
       
