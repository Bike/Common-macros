(cl:in-package #:common-macros)

;;;; This code needs to be adapted to Iconoclast.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Function DESTRUCTURE-LAMBDA-LIST.
;;;
;;; Destructuring a tree according to a lambda list.
;;;
;;; The destructuring itself is typically done when a macro function
;;; is run, and the purpose is to take the macro form apart and assign
;;; parts of it to the parameters of the lambda list of the macro.
;;;
;;; The function DESTRUCTURE-LAMBDA-LIST generates the code for doing
;;; the destrucuring.  It is typically run by the expansion of
;;; DEFMACRO.  Recall that DEFMACRO must take the definition of a
;;; macro, in particular its lambda list, and generate a macro
;;; function.  The macro function takes the macro form as input and
;;; generates the expanded form.  Destructuring is done by a LET*
;;; form, and this code generates the bindings of that LET* form.
;;;
;;; It would have been more elegant to generate nested LET
;;; expressions, rather than a single LET*, because there are some
;;; arbitrary forms that need to be evaluated in between bindings, and
;;; those forms would fit more naturally into the body of a LET.  With
;;; a single LET* those forms must be part of the binding form of the
;;; LET*, and there is not always an obvious lexical variable to bind
;;; the result to.  So we must generate new variables and then ignore
;;; them in the LET* body.  But we do it this way because the DEFMACRO
;;; form may contain declarations that mention the variables in the
;;; DEFMACRO lambda list, and with nested LET expressions, some of
;;; those variables would then be introduced in a LET expression that
;;; is not the innermost one.  We could handle some such cases with
;;; LOCALLY, but IGNORE declarations result in warnings in some
;;; implementations.
;;;
;;; So, the bindings that we create will contain generated variables
;;; that are not used in the body of the macro definition, and we want
;;; them to be declared IGNORE.  For that reason,
;;; DESTRUCTURE-LAMBDA-LIST returns two values: the bindings mentioned
;;; above, and a list of variables to declare IGNORE in the beginning
;;; of the body of the macro function.
;;;
;;; The bindings return by DESTRUCTURE-LAMBDA-LIST and its subroutines
;;; are in the reverse order compared to the order it which they
;;; should appear in the expanded expression.  We do it this way in
;;; order to avoid too much consing.
;;;
;;; The lambda list is represented as an Iconoclast AST.

;;; Given a list of the remaining groups of a lambda list, return true
;;; if and only the list is not empty, and the first group of the list
;;; starts with LAMBDA-LIST-KEYWORD.
(defun first-group-is (remaining lambda-list-keyword)
  (and (not (null remaining))
       (not (null (first remaining)))
       (eq (first (first remaining)) lambda-list-keyword)))

(defun not-enough-arguments-ast ()
  (application 'error (aquote 'too-few-arguments)))

(defun add-binding-asts (variable-ast form-ast let*-ast)
  (reinitialize-instance let*-ast
    :binding-asts
    (append (ico:binding-asts let*-ast)
            (make-let-binding-ast variable-ast form-ast))))

