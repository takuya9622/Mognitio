(in-package #:mognitio.tests)

(deftest v05-void-blocks-and-flow
  (dolist (source
    '("void; {}; true"
      "let value: void = {}; var other: void = void; other = value; other; true"
      "let f :function(void,int):void= function(x: void, n: int): void { x; branch when{(n == 0)=>{return;}}; void }; f(void, 0); f({}, 1); true"
      "let f :function():void= function(): void {}; f(); true"
      "let f :function():void= function(): void { return void; }; f(); true"
      "let f :function():int= function(): int { 7 }; ({ f })() == 7"
      "let f :function():int= function(): int { 7 }; ({ f })() == 7"
      "let outer :function(bool):int= function(flag: bool): int { branch when{(flag)=>{return 7;}}; 8 }; outer(true) + outer(false) == 15"
      "let f :function():int= function(): int { ({ return 7; })(1 / 0) }; f() == 7"
      "let f :function(int):int= function(x: int): int { x }; let g :function():int= function(): int { f({ return 8; }) }; g() == 8"
      "var n: int = 0; let f :function(int):int= function(x: int): int { x }; ({ n = n + 1; f })({ n = n * 10; n }) == 10"
      "let f :function():int= function(): int { { return 7; }; }; f() == 7"
      "-(-1) == 1" "10 - (-2) == 12"))
    (v03-positive source :true))
  (dolist (source
    '("void" "void == void" "void + 1 == 1" "1; true" "true; false"
      "let f :function():int= function(): int {1}; f(); true" "function(): void {}; true"
      "branch when{(true)=>{1}}; true" "branch when{(true)=>{void},else=>{1}}; true"
      "let f :function():int= function(): int { return; }; true" "let f :function():int= function(): int {}; true"
      "let f :function():void= function(): void { 1 }; true" "let f :function(void):void= function(x: void): void {}; f(true); true"
      "let f :function():int= function(): int { return 1; 2 }; true"
      "let f :function():int= function(): int { {return 1;}; let x = 2; x }; true"
      "let f :function():int= function(): int { var x: int = 1; x = {return 7;}; true }; true"
      "let f :function():int= function(): int { 1 }; let selected = {f}; let g :function():int= function(): int {selected()}; true"
      "let f :function():int= function(): int { ({return 1;})(missing) }; true"
      "return true; false"))
    (v03-reject source "semantic"))
  (dolist (source '("--1 == 1" "- -1 == 1" "10--2 == 12" "10 - -2 == 12"
                    "()" "(); true" ";true" "void;" "let x = void;" "true;;"
                    "let void = 1; true" "function named(): void {} true"))
    (v03-reject source "parse"))
  (v03-reject (format nil "-~%-1 == 1") "parse")
  (v03-runtime "-(-9223372036854775808) == 0" "integer overflow"))

(deftest v05-migrated-semantic-rejections
  (dolist (source '("let f :function():void= function(): void { 1 }; true"
    "let f :function():int= function(): int { }; true"
    "branch when{(true)=>{},else=>{false}}"
    "let f :function():int= function(): int { 1 }; f(); true"
    "let f :function():int= function(): int { return; }; true"
    "let f :function():int= function(): int { return 1; 2 }; true"
    "let f :function():int= function(): int { return 1; let x = 2; x }; true"))
    (v03-reject source "semantic")))
