(cl:in-package #:common-macros)

;;; Macro DOTIMES.
;;;
;;; The spec says we have a choice between binding or assigning the
;;; variable in each iteration.  We have chosen to bind the variable
;;; once for the entire loop body.

(defmacro cmd:dotimes ((var count-form &optional result-form) &body body)
  (multiple-value-bind (declarations forms)
      (separate-ordinary-body body)
    (let ((start-tag (gensym))
          (end-tag (gensym))
          (count-var (gensym)))
      `(let ((,count-var ,count-form)
             (,var 0))
         (declare (type unsigned-byte ,var))
         ,@declarations
         (block nil
           (tagbody
              ,start-tag
              (when (= ,var ,count-var)
                (go ,end-tag))
              (tagbody ,@forms)
              (incf ,var)
              (go ,start-tag)
              ,end-tag)
           ,result-form)))))
