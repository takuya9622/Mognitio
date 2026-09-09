(in-package #:mognitio.cli)
(defun main ()
  (sb-ext:exit :code (mognitio.driver:run-cli
                      (uiop:command-line-arguments)
                      *standard-output* *error-output*)))