(defun destructure-pattern (pattern-ast variable-ast let*-ast)
  (let ((temp-ast (node* (:variable-name :name (gensym)))))
    (add-binding-asts
     temp-ast
     (aif (application 'null variable-ast)
          (not-enough-arguments-ast)
          (application 'first variable-ast))
     let*-ast)
    (add-binding-asts
     variable-ast
     (application 'rest variable-ast)
     let*-ast)
    (destructure-lambda-list
     pattern-ast temp-ast let*-ast)))

;;; Destructure a REQUIRED-SECTION-AST.
(defun destructure-required (section-ast variable-ast let*-ast)
  (unless (null section-ast)
    (loop for ast in (ico:parameter-asts section-ast)
          for name-ast = (ico:name-ast ast)
          do (if (typep name-ast 'ico:variable-name-ast)
                 (progn
                   (add-binding-asts
                    name-ast
                    (aif (application 'null variable-ast)
                         (not-enough-arguments-ast)
                         (application 'first variable-ast))
                    let*-ast)
                   (add-binding-asts
                    variable-ast
                    (application 'rest variable-ast)
                    let*-ast))
                 (destructure-pattern name-ast variable-ast let*-ast)))))

;;; FIXME: handle situation when the variable is a pattern.
;;; Destructure an OPTIONAL-SECTION-AST.
(defun destructure-optional (section-ast variable-ast let*-ast)
  (unless (null section-ast)
    (loop for ast in (ico:parameter-asts section-ast)
          for name-ast = (ico:name-ast ast)
          for init-form-ast = (ico:init-form-ast ast)
          for supplied-p-parameter-ast = (ico:supplied-p-parameter-ast ast)
          do (unless (null supplied-p-parameter-ast)
               (add-binding-asts
                supplied-p-parameter-ast
                (application 'not (application 'null variable-ast))
                let*-ast))
             (add-binding-asts
              name-ast
              (aif (application 'null variable-ast)
                   init-form-ast
                   (application 'first variable-ast))
              let*-ast)
             (add-binding-asts
              variable-ast
              (aif (application 'null variable-ast)
                   variable-ast
                   (application 'rest variable-ast))
              let*-ast))))

  (let ((bindings '()))
    (loop for (var default supplied-p) in optional
          do (unless (null supplied-p)
               (push `(,supplied-p (not (null ,variable)))
                     bindings))
             (push `(,var (if (null ,variable)
                              ,default
                              (first ,variable)))
                   bindings)
             (push `(,variable (if (null ,variable)
                                   ,variable
                                   (rest ,variable)))
                   bindings))
    bindings))

;;; Destructure a &REST or &BODY parameter which can be a variable or
;;; a pattern.  Return a list of bindings and a list of variables to
;;; ignore.
(defun destructure-rest/body
    (pattern variable invoking-form-variable)
  (let ((bindings '())
        (ignored-variables '()))
    (if (symbolp pattern)
        (push `(,pattern ,variable) bindings)
        (let ((temp (gensym)))
          (push `(,temp ,variable)
                bindings)
          (multiple-value-bind (nested-bindings nested-ignored-variables)
              (destructure-lambda-list pattern temp invoking-form-variable)
            (setf bindings
                  (append nested-bindings bindings))
            (setf ignored-variables
                  (append nested-ignored-variables ignored-variables)))))
    (values bindings ignored-variables)))

;;; Destructure a list of &KEY parameters.  Return a list of bindings
;;; and a list of variables to ignore.
(defun destructure-key
    (key variable canonicalized-lambda-list invoking-form-variable allow-other-keys)
  (let* ((bindings '())
         (ignored-variables '())
         (keywords (mapcar #'caar key))
         (odd-number-of-keyword-arguments-form
           `(error 'odd-number-of-keyword-arguments
                   :lambda-list
                   ',(reduce #'append canonicalized-lambda-list)
                   :invoking-form ,invoking-form-variable))
         (check-keywords-form
           (let ((temp (gensym)))
             `(let ((,temp ,variable))
                (tagbody
                 again
                   (if (null ,temp) (go out))
                   (if (not (member (first ,temp)
                                    '(:allow-other-keys ,@keywords)
                                    :test #'eq))
                       (error 'invalid-keyword
                              :keyword (first ,temp)
                              :lambda-list
                              ',(reduce #'append canonicalized-lambda-list)
                              :invoking-form ,invoking-form-variable)
                       (progn (setf ,temp (cddr ,temp))
                              (go again)))
                 out)))))
    (let ((ignored (gensym)))
      (push ignored ignored-variables)
      (push `(,ignored (if (oddp (length ,variable))
                           ,odd-number-of-keyword-arguments-form))
            bindings))
    (unless allow-other-keys
      (let ((ignored (gensym)))
        (push ignored ignored-variables)
        (push `(,ignored (if (not (getf ,variable :allow-other-keys))
                             ,check-keywords-form))
              bindings)))
    (loop for ((keyword var) default supplied-p) in key
          for temp1 = (gensym)
          for temp2 = (gensym)
          do (push `(,temp1 (list nil)) bindings)
             (push `(,temp2 (getf ,variable ,keyword ,temp1))
                   bindings)
             (if (null supplied-p)
                 nil
                 (push `(,supplied-p (not (eq ,temp2 ,temp1)))
                       bindings))
             (push `(,var (if (eq ,temp2 ,temp1)
                              ,default
                              ,temp2))
                   bindings))
    (values bindings ignored-variables)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; DESTRUCTURE-LAMBDA-LIST

(defun destructure-lambda-list (lambda-list-ast variable-ast let*-ast)
  ;; Destructure required parameters.
  (let ((section-ast (ico:required-section-ast lambda-list-ast)))
    (destructure-required section-asts variable-ast let*-ast))
  (let ((section-ast (ico:optional-section-ast lambda-list-ast)))
    (destructure-optional section-asts variable-ast let*-ast))
    (unless (or (member '&rest remaining :key #'first :test #'eq)
                (member '&body remaining :key #'first :test #'eq)
                (member '&key remaining :key #'first :test #'eq))
      (let ((temp (gensym)))
        (push temp ignored-variables)
        (push `(,temp (if (not (null ,variable))
                          (error 'too-many-arguments
                                 :lambda-list
                                 ',(reduce #'append canonicalized-lambda-list)
                                 :invoking-form ,invoking-form-variable)))
              bindings)))
    (when (or (first-group-is remaining '&rest)
              (first-group-is remaining '&body))
      (multiple-value-bind (nested-bindings nested-ignored-variables)
          (destructure-rest/body
           (second (pop remaining)) variable invoking-form-variable)
        (setf bindings
              (append nested-bindings bindings))
        (setf ignored-variables
              (append nested-ignored-variables ignored-variables))))
    (when (first-group-is remaining '&key)
      (let* ((group (pop remaining))
             (allow-other-keys
               (if (first-group-is remaining '&allow-other-keys)
                   (progn (pop remaining) t)
                   nil)))
        (multiple-value-bind (nested-bindings nested-ignored-variables)
            (destructure-key
             (rest group)
             variable
             canonicalized-lambda-list
             invoking-form-variable
             allow-other-keys)
          (setf bindings
                (append nested-bindings bindings))
          (setf ignored-variables
                (append nested-ignored-variables ignored-variables)))))
    (when (first-group-is remaining '&aux)
      (setf bindings
            (append (reverse (rest (pop remaining))) bindings)))
    (values bindings ignored-variables)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; PARSE-MACRO
;;;
;;; According to CLtL2.

(defun parse-macro (name lambda-list body &optional environment)
  (declare (ignore environment)) ; For now.
  (let* ((canonicalized-lambda-list
           (canonicalize-macro-lambda-list lambda-list))
         (environment-group
           (extract-named-group canonicalized-lambda-list '&environment))
         (environment-parameter
           (if (null environment-group) (gensym) (second environment-group)))
         (whole-group
           (extract-named-group canonicalized-lambda-list '&whole))
         (whole-parameter
           (if (null whole-group) (gensym) (second whole-group)))
         (remaining
           (remove '&environment
                   (remove '&whole canonicalized-lambda-list
                           :key #'first :test #'eq)
                   :key #'first :test #'eq))
         (args-var (gensym)))
    (multiple-value-bind (declarations documentation forms)
        (separate-function-body body)
      (multiple-value-bind (bindings ignored-variables)
          (destructure-lambda-list remaining args-var whole-parameter)
        `(lambda (,whole-parameter ,environment-parameter)
           ,@(if (null documentation) '() (list documentation))
           ;; If the lambda list does not contain &environment, then
           ;; we IGNORE the GENSYMed parameter to avoid warnings.
           ;; If the lambda list does contain &environment, we do
           ;; not want to make it IGNORABLE because we would want a
           ;; warning if it is not used then.
           ,@(if (null environment-group)
                 `((declare (ignore ,environment-parameter)))
                 `())
           (block ,name
             (let ((,args-var (rest ,whole-parameter)))
               (let* ,(reverse bindings)
                 (declare (ignore ,@ignored-variables))
                 ,@declarations
                 ,@forms))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; PARSE-COMPILER-MACRO
;;;
;;; This function differs from parse-macro only in the code that
;;; destructures the lambda list from the arguments.

(defun parse-compiler-macro (name lambda-list body &optional environment)
  (declare (ignore name environment)) ; For now.
  (let* ((canonicalized-lambda-list
           (canonicalize-macro-lambda-list lambda-list))
         (environment-group
           (extract-named-group canonicalized-lambda-list '&environment))
         (environment-parameter
           (if (null environment-group) (gensym) (second environment-group)))
         (whole-group
           (extract-named-group canonicalized-lambda-list '&whole))
         (whole-parameter
           (if (null whole-group) (gensym) (second whole-group)))
         (remaining
           (remove '&environment
                   (remove '&whole canonicalized-lambda-list
                           :key #'first :test #'eq)
                   :key #'first :test #'eq))
         (args-var (gensym)))
    (multiple-value-bind (declarations documentation forms)
        (separate-function-body body)
      (multiple-value-bind (bindings ignored-variables)
          (destructure-lambda-list remaining args-var whole-parameter)
        `(lambda (,whole-parameter ,environment-parameter)
           ,@(if (null documentation) '() (list documentation))
           ;; If the lambda list does not contain &environment, then
           ;; we IGNORE the GENSYMed parameter to avoid warnings.
           ;; If the lambda list does contain &environment, we do
           ;; not want to make it IGNORABLE because we would want a
           ;; warning if it is not used then.
           ,@(if (null environment-group)
                 `((declare (ignore ,environment-parameter)))
                 `())
           (let ((,args-var (if (and (eq (car ,whole-parameter) 'funcall)
                                   (consp (cdr ,whole-parameter))
                                   (consp (cadr ,whole-parameter))
                                   (eq (car (cadr ,whole-parameter)) 'function))
                              (cddr ,whole-parameter)
                              (cdr ,whole-parameter))))
             (let* ,(reverse bindings)
               (declare (ignore ,@ignored-variables))
               ,@declarations
               ,@forms)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; PARSE-DEFTYPE

(defun parse-deftype (name lambda-list body)
  (declare (ignore name))
  (let* ((canonicalized-lambda-list
           (canonicalize-deftype-lambda-list lambda-list))
         (environment-group
           (extract-named-group canonicalized-lambda-list '&environment))
         (environment-parameter
           (if (null environment-group) (gensym) (second environment-group)))
         (whole-group
           (extract-named-group canonicalized-lambda-list '&whole))
         (whole-parameter
           (if (null whole-group) (gensym) (second whole-group)))
         (remaining
           (remove '&environment
                   (remove '&whole canonicalized-lambda-list
                           :key #'first :test #'eq)
                   :key #'first :test #'eq))
         (args-var (gensym)))
    (multiple-value-bind (declarations documentation forms)
        (separate-function-body body)
      (multiple-value-bind (bindings ignored-variables)
          (destructure-lambda-list remaining args-var whole-parameter)
        `(lambda (,whole-parameter ,environment-parameter)
           ,@(if (null documentation) '() (list documentation))
           ;; If the lambda list does not contain &environment, then
           ;; we IGNORE the GENSYMed parameter to avoid warnings.
           ;; If the lambda list does contain &environment, we do
           ;; not want to make it IGNORABLE because we would want a
           ;; warning if it is not used then.
           ,@(if (null environment-group)
                 `((declare (ignore ,environment-parameter)))
                 `())
           (let ((,args-var (rest ,whole-parameter)))
             (let* ,(reverse bindings)
               (declare (ignore ,@ignored-variables))
               ,@declarations
               ,@forms)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; PARSE-DESTRUCTURING-BIND

(defun parse-destructuring-bind (lambda-list form body)
  (let* ((canonicalized-lambda-list
           (canonicalize-destructuring-lambda-list lambda-list))
         (whole-group
           (extract-named-group canonicalized-lambda-list '&whole))
         (whole-parameter
           (if (null whole-group) (gensym) (second whole-group)))
         (remaining
           (remove '&whole canonicalized-lambda-list
                   :key #'first :test #'eq))
         (args-var (gensym)))
    (multiple-value-bind (declarations forms)
        (separate-ordinary-body body)
      (multiple-value-bind (bindings ignored-variables)
          (destructure-lambda-list remaining args-var whole-parameter)
        `(let* ((,whole-parameter ,form)
                (,args-var ,whole-parameter)
                ,@(reverse bindings))
           (declare (ignore ,@ignored-variables))
           ,@declarations
           ,@forms)))))
