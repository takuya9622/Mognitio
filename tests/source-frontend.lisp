(in-package #:mognitio.tests)

(deftest v01-v02-booleans-and-branches
  (expect-source "true" :true)
  (expect-source "false" :false)
  (dolist (condition '(:true :false))
    (dolist (then '(:true :false))
      (dolist (else '(:true :false))
        (expect-source
         (format nil "if(~(~A~)){~(~A~)}else{~(~A~)}" condition then else)
         (if (eq condition :true) then else)))))
  (expect-source "if(if(false){true}else{false}){if(true){false}else{true}}else{if(false){false}else{true}}"
                 :true))

(deftest v03-whitespace-and-eof
  (dolist (space (list " " (string #\Tab) (string #\Newline)
                       (string #\Return) (format nil "~C~C" #\Return #\Newline)))
    (let* ((text (format nil "~Aif~A(~Atrue~A)~A{~Afalse~A}~Aelse~A{~Atrue~A}~A"
                         space space space space space space space space
                         space space space space))
           (source (text-source text))
           (tokens (lex-source source)))
      (same '(:if :left-paren :true :right-paren :left-brace :false :right-brace
              :else :left-brace :true :right-brace :eof)
            (map 'list #'token-kind tokens))
      (same (length text) (span-start (token-span (aref tokens 11))))
      (same (length text) (span-end (token-span (aref tokens 11))))
      (expect-source text :false))))

(deftest v04-bom
  (let ((valid (put-bytes (fresh-path) #(239 187 191 116 114 117 101))))
    (expect-cli (list "run" (namestring valid)) 0 :output (format nil "true~%"))
    (let ((source (read-source (namestring valid))))
      (same #(3 4 5 6 7) (source-byte-offsets source))
      (same #(1 1 1 1 1) (source-lines source))
      (same #(1 2 3 4 5) (source-columns source))))
  (dolist (case '((#(239 187 191) "parse")
                  (#(239 187 191 239 187 191) "source")
                  (#(116 114 117 101 239 187 191) "source")))
    (expect-cli (list "run" (namestring (put-bytes (fresh-path) (first case))))
                1 :phase (second case))))

(deftest v05-strict-utf8
  (dolist (bytes '(#(128) #(191) #(192 128) #(193 191) #(194) #(223)
                   #(224) #(224 160) #(224 159 191) #(225 128)
                   #(237 160 128) #(239 187) #(240) #(240 144) #(240 144 128)
                   #(240 143 191 191) #(244 144 128 128) #(245 128 128 128)
                   #(255) #(194 127) #(194 192) #(225 128 127)
                   #(241 128 128 192) #(239)))
    (let ((diag (diagnostic-of (lambda () (decode-source "bytes.mgn" bytes)))))
      (same :source (diagnostic-phase diag))
      (same 1 (diagnostic-line diag))
      (same 1 (diagnostic-column diag)))
    (expect-cli (list "run" (namestring (put-bytes (fresh-path) bytes)))
                1 :phase "source"))
  ;; Entire source is decoded before an earlier invalid token can be lexed.
  (expect-cli (list "run" (namestring (put-bytes (fresh-path) #(59 255))))
              1 :phase "source"))

(deftest v07-location-boundaries
  (dolist (case (list (list (format nil "~C@" #\Tab) 1 2)
                     (list (format nil "true~%@") 2 1)
                     (list (format nil "true~C@" #\Return) 2 1)
                     (list (format nil "true~C~C@" #\Return #\Newline) 2 1)
                     (list (format nil "~C~C~C@" #\Return #\Newline #\Tab) 2 2)))
    (let* ((text (first case)) (source (text-source text))
           (diag (diagnostic-of (lambda () (lex-source source)))))
      (same :lex (diagnostic-phase diag))
      (same (second case) (diagnostic-line diag))
      (same (third case) (diagnostic-column diag))
      (let* ((path (put-text (fresh-path) text))
             (err (expect-cli (list "run" (namestring path)) 1 :phase "lex")))
        (is (search (format nil ":~D:~D: lex:" (second case) (third case)) err)))))
  (let* ((source (text-source (format nil "if(true){false}else{~C~C~C"
                                            #\Return #\Newline #\Tab)))
         (diag (diagnostic-of (lambda () (parse-program source (lex-source source))))))
    (same 2 (diagnostic-line diag)) (same 2 (diagnostic-column diag)))
  (let ((diag (diagnostic-of
               (lambda () (decode-source "bad.mgn" #(239 187 191 13 10 9 226 130 0))))))
    (same 2 (diagnostic-line diag)) (same 2 (diagnostic-column diag)))
  (let ((source (text-source (format nil "~C~C~C" #\Return #\Newline #\Tab))))
    (same #(1 2 2 2) (source-lines source))
    (same #(1 1 1 2) (source-columns source)))
  (let ((diag (diagnostic-of
               (lambda () (lex-source (decode-source "bom.mgn" #(239 187 191 9 64)))))))
    (same 1 (diagnostic-line diag)) (same 2 (diagnostic-column diag))))

(deftest v08-valid-unicode
  (dolist (case '((#(0) 0) (#(127) 127) (#(194 128) 128) (#(223 191) 2047)
                  (#(224 160 128) 2048) (#(237 159 191) 55295)
                  (#(238 128 128) 57344) (#(239 191 191) 65535)
                  (#(240 144 128 128) 65536) (#(244 143 191 191) 1114111)
                  (#(194 160) 160) (#(230 151 165) 26085)))
    (let ((source (decode-source "unicode.mgn" (first case))))
      (same (second case) (char-code (char (source-text source) 0)))
      (same (list 0 (length (first case))) (coerce (source-byte-offsets source) 'list))
      (same :lex (diagnostic-phase (diagnostic-of (lambda () (lex-source source))))))
    (expect-cli (list "run" (namestring (put-bytes (fresh-path) (first case))))
                1 :phase "lex")))

(deftest v06-invalid-words-and-characters
  (dolist (text '("foo" "truefalse" "trueif" "True" "TRUE" "true1" "1"
                  ";" "// comment" "/*x*/" "_" "#.(quit)" "+" "null"))
    (expect-invalid text "lex"))
  (let* ((source (text-source "truefalse"))
         (diag (diagnostic-of (lambda () (lex-source source)))))
    (same 1 (diagnostic-column diag))))

(deftest v09-v12-invalid-grammar
  (dolist (text '("" " " "if(true){}else{false}" "if(true){true false}else{false}"
                  "if true){true}else{false}" "if(true{true}else{false}"
                  "if(true)true}else{false}" "if(true){true else{false}"
                  "if(true){true}" "if(true){true}else false}"
                  "if(true){true}else{false" "true)" "true false"
                  "if(true){true}else{false}if(false){false}else{true}"
                  "(true)" "if(true){true}else if(false){true}else{false}"
                  "if(true){true}else{}"))
    (expect-invalid text "parse")))

(deftest frontend-spans
  (let* ((program (parse-text " if(true){false}else{true} "))
         (node (program-root program)))
    (same 1 (span-start (node-span node)))
    (same 26 (span-end (node-span node)))
    (same 4 (span-start (node-span (if-expression-condition node))))
    (same 8 (span-end (node-span (if-expression-condition node))))))
