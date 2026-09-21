(in-package #:mognitio.tests)

(deftest v05-void-blocks-and-flow
  (dolist (source
    '("void; {}; true"
      "let value = {}; var other = void; other = value; other; true"
      "let f = function(x: void, n: int): void { x; if(n == 0){return;}; void }; f(void, 0); f({}, 1); true"
      "let f = function(): void {}; f(); true"
      "let f = function(): void { return void; }; f(); true"
      "let f = function(): int { 7 }; let g = { f }; g() == 7"
      "let f = function(): int { 7 }; ({ f })() == 7"
      "let outer = function(flag: bool): int { if(flag){return 7;}; 8 }; outer(true) + outer(false) == 15"
      "let f = function(): int { ({ return 7; })(1 / 0) }; f() == 7"
      "let f = function(x: int): int { x }; let g = function(): int { f({ return 8; }) }; g() == 8"
      "var n = 0; let f = function(x: int): int { x }; ({ n = n + 1; f })({ n = n * 10; n }) == 10"
      "let f = function(): int { { return 7; }; }; f() == 7"
      "-(-1) == 1" "10 - (-2) == 12"))
    (v03-positive source :true))
  (dolist (source
    '("void" "void == void" "void + 1 == 1" "1; true" "true; false"
      "let f = function(): int {1}; f(); true" "function(): void {}; true"
      "if(true){1}; true" "if(true){void}else{1}; true"
      "let f = function(): int { return; }; true" "let f = function(): int {}; true"
      "let f = function(): void { 1 }; true" "let f = function(x: void): void {}; f(true); true"
      "let f = function(): int { return 1; 2 }; true"
      "let f = function(): int { {return 1;}; let x = 2; x }; true"
      "let f = function(): int { var x = 1; x = {return 7;}; true }; true"
      "let f = function(): int { 1 }; let selected = {f}; let g = function(): int {selected()}; true"
      "let f = function(): int { ({return 1;})(missing) }; true"
      "return true; false"))
    (v03-reject source "semantic"))
  (dolist (source '("--1 == 1" "- -1 == 1" "10--2 == 12" "10 - -2 == 12"
                    "()" "(); true" ";true" "void;" "let x = void;" "true;;"
                    "let void = 1; true" "function named(): void {} true"))
    (v03-reject source "parse"))
  (v03-reject (format nil "-~%-1 == 1") "parse")
  (v03-runtime "-(-9223372036854775808) == 0" "integer overflow"))

(deftest v05-migrated-semantic-rejections
  (dolist (source '("let f = function(): void { 1 }; true"
    "let f = function(): int { }; true"
    "if(true){}else{false}"
    "let f = function(): int { 1 }; f(); true"
    "let f = function(): int { return; }; true"
    "let f = function(): int { return 1; 2 }; true"
    "let f = function(): int { return 1; let x = 2; x }; true"))
    (v03-reject source "semantic")))
