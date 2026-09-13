(in-package #:mognitio.runtime)

(defconstant +retry-budget+ 16)
(defparameter *failure-data*
  '((:overflow "runtime: integer overflow")
    (:division-by-zero "runtime: division by zero")
    (:remainder-by-zero "runtime: remainder by zero")))
(define-condition integer-runtime-failure (error)
  ((kind :initarg :kind :reader failure-kind)))
(defun failure-octets (kind)
  (let ((entry (assoc kind *failure-data*)))
    (unless entry (mognitio.diagnostics:internal-error "Unknown runtime failure"))
    (sb-ext:string-to-octets (format nil "~A~%" (second entry)) :external-format :utf-8)))
(defun runtime-error (kind) (error 'integer-runtime-failure :kind kind))
(defun failure-status (kind) (failure-octets kind) 4)

(defun write-chunk (fd bytes offset count)
  (sb-sys:with-pinned-objects (bytes)
    (handler-case
        (sb-posix:write fd (sb-sys:sap+ (sb-sys:vector-sap bytes) offset) count)
      (sb-posix:syscall-error (c) (- (sb-posix:syscall-errno c))))))

(defun write-runtime-failure (condition stream)
  ;; Reporting cannot replace the original failure, or restart source evaluation.
  (let ((bytes (failure-octets (failure-kind condition))))
    (handler-case
        (if (typep stream 'sb-sys:fd-stream)
            (let ((offset 0) (retries 0) (fd (sb-sys:fd-stream-fd stream)))
              (loop while (< offset (length bytes)) do
                (let ((count (write-chunk fd bytes offset (- (length bytes) offset))))
                  (cond ((= count (- sb-posix:eintr))
                         (when (>= (incf retries) +retry-budget+) (return)))
                        ((plusp count) (incf offset count) (setf retries 0))
                        (t (return))))))
            ;; In-memory adapters preserve the driver test interface.
            (progn (write-string (sb-ext:octets-to-string bytes :external-format :utf-8) stream)
                   (finish-output stream)))
      (error () nil)))
  (failure-status (failure-kind condition)))
