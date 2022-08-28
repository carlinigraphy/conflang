# vim:ft=sh

Describe 'imports'
   It 'lexer'
      When run source lib/lexer.sh
      The status should be success
   End

   It 'parser'
      When run source lib/parser.sh
      The status should be success
   End

   It 'compiler'
      When run source lib/compiler.sh
      The status should be success
   End
End


Describe 'lexer.sh'
   Include lib/lexer.sh
   Include lib/errors.sh

   It 'fails with no input'
      When run init_scanner
      The status should eq "${EXIT_STATUS[no_input]}" 
      The status should be failure
      The stderr should include 'missing input'
   End

   It 'runs with empty file'
      FILES=( test/share/empty.conf )
      init_scanner

      When run scan
      The status should be success
   End
End
