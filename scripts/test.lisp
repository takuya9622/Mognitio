(require :asdf)
(asdf:load-asd (truename (merge-pathnames "../mognitio.asd" *load-truename*)))
(asdf:test-system "mognitio")
