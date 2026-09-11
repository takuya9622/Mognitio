;; The first form only refers to packages available before ASDF is loaded.
(let ((stdout *standard-output*) (stderr *error-output*))
  (handler-case
      (progn
        (let* ((capture (make-string-output-stream))
               (*standard-output* capture) (*error-output* capture)
               (*trace-output* capture) (*compile-verbose* nil)
               (*compile-print* nil) (*load-verbose* nil) (*load-print* nil))
          (require :asdf)
          (let* ((entry (truename *load-truename*))
                 (root (merge-pathnames "../" (make-pathname :name nil :type nil
                                                              :defaults entry)))
                 (asd (truename (merge-pathnames "mognitio.asd" root))))
            (funcall (find-symbol "LOAD-ASD" "ASDF") asd)
            (funcall (find-symbol "LOAD-SYSTEM" "ASDF") "mognitio")))
        (let ((*standard-output* stdout) (*error-output* stderr))
          (funcall (find-symbol "MAIN" "MOGNITIO.CLI"))))
    (error ()
      (ignore-errors
        (write-line "mgn: internal: Compiler bootstrap failed" stderr)
        (finish-output stderr))
      (sb-ext:exit :code 3))))
