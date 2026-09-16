(in-package #:mognitio.object)

;; These records describe only the in-memory image owned by this compiler.
(defstruct code-unit owner instructions entry)
(defstruct image-symbol name kind offset)
(defstruct fixup offset end target (kind :pc-rel32) use)

(defun symbol-kind (name)
  (cond
    ((keywordp name) :code)
    ((and (listp name)
          (case (first name)
            (:function (and (= 2 (length name)) (typep (second name) '(integer 0 *))))
            ((:block :internal)
             (and (member (length name) '(2 3))
                  (every (lambda (id) (typep id '(integer 0 *))) (rest name))))))
     (if (eq (first name) :function) :function :code))
    ((and (listp name) (= 2 (length name)) (eq (first name) :data)
          (member (second name) '(:true :false :overflow :division-by-zero :remainder-by-zero))) :data)
    (t (internal-error "Invalid image symbol"))))

(defun layout-units (units)
  (loop for unit in units append (code-unit-instructions unit)))
