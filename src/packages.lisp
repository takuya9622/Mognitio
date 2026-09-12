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
  (:export #:token #:make-token #:token-kind #:token-span
           #:boolean-literal #:make-boolean-literal #:boolean-literal-value
           #:boolean-literal-span #:if-expression #:make-if-expression
           #:if-expression-condition #:if-expression-then-branch
           #:if-expression-else-branch #:if-expression-span #:node-span
           #:program #:make-program #:program-source #:program-root))
(defpackage #:mognitio.frontend
  (:use #:cl #:mognitio.diagnostics #:mognitio.source #:mognitio.syntax)
  (:export #:lex-source #:parse-program))
(defpackage #:mognitio.semantic
  (:use #:cl #:mognitio.diagnostics #:mognitio.source #:mognitio.syntax)
  (:export #:check-program #:checked-program #:checked-program-program))
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
           #:instruction-op #:instruction-value #:instruction-span
           #:basic-block #:make-basic-block #:basic-block-id #:basic-block-parameters
           #:basic-block-instructions #:basic-block-terminator #:basic-block-span
           #:module #:make-module #:module-blocks #:module-entry #:module-span
           #:lower-program #:verify-module #:successors))
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
