(in-package #:mognitio.tests)

(defparameter *v07-contract-source*
  "type U=struct{s:string;}; type V=enum{Item(string);}; interface Name{let name = function():string;} type N=Name; implement U against N{let name=function():string{this->s};} implement V against Name{let name=function():string{branch on(this){V::Item(s)=>s}};} let render=function(n:N):string{n->name()};")
(defparameter *v07-same-name-source*
  "type U=struct{}; interface A{let name = function():string;} interface B{let name = function():string;} type Alias=A; implement U against Alias{let name=function():string{\"a\"};} implement U against B{let name=function():string{\"b\"};} let a=function(x:A):string{x->name()};let b=function(x:B):string{x->name()};")

(deftest v07-methods-and-dispatch
  ;; C07-25..35, 47..50, 52..53.
  (v07-accept "type U=struct{n:int;};interface I{let number = function():int;}implement U against I{let number=function():int{this->n};}implement U{let asI=function():I{this};let pass=function(u:U):int{u->n};let forward=function():int{this->pass(this)};}branch when{U{n:7}->asI()->number()==7=>U{n:7}->forward()==7,else=>false}")
  (v03-reject "interface Step{let step = function():bool;}type Alias=Step;type Stop=struct{};implement Stop against Alias{let step=function():bool{true};}let apply=function(v:Alias):bool{v->step()};type Again=struct{};implement Again against Step{let step=function():bool{apply(Stop{})};}apply(Stop{})" "semantic")
  (dolist (suffix '("render(U{s:\"a\"})+render(V::Item(\"b\"))==\"ab\""
                    "let make=function():N{U{s:\"a\"}}; var n:N=make();let old:N=n;n=V::Item(\"b\");old->name()+n->name()==\"ab\""
                    "U{s:\"a\"}->name()+V::Item(\"b\")->name()==\"ab\""))
    (v07-accept (concatenate 'string *v07-contract-source* suffix)))
  (v07-accept (concatenate 'string *v07-same-name-source* "a(U{})+b(U{})==\"ab\""))
  (v07-reject (concatenate 'string *v07-same-name-source* "U{}->name()==\"a\"") "semantic")
  (dolist (source
    '("type U=struct{s:string;};let raw=function(u:U):string{u->s};implement U{let name=function():string{raw(this)};let copy=function():U{return this;};let value=function():U{this};} U{s:\"ok\"}->copy()->value()->name()==\"ok\""
      "type U=struct{};implement U{let f=function():int{this->g()};let g=function():int{7};}let f: int=2;U{}->f()+f==9"
      "type U=struct{};implement U{let a=function():int{1};}implement U{let b=function():int{2};}U{}->a()+U{}->b()==3"
      "type U=struct{x:int;};implement U{let add=function(a:int,b:int,):int{this->x*100+a*10+b};}var n: int=0;let x: int=({n=n+1;U{x:n}})->add({n=n+1;n},{n=n+1;n},);x+n==126"
      "type U=struct{};implement U{let f=function(a:int):int{a};}let g=function():int{({return 7;})->f(1/0)};g()==7"
      "type U=struct{};implement U{let f=function(a:int,b:int):int{a+b};}let g=function():int{U{}->f({return 7;},1/0)};g()==7"
      "type U=struct{};interface A{let f = function():int;}interface B{let f = function():int;}implement U against A{let f=function():int{1};}let first=function(u:U):int{u->f()};implement U against B{let f=function():int{2};}first(U{})==1"
      "type U=struct{};interface Empty{}implement U against Empty{}let f=function(e:Empty):bool{true};f(U{})"
      "type U=struct{};interface A{let a = function():int;}let use=function(x:A):int{x->a()};implement U against A{let a=function():int{7};let extra=function():int{1};}true"))
    ;; The final source is an intentional rejection below, never an acceptance.
    (if (search "let extra" source) (v07-reject source "semantic") (v07-accept source)))
  (dolist (source
    '("type U=struct{};interface A{let f = function():int;}implement U against A{}true"
      "type U=struct{};interface A{let f = function():int;}implement U against A{let f=function():bool{true};}true"
      "type U=struct{};interface A{let f = function(x:int):int;}implement U against A{let f=function():int{1};}true"
      "type U=struct{};interface A{}type B=A;implement U against A{}implement U against B{}true"
      "type U=struct{f:int;};implement U{let f=function():int{1};}true"
      "type U=struct{};implement U{let f=function():int{1};}implement U{let f=function():int{2};}true"
      "type U=struct{};interface A{let f = function():int;}implement U{let f=function():int{1};}implement U against A{let f=function():int{2};}U{}->f()==1"
      "type U=struct{};interface A{let f = function():int;}interface B{let f = function(x:int):int;}implement U against A{let f=function():int{1};}implement U against B{let f=function(x:int):int{x};}U{}->f()==1"
      "this" "type U=struct{};implement U{let f=function():U{this=U{};this};}true"
      "type U=struct{};implement U{let f=function():U{let g=function():U{this};g()};}true"
      "type I=int;implement I{let f=function():int{1};}true"
      "type U=struct{};implement U{let f=function():int{1};}U{}->f"
      "type U=struct{};implement U{let f=function():int{this->f()};}true"
      "type U=struct{};implement U{let f=function():int{this->g()};let g=function():int{this->f()};}true"
      "interface Step{let step = function():bool;}type Stop=struct{};implement Stop against Step{let step=function():bool{true};}let apply=function(v:Step):bool{v->step()};type Again=struct{};implement Again against Step{let step=function():bool{apply(Stop{})};}apply(Stop{})"
      "interface A{let f = function():int;}type U=struct{};implement U{let f=function():int{1};}let use=function(a:A):int{a->f()};use(U{})==1"
      "interface A{}type U=struct{};implement U against A{}let cast=function(a:A):U{a};true"
      "type U=struct{};type V=struct{};interface A{}implement U against A{}implement V against A{}let f=function():A{branch when{true=>U{},else=>V{}}};true"
      "\"a\"->length" "(\"a\"->length)()"))
    (v07-reject source "semantic"))
  (dolist (source '("implement int{let f=function():int{1};}true"
                    "interface A{let f = function():int{1};}true" "interface A{let x=1;}true"
                    "type U=struct{};implement U{let f=function(this:U):int{1};}true"))
    (v07-reject source "parse")))
