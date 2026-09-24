(in-package #:mognitio.tests)

(defun v06-raw-result (forms &optional options)
  (let ((mognitio.native.runtime::*test-options* options))
    (v05-cross-abi "let x: string=\"a\"+\"b\"; true" 0
      (append (v06-raw-frame) forms
        '((:mov-reg :rsp :rbp) (:pop-rbp) (:ret))))))

(deftest v06-native-size-boundaries
  (multiple-value-bind (out err code)
      (v06-raw-result
        '((:imm-rax 9223372036854775806) (:store-out 0 :rax)
          (:imm-rax 1) (:store-out 8 :rax) (:call (:runtime :sum))
          (:imm-rcx 9223372036854775807) (:cmp) (:set-bool :eq)))
    (same 0 code) (same (format nil "true~%") out) (same "" err))
  ;; Physical size calculation has unsigned overflow and alignment boundaries,
  ;; independent of source lengths and without requesting enormous mappings.
  (dolist (pair '((0 32) (1 40) (8 40) (9 48) (9223372036854775807 -9223372036854775776)))
    (multiple-value-bind (out err code)
        (v06-raw-result
          `((:imm-rax ,(first pair)) (:store-out 0 :rax) (:call (:runtime :physical-size))
            (:imm-rcx ,(second pair)) (:cmp) (:set-bool :eq)))
      (same 0 code) (same (format nil "true~%") out) (same "" err)))
  (dolist (n '(-1 -32 -38))
    (multiple-value-bind (out err code)
        (v06-raw-result `((:imm-rax ,n) (:store-out 0 :rax) (:call (:runtime :physical-size))
                         (:jmp :division-by-zero)))
      (same 4 code) (same "" out) (same (format nil "runtime: allocation_failed~%") err)))
  ;; Both input objects are stack metadata; each path must fail before payload
  ;; reads, collection, or allocation. Test byte and scalar checks independently.
  (dolist (field '(16 24))
    (let ((forms
            (append
              (loop for base in '(-64 -32) append
                `((:lea-base :r8 :rbp ,base) (:imm-rax 32) (:store-word :r8 0 :rax)
                  (:imm-rax 5) (:store-word :r8 8 :rax)
                  (:imm-rax 1) (:store-word :r8 16 :rax) (:store-word :r8 24 :rax)))
              `((:lea-base :r8 :rbp -64) (:imm-rax 9223372036854775807)
                (:store-word :r8 ,field :rax) (:store-out 0 :r8)
                (:lea-base :r9 :rbp -32) (:store-out 8 :r9)
                (:call (:helper :text.concat)) (:jmp :division-by-zero)))))
      (multiple-value-bind (out err code) (v06-raw-result forms '(:mmap-fail t))
        (same 4 code) (same "" out) (same (format nil "runtime: string_size_overflow~%") err))))
  (multiple-value-bind (out err code)
      (process-result
        (list (namestring (v06-runtime-artifact "\"a\"->slice(-1,0)==\"\"" '(:mmap-fail t)))))
    (same 4 code) (same "" out) (same (format nil "runtime: string_index_out_of_bounds~%") err)))

(deftest v06-native-invalid-root-pointers
  (dolist (kind '(:interior :free :outside))
    (let* ((forms (append (v06-raw-allocate 1)
                   (case kind
                     (:interior '((:add-imm :rax 8)))
                     (:free '((:store-frame -8 :rax) (:call (:runtime :collect)) (:load-frame :rax -8)))
                     (:outside '((:lea-base :rax :rbp -64))))
                   '((:store-frame -32 :rax) (:call (:runtime :collect)) (:imm-rax 1)))))
      (multiple-value-bind (out err code) (v06-raw-result forms '(:validate t))
        (same 3 code) (same "" out) (same "" err)))))

(deftest v06-native-interior-root-static-bit
  (multiple-value-bind (out err code)
      (v06-raw-result
        (append (v06-raw-allocate 4)
                '((:add-imm :rax 8) (:store-frame -32 :rax)
                  (:call (:runtime :collect)) (:imm-rax 1)))
        '(:validate t))
    (same 3 code) (same "" out) (same "" err)))

(deftest v06-native-root-address-classification
  ;; Known empty and nonempty literal starts are accepted without writing RX
  ;; storage. Zero slots and duplicate dynamic roots survive repeated marking.
  (multiple-value-bind (out err code)
      (v06-raw-result
        (append
          (loop for id below 3 append
            `((:lea-text (:text ,id)) (:store-frame -32 :rax) (:call (:runtime :collect))))
          (v06-raw-allocate 4)
          '((:store-frame -32 :rax) (:store-frame -24 :rax)
            (:call (:runtime :collect)) (:load-frame :rax -32)
            (:load-word :rax :rax 8) (:cmp-imm :rax 1) (:set-bool :eq)))
        '(:validate t))
    (same 0 code) (same (format nil "true~%") out) (same "" err))
  (dolist (kind '(:literal-interior :unmapped :fake-static :free-interior :heap-static))
    (multiple-value-bind (out err code)
        (v06-raw-result
          (append
            (case kind
              (:literal-interior '((:lea-text (:text 1)) (:add-imm :rax 8)))
              (:unmapped '((:imm-rax 1)))
              (:fake-static '((:lea-base :rax :rbp -64) (:imm-rcx 5) (:store-word :rax 8 :rcx)))
              (:free-interior
               (append (v06-raw-allocate 4)
                       '((:store-frame -8 :rax) (:call (:runtime :collect))
                         (:load-frame :rax -8) (:add-imm :rax 8))))
              (:heap-static
               (append (v06-raw-allocate 4) '((:imm-rcx 5) (:store-word :rax 8 :rcx)))))
            '((:store-frame -32 :rax) (:call (:runtime :collect)) (:imm-rax 1)))
          '(:validate t))
      (same 3 code) (same "" out) (same "" err))))
