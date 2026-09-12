(asdf:defsystem "mognitio"
  :description "Mognitio boolean compiler"
  :version "0.2.0"
  :depends-on ("sb-posix")
  :serial t
  :components ((:file "src/packages")
               (:file "src/diagnostics")
               (:file "src/source")
               (:file "src/syntax")
               (:file "src/lexer")
               (:file "src/parser")
               (:file "src/semantic")
               (:file "src/backend-common-lisp")
               (:file "src/target")
               (:file "src/ir")
               (:file "src/machine-ir")
               (:file "src/amd64")
               (:file "src/elf")
               (:file "src/backend-native")
               (:file "src/artifact")
               (:file "src/driver")
               (:file "src/cli"))
  :in-order-to ((asdf:test-op (asdf:test-op "mognitio/tests"))))

(asdf:defsystem "mognitio/tests"
  :depends-on ("mognitio")
  :serial t
  :components ((:file "tests/harness")
               (:file "tests/source-frontend")
               (:file "tests/semantic-backend")
               (:file "tests/driver-process")
               (:file "tests/generated")
               (:file "tests/native-ir")
               (:file "tests/native-process")
               (:file "tests/native-generated"))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :mognitio.tests :run-tests)))
