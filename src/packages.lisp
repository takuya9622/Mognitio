(defpackage #:mognitio.diagnostics
  (:use #:cl)
  (:export #:diagnostic #:make-diagnostic #:diagnostic-phase #:diagnostic-message
           #:diagnostic-path #:diagnostic-line #:diagnostic-column
           #:compiler-failure #:failure-diagnostic #:source-failure
           #:usage-or-io-failure #:internal-failure #:fail #:internal-error
           #:render-diagnostic #:one-line))
(defpackage #:mognitio.source
  (:use #:cl #:mognitio.diagnostics)
  (:export #:source #:source-path #:source-octets #:source-text #:source-byte-offsets
           #:source-lines #:source-columns #:decode-source #:read-source
           #:span #:make-span #:span-source #:span-start #:span-end
           #:span-diagnostic #:fail-at))
(defpackage #:mognitio.syntax
  (:use #:cl #:mognitio.source)
  (:export #:token #:make-token #:token-kind #:token-span #:boolean-literal
           #:make-boolean-literal #:boolean-literal-value #:boolean-literal-span
           #:if-expression #:make-if-expression #:if-expression-condition
           #:if-expression-then-branch #:if-expression-else-branch #:if-expression-span
           #:node-span #:program #:make-program #:program-source #:program-root
           #:program-statements #:token-text #:integer-literal #:make-integer-literal
           #:integer-literal-token #:integer-literal-span #:variable-reference
           #:make-variable-reference #:variable-reference-name #:variable-reference-span
           #:local-binding #:make-local-binding #:local-binding-mutability #:local-binding-name
           #:local-binding-initializer #:local-binding-span #:assignment #:make-assignment
           #:assignment-name #:assignment-rhs #:assignment-span #:sequence-node
           #:make-sequence-node #:sequence-node-statements #:sequence-node-tail
           #:sequence-node-span #:grouping #:make-grouping #:grouping-expression
           #:grouping-span #:unary-expression #:make-unary-expression
           #:unary-expression-operator #:unary-expression-operand #:unary-expression-span
           #:binary-expression #:make-binary-expression #:binary-expression-operator
           #:binary-expression-left #:binary-expression-right #:binary-expression-span))
(defpackage #:mognitio.frontend
  (:use #:cl #:mognitio.diagnostics #:mognitio.source #:mognitio.syntax)
  (:export #:lex-source #:parse-program))
(defpackage #:mognitio.semantic
  (:use #:cl #:mognitio.diagnostics #:mognitio.source #:mognitio.syntax)
  (:export #:check-program #:checked-program #:checked-program-program #:checked-type #:checked-symbol #:checked-literal #:checked-literal-p #:checked-program-bindings #:local-symbol-id #:local-symbol-type #:local-symbol-mutability))
(defpackage #:mognitio.backend.cl
  (:use #:cl #:mognitio.diagnostics #:mognitio.source #:mognitio.syntax
        #:mognitio.semantic)
  (:export #:compile-program #:execute-program #:compiled-program))
(defpackage #:mognitio.driver
  (:use #:cl #:mognitio.diagnostics #:mognitio.source #:mognitio.syntax
        #:mognitio.frontend #:mognitio.semantic #:mognitio.backend.cl)
  (:export #:run-cli))
(defpackage #:mognitio.cli
  (:use #:cl)
  (:export #:main))

(defpackage #:mognitio.ir
  (:use #:cl #:mognitio.diagnostics #:mognitio.source #:mognitio.syntax
        #:mognitio.semantic)
  (:export #:instruction #:make-instruction #:instruction-result #:instruction-type
           #:instruction-op #:instruction-value #:instruction-operands #:instruction-span
           #:basic-block #:make-basic-block #:basic-block-id #:basic-block-parameters
           #:basic-block-instructions #:basic-block-terminator #:basic-block-span
           #:module #:make-module #:module-functions #:module-entry #:module-span
           #:ir-function #:make-ir-function #:ir-function-id #:ir-function-parameter-types
           #:ir-function-result-type #:ir-function-blocks #:ir-function-entry #:ir-function-span
           #:lower-program #:verify-module #:successors))
(defpackage #:mognitio.object
  (:use #:cl #:mognitio.diagnostics)
  (:export #:code-unit #:make-code-unit #:code-unit-owner #:code-unit-instructions
           #:code-unit-entry #:layout-units #:image-symbol #:make-image-symbol
           #:image-symbol-name #:image-symbol-kind #:image-symbol-offset #:symbol-kind
           #:fixup #:make-fixup #:fixup-offset #:fixup-end #:fixup-target #:fixup-kind #:fixup-use))
(defpackage #:mognitio.machine
  (:use #:cl #:mognitio.diagnostics)
  (:export #:instruction #:make-instruction #:instruction-opcode
           #:instruction-operands #:instruction-span #:lower-module))
(defpackage #:mognitio.amd64
  (:use #:cl #:mognitio.diagnostics)
  (:export #:encode #:little-endian))
(defpackage #:mognitio.elf
  (:use #:cl #:mognitio.diagnostics)
  (:export #:make-image))
(defpackage #:mognitio.backend.native
  (:use #:cl #:mognitio.diagnostics)
  (:export #:compile-program))
(defpackage #:mognitio.artifact
  (:use #:cl #:mognitio.diagnostics)
  (:export #:validate-paths #:publish-image))
(defpackage #:mognitio.target
  (:use #:cl #:mognitio.diagnostics)
  (:export #:target #:linux-amd64 #:target-os #:target-arch #:target-abi #:target-artifact))

(defpackage #:mognitio.runtime (:use #:cl) (:export #:integer-runtime-failure #:failure-kind #:failure-octets #:failure-status #:runtime-error #:write-runtime-failure #:+retry-budget+))
(defpackage #:mognitio.integer (:use #:cl) (:export #:+minimum+ #:+maximum+ #:in-range-p #:decimal-magnitude #:checked-arithmetic))
