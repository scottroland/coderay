module CodeRay
module Scanners

  # TODO: Review. Most of this code is copied from the C++ scanner and not
  # applicable for e.

  # Scanner for IEEE Std 1647 e
  #
  # Aliases: +specmen+
  class E < Scanner

    register_for :e
    file_extension 'e'
    title 'e'

    # TODO: DUT'unique_name

    # NOTE: e is an odd language in that the essential vocabulary of the
    # language (like 'extend') are not actually reserved words. The following
    # parser isn't smart enough to handle that; it pretends that these are
    # reserved words.

    KEYWORDS = [
       'a', 'also', 'bits', 'cover', 'each', 'else', 'empty', 'extend', 'first', 'for', 'ignore', 'illegal', 'if', 'in', 'is', 'item', 'keep', 'like', 'list', 'not', 'only', 'package', 'per_instance', 'radix', 'result', 'return', 'rf_manager', 'soft', 'sys', 'type', 'unit', 'using', 'var', 'when'
    ]  # :nodoc:
    
    PREDEFINED_TYPES = [
       'bool', 'bit', 'event', 'rf_scalar', 'rf_type', 'string', 'uint'
    ]  # :nodoc:
    PREDEFINED_CONSTANTS = [
       'FALSE', 'TRUE'
    ]  # :nodoc:
    PREDEFINED_VARIABLES = [
    ]  # :nodoc:
    DIRECTIVES = [
    ]  # :nodoc:
    
    IDENT_KIND = WordList.new(:ident).
      add(KEYWORDS, :keyword).
      add(PREDEFINED_TYPES, :predefined_type).
      add(PREDEFINED_VARIABLES, :local_variable).
      add(DIRECTIVES, :directive).
      add(PREDEFINED_CONSTANTS, :predefined_constant)  # :nodoc:

    ESCAPE = / [rbfntv\n\\'"] | x[a-fA-F0-9]{1,2} | [0-7]{1,3} /x  # :nodoc:
    UNICODE_ESCAPE =  / u[a-fA-F0-9]{4} | U[a-fA-F0-9]{8} /x  # :nodoc:
    
  protected
    
    def scan_tokens encoder, options

      state = :comment_segment
      label_expected = true
      case_expected = false
      label_expected_before_preproc_line = nil
      in_preproc_line = false

      until eos?

        case state

        when :comment_segment
          if match = scan(/^<'$/)            
            encoder.text_token match, :operator
            state = :code_segment
          elsif match = scan(/^.+$/)             
            encoder.text_token match, :comment
          elsif match = scan(/\\\n/)
            encoder.text_token match, :space
          else
            encoder.text_token getch, :error
          end

        when :code_segment
          if match = scan(/^'>$/)            
            encoder.text_token match, :operator
            state = :comment_segment

          elsif match = scan(/ \s+ | \\\n /x)
            if in_preproc_line && match != "\\\n" && match.index(?\n)
              in_preproc_line = false
              label_expected = label_expected_before_preproc_line
            end
            encoder.text_token match, :space

          elsif match = scan(%r! // [^\n\\]* (?: \\. [^\n\\]* )* !mx)
            encoder.text_token match, :comment
          elsif match = scan(%r! -- [^\n\\]* (?: \\. [^\n\\]* )* !mx)
            encoder.text_token match, :comment

          elsif match = scan(/ \# \s* if \s* 0 /x)
            match << scan_until(/ ^\# (?:elif|else|endif) .*? $ | \z /xm) unless eos?
            encoder.text_token match, :comment

            #########################
            # 4.1.4.2 Sized numbers
          elsif match = scan(/[0-9]+'[bB][0-1_]+/)
            label_expected = false
            encoder.text_token match, :binary
          elsif match = scan(/[0-9]+'[oO][0-7_]+/)
            label_expected = false
            encoder.text_token match, :octal
          elsif match = scan(/[0-9]+'[dD][0-9_a-f]+/)
            label_expected = false
            encoder.text_token match, :integer
          elsif match = scan(/[0-9]+'[hxHX][0-9_a-f]+/)
            label_expected = false
            encoder.text_token match, :hex

            #########################
            # 4.1.4.1 Unsized numbers
          elsif match = scan(/0x[0-9_a-f]+/)
            label_expected = false
            encoder.text_token match, :hex
          elsif match = scan(/0o([0-7_]+)/)
            label_expected = false
            encoder.text_token match, :octal
          elsif match = scan(/0b[0-1_]+/)
            label_expected = false
            encoder.text_token match, :binary
          elsif match = scan(/\-?[0-9_]+[kmKM]?/)
            label_expected = false
            encoder.text_token match, :integer


          elsif match = scan(/ [-+*=<>?:;,!&^|()\[\]{}~%]+ | \/=? | \.(?!\d) /x)
            label_expected = match =~ /[;\{\}]/
            if case_expected
              label_expected = true if match == ':'
              case_expected = false
            end
            encoder.text_token match, :operator

          elsif match = scan(/ [A-Za-z_][A-Za-z_0-9]* /x)
            kind = IDENT_KIND[match]
            if kind == :ident && label_expected && !in_preproc_line && scan(/:(?!:)/)
              kind = :label
              match << matched
            else
              label_expected = false
              if kind == :keyword
                case match
                when 'class'
                  state = :class_name_expected
                when 'case', 'default'
                  case_expected = true
                end
              end
            end
            encoder.text_token match, kind

          elsif match = scan(/\$/)
            encoder.text_token match, :ident
          
          elsif match = scan(/L?"/)
            encoder.begin_group :string
            if match[0] == ?L
              encoder.text_token match, 'L', :modifier
              match = '"'
            end
            state = :string
            encoder.text_token match, :delimiter

          elsif match = scan(/`[ \t]*(\w*)/)
            encoder.text_token match, :preprocessor
            in_preproc_line = true
            label_expected_before_preproc_line = label_expected
            state = :include_expected if self[1] == 'include'

          elsif match = scan(/ L?' (?: [^\'\n\\] | \\ #{ESCAPE} )? '? /ox)
            label_expected = false
            encoder.text_token match, :char

          elsif match = scan(/\d[fF]?|\d*\.\d+(?:[eE][+-]?\d+)?[fF]?|\d+[eE][+-]?\d+[fF]?/)
            label_expected = false
            encoder.text_token match, :float

          else
            encoder.text_token getch, :error

          end

        when :string
          if match = scan(/[^\\"]+/)
            encoder.text_token match, :content
          elsif match = scan(/"/)
            encoder.text_token match, :delimiter
            encoder.end_group :string
            state = :code_segment
            label_expected = false
          elsif match = scan(/ \\ (?: #{ESCAPE} | #{UNICODE_ESCAPE} ) /mox)
            encoder.text_token match, :char
          elsif match = scan(/ \\ | $ /x)
            encoder.end_group :string
            encoder.text_token match, :error
            state = :code_segment
            label_expected = false
          else
            raise_inspect "else case \" reached; %p not handled." % peek(1), encoder
          end

        when :include_expected
          if match = scan(/<[^>\n]+>?|"[^"\n\\]*(?:\\.[^"\n\\]*)*"?/)
            encoder.text_token match, :include
            state = :code_segment

          elsif match = scan(/\s+/)
            encoder.text_token match, :space
            state = :code_segment if match.index ?\n

          else
            state = :code_segment

          end
        
        when :class_name_expected
          if match = scan(/ [A-Za-z_][A-Za-z_0-9]* /x)
            encoder.text_token match, :class
            state = :code_segment

          elsif match = scan(/\s+/)
            encoder.text_token match, :space

          else
            encoder.text_token getch, :error
            state = :code_segment

          end
          
        else
          raise_inspect 'Unknown state', encoder

        end

      end

      if state == :string
        encoder.end_group :string
      end

      encoder
    end

  end

end
end
