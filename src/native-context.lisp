(in-package #:mognitio.native.runtime)

(defconstant +root-head+ 0)
(defconstant +arena-head+ 8)
(defconstant +page-size+ 16)
(defconstant +context-size+ 32)

(defun entry-forms ()
  ;; Read the initial stack before reserving fresh, aligned context storage.
  (append
   '((:mov-reg :rdx :rsp) (:align-stack) (:clear-frame) (:add-imm :rdx 8)
     (:label :skip-argv) (:load-word :rax :rdx 0) (:add-imm :rdx 8) (:test) (:jnz :skip-argv)
     (:label :skip-env) (:load-word :rax :rdx 0) (:add-imm :rdx 8) (:test) (:jnz :skip-env)
     (:label :auxv) (:load-word :rax :rdx 0) (:test) (:jz :bad-auxv)
     (:cmp-imm :rax 6) (:jz :have-pagesize) (:add-imm :rdx 16) (:jmp :auxv)
     (:label :have-pagesize) (:load-word :rax :rdx 8) (:test) (:jle :bad-auxv))
   (loop repeat (/ +context-size+ 8) collect '(:push-zero))
   `((:mov-reg :r15 :rsp) (:store-word :r15 ,+page-size+ :rax)
     (:call (:function 0)) (:jmp :print)
     (:label :bad-auxv) (:mov-edi 3) (:mov-eax 60) (:syscall) (:ud2))))

(defun literal-forms (pool)
  (loop for payload across pool for id from 0 append
    (let* ((bytes (mognitio.syntax:text-payload-octets payload))
           (size (* 8 (ceiling (+ 32 (length bytes)) 8))))
      (append (list '(:align 8) (list :label (list :text id)))
              (list (cons :bytes
                     (append (mognitio.amd64:little-endian size 8)
                             (mognitio.amd64:little-endian 5 8)
                             (mognitio.amd64:little-endian (length bytes) 8)
                             (mognitio.amd64:little-endian (mognitio.syntax:text-payload-scalar-count payload) 8)
                             (coerce bytes 'list) (make-list (- size 32 (length bytes)) :initial-element 0))))))))

(defun text-helper-units (operations)
  ;; The runtime implementation is a separate increment. Tests substitute
  ;; explicit ABI probes here; production must not silently link such stubs.
  (when operations (internal-error "Native text helpers are not implemented yet"))
  nil)
