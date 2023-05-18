(cl:in-package #:common-macros)

(defmacro cmd:case (&whole form keyform &rest clauses)
  (declare (ignore keyform clauses))
  (let* ((builder (make-instance 'bld:builder))
         (syntax (ses:find-syntax 'case))
         (ast (ses:parse builder syntax form))
         (keyform-ast (ico:form-ast ast))
         (keyform (ico:form keyform-ast))
         (form-variable (gensym)))
    (labels ((process-clauses (clause-asts)
               (if (null clause-asts)
                   'nil
                   (let* ((clause-ast (first clause-asts))
                          (form-asts (ico:form-asts clause-ast))
                          (forms (mapcar #'ico:form form-asts)))
                     (if (typep clause-ast 'ico:case-otherwise-clause-ast)
                         `(progn ,@forms)
                         (let* ((key-asts (ico:key-asts clause-ast))
                                (keys (mapcar #'ico:key key-asts))
                                (tests (mapcar (lambda (key)
                                                 `(eql ,form-variable ,key))
                                               keys)))
                           `(if (or ,@tests)
                                (progn ,@forms)
                                ,(process-clauses (rest clause-asts)))))))))
      `(let (,form-variable ,keyform)
         ,(process-clauses (ico:clause-asts ast))))))
