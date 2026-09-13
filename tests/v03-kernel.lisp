(in-package #:mognitio.tests)

(defun v03-positive (source expected &optional cli)
  (same expected (compiled-result source))
  (expect-artifact (build-text source) expected)
  (when cli (expect-source source expected)))

(defun v03-reject (source phase)
  (let ((path (put-text (fresh-path) source)) (output (fresh-path ".elf")))
    (dolist (existing '(nil t))
      (when existing (put-text output "previous artifact"))
      (dolist (args (list (list "run" (namestring path)) (build-args path output)))
        (multiple-value-bind (out err code) (driver-result args)
          (same 1 code) (same "" out)
          (is (search (format nil ": ~A:" phase) err))))
      (if existing (same "previous artifact" (uiop:read-file-string output))
          (is (not (probe-file output)))))))

(defun v03-runtime (source diagnostic &optional cli)
  (let ((path (put-text (fresh-path) source))
        (expected (format nil "runtime: ~A~%" diagnostic))
        (artifact (build-text source)))
    (multiple-value-bind (out err code) (driver-result (list "run" (namestring path)))
      (same 4 code) (same "" out) (same expected err))
    (multiple-value-bind (out err code) (process-result (list (namestring artifact)))
      (same 4 code) (same "" out) (same expected err))
    (when cli
      (multiple-value-bind (out err code) (cli-result (list "run" (namestring path)))
        (same 4 code) (same "" out) (same expected err)))
    artifact))

(deftest v03-positive-kernel
  (dolist (text
            '("(true)" "let unitPrice = 120; var count = 2; count = count + 1; count * unitPrice == 360"
              "let a = 1 + 2 * 3; let b = (1 + 2) * 3; if (a == 7) { b == 9 } else { false }"
              "10 - 3 - 2 == 5" "24 / 4 / 2 == 3" "--1 == 1" "010 == 10" "000 == 0"
              "-9223372036854775808 < 9223372036854775807"
              "- 09223372036854775808 == (-9223372036854775808)"
              "7 / 3 == 2" "-7 / 3 == -2" "7 / -3 == -2" "-7 / -3 == 2"
              "-7 % 3 == -1" "7 % -3 == 1" "-7 % -3 == -1" "0 % 3 == 0"
              "1 < 2 == true" "(1 < 2) == (3 < 4)" "true != false" "1 != 2"
              "let n = if (false) { 1 } else { 2 }; n == 2"
              "let chosen = if (true) { let result = 1; result } else { let result = 2; result }; chosen == 1"
              "var n = 0; let ok = if (true) { n = 2; true } else { n = 9; false }; if (ok) { n == 2 } else { false }"
              "var value = 1; let sum = (if (true) { value = 2; value } else { 0 }) + value; sum == 4"
              "var value = 1; let sum = value + (if (true) { value = 2; value } else { 0 }); sum == 3"
              "var value = 8; let n = value / (if (true) { value = 2; value } else { 1 }); n == 4"
              "var value = 8; let n = value - (if (true) { value = 2; value } else { 1 }); n == 6"
              "if (false) { 1 / 0 } else { 1 } == 1"
              "if (true) { 1 } else { 1 % 0 } == 1"
              "let x = 1; let y = if (true) { var localX = 2; localX = 3; localX } else { 0 }; if (y == 3) { x == 1 } else { false }"
              "var ok = false; ok = true; ok"
              "let true1 = 1; let Let = 2; let int = 3; let _a2 = 4; true1 + Let + int + _a2 == 10"
              "let x = 1; let X = 2; x + X == 3"
              "let first = if (true) { let item = 1; item } else { 0 }; let item = 2; if (first == 1) { item == 2 } else { false }"
              "var a = 1; var b = 2; let x = if (true) { a = 3; b = 4; a + b } else { b = 9; 0 }; if (x == 7) { a * b == 12 } else { false }"
              "var a = 1; let x = if (if (true) { a = 5; true } else { false }) { a } else { 0 }; x == 5"
              "var a = 1; let x = if (false) { a = 9; 0 } else { if (true) { a = 2; a } else { 1 } }; if (x == 2) { a == 2 } else { false }"))
    (v03-positive text :true))
  (dolist (text '("1 > 2" "1 >= 2" "2 < 1" "2 <= 1" "1 == 2" "true == false" "false != false"))
    (v03-positive text :false))
  (dolist (text '("1 <= 1" "1 >= 1" "-1 < 0" "0 > -1" "-1 == -1"))
    (v03-positive text :true))
  (v03-positive "let result = (2 + 3) * 4; result == 20" :true t))

(deftest v03-rejection-kernel
  (dolist (text '("12abc" "1_000" "$" "$name" "0x10" "let 日本 = 1; true"))
    (v03-reject text "lex"))
  (dolist (text '("let x;" "var x = ; true" "let x = 1 true" "true;" ";true"
                  "let int x = 1; true" "let true = 1; true" "x = y = 1; true"
                  "let x = 1; (x = 2) == 2" "1 < 2 < 3" "true == false == true"
                  "true === true" "1 += 2" "if(true){}else{false}" "if(true){true}else if(false){true}else{false}"))
    (v03-reject text "parse"))
  (dolist (text '("let x = x; true" "true1" "truefalse" "x = 1; true"
                  "let y = x; let x = 1; true" "let x = 1; let x = 2; true"
                  "let x = 1; x = 2; true" "var x = 1; x = true; true"
                  "1 + true == 2" "1 == true" "true < false" "if(1){true}else{false}"
                  "if(true){1}else{false}" "42" "1 < (2 < 3)"
                  "9223372036854775808 == 0" "-9223372036854775809 == 0"
                  "-(9223372036854775808) == 0"
                  "if(false){9223372036854775808}else{0} == 0"
                  "let y = if(true){let x = 1; x}else{0}; x == 1"
                  "let y = if(true){let x = 1; x}else{x}; y == 1"
                  "var x = if(true){x = 1; 1}else{0}; true"
                  "let x = if(if(true){let x = 1; true}else{false}){1}else{0}; true"
                  "let a = if(true){let b = if(true){let a = 1; a}else{0}; b}else{0}; true"
                  "let x = 1; let y = if(false){let z = if(true){var x = false; 0}else{0};z}else{0};true"))
    (v03-reject text "semantic"))
  (dolist (outer '("let" "var"))
    (dolist (inner '("let" "var"))
      (dolist (condition '("true" "false"))
        (v03-reject (format nil "~A x = 1; let y = if(~A){~A x = false; 1}else{0};true"
                            outer condition inner) "semantic")
        (v03-reject (format nil "~A x = if(~A){~A x = 1; x}else{0};true"
                            outer condition inner) "semantic"))))
  (v03-reject (format nil "~A == 0" (make-string 10000 :initial-element #\9)) "semantic")
  (v03-positive (format nil "~A1 == 1" (make-string 10000 :initial-element #\0)) :true))

(deftest v03-runtime-arithmetic
  (dolist (expr '("9223372036854775807 + 1" "-9223372036854775808 - 1"
                  "9223372036854775807 * 2" "--9223372036854775808"
                  "-9223372036854775808 / -1" "-9223372036854775808 % -1"
                  "(9223372036854775807 + 1) - 1"))
    (v03-runtime (format nil "~A == 0" expr) "integer overflow")
    (v03-positive (format nil "if(false){~A}else{0} == 0" expr) :true))
  (dolist (expr '("1 / 0" "0 / 0" "1 / 0 + 1 % 0"))
    (v03-runtime (format nil "~A == 0" expr) "division by zero" t))
  (v03-runtime "1 % 0 == 0" "remainder by zero" t)
  (v03-runtime "var n = -9223372036854775808; -n == 0" "integer overflow" t)
  (v03-runtime "var n = 0; 1 / n == 0" "division by zero")
  (v03-runtime "var n = 0; 1 % n == 0" "remainder by zero")
  (v03-runtime "let unused = 1 / 0; true" "division by zero")
  (v03-runtime "var n = 1; n = 1 % 0; true" "remainder by zero")
  (v03-runtime "if(true){let n = 1 / 0; false}else{true}" "division by zero")
  (let ((checked (check-program (parse-text "1 / 0 == 0"))))
    (replacing (mognitio.backend.cl::host-compile
                (lambda (form) (declare (ignore form)) (mognitio.runtime:runtime-error :overflow)))
      (signals internal-failure (compile-program checked)))))

(deftest v03-integer-machine-goldens
  (dolist (pair '(((:imm-rax -9223372036854775808) "48b80000000000000080")
                  ((:imm-rcx 9223372036854775807) "48b9ffffffffffffff7f")
                  ((:imm-rdx -1) "48baffffffffffffffff")
                  ((:load-rax 0) "488b842400000000") ((:load-rcx 256) "488b8c2400010000")
                  ((:store-rax 8) "4889842408000000") ((:push-zero) "6a00")
                  ((:dec-rcx) "48ffc9") ((:test-rcx) "4885c9") ((:neg) "48f7d8")
                  ((:add) "4801c8") ((:sub) "4829c8") ((:mul) "480fafc1")
                  ((:cmp) "4839c8") ((:cqo) "4899") ((:idiv) "48f7f9")
                  ((:cmp-rcx-minus-one) "4883f9ff") ((:cmp-rax-rdx) "4839d0")
                  ((:mov-rax-rdx) "4889d0") ((:set-bool :lt) "0f9cc00fb6c0")
                  ((:set-bool :ge) "0f9dc00fb6c0") ((:mov-r10d 16) "41ba10000000")
                  ((:dec-r10d) "41ffca") ((:mov-edi-r8d) "4489c7") ((:mov-edi-r9d) "4489cf")))
    (same (hex-bytes (second pair)) (mognitio.amd64:encode (machine (first pair)))))
  (same (hex-bytes "0f8000000000")
        (mognitio.amd64:encode (machine '(:jo :end) '(:label :end))))
  (dolist (form '((:imm-rax 9223372036854775808) (:load-rax -8) (:store-rax 1)
                  (:load-rcx 2147483648) (:set-bool :unsigned) (:idiv 1)))
    (signals internal-failure (mognitio.amd64:encode (machine form))))
  (let* ((ir (native-ir "var x = 1; let y = if(true){x = 2; 3}else{4}; x + y == 5"))
         (join (find-if (lambda (b) (= 2 (length (mognitio.ir:basic-block-parameters b))))
                        (mognitio.ir:module-blocks ir))))
    (is join)
    (let* ((edge (find-if (lambda (b) (eq :jump (first (mognitio.ir:basic-block-terminator b))))
                          (mognitio.ir:module-blocks ir)))
           (old (mognitio.ir:basic-block-terminator edge)))
      (setf (mognitio.ir:basic-block-terminator edge) (list :jump (second old) nil))
      (signals internal-failure (mognitio.ir:verify-module ir))))
  (let* ((ir (native-ir "1 + 2 == 3"))
         (inst (find :add (mognitio.ir:basic-block-instructions (first (mognitio.ir:module-blocks ir)))
                     :key #'mognitio.ir:instruction-op)))
    (is inst)
    (setf (mognitio.ir:instruction-operands inst) '(999 0))
    (signals internal-failure (mognitio.ir:verify-module ir)))
  ;; A frame larger than a page still touches all homes and preserves old values.
  (let ((text (with-output-to-string (out)
                (dotimes (i 600) (format out "let x~D = ~D; " i i))
                (write-string "x0 + x599 == 599" out))))
    (v03-positive text :true)))

(deftest v03-runtime-output-faults
  (let ((artifact (build-text "1 / 0 == 0")) (source (put-text (fresh-path) "1 / 0 == 0")))
    (dolist (mode '("partial-eintr" "zero" "error" "eintr-budget"))
      (multiple-value-bind (out err code)
          (process-result (list "python3" (namestring (root-path "tests/runtime-syscalls.py"))
                                (namestring artifact) mode "runtime"))
        (same 4 code) (same "" out)
        (same (if (string= mode "partial-eintr") (format nil "runtime: division by zero~%") "") err)))
    (dolist (argv (list (list (namestring artifact))
                        (list (namestring (root-path "bin/mgn")) "run" (namestring source))))
      (dolist (redirection '("2>/dev/full" "2>&-"))
        (multiple-value-bind (out err code)
            (process-result (append (list "/bin/sh" "-c" (format nil "exec \"$@\" ~A" redirection) "test") argv))
          (same 4 code) (same "" out) (same "" err)))))
  (dolist (results '((-4 2 -4 3 1000) (0) (-5) (-4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4 -4)))
    (let ((remaining results) (offsets nil) (lengths nil))
      (with-open-file (stream (fresh-path ".stderr") :direction :output)
        (replacing (mognitio.runtime::write-chunk
                    (lambda (fd bytes offset count)
                      (declare (ignore fd bytes))
                      (push offset offsets) (push count lengths)
                      (let ((result (pop remaining)))
                        (unless result (error "Unexpected extra write"))
                        (if (plusp result) (min count result) result))))
          (same 4 (mognitio.runtime:write-runtime-failure
                    (make-condition 'mognitio.runtime:integer-runtime-failure :kind :overflow) stream))))
      (same nil remaining)
      (when (= (length results) 5)
        (same '(0 0 2 2 5) (reverse offsets))
        (same '(26 26 24 24 21) (reverse lengths))))))
