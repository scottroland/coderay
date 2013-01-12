module CodeRay
module Scanners

  # TODO: Review. Most of this code is copied from the C++ scanner and not
  # applicable for SystemVerilog.

  # Scanner for IEEE Standard 1800-2009 SystemVerilog
  #
  # Aliases: +verilog+
  class SystemVerilog < Scanner

    register_for :systemverilog
    file_extension 'sv'
    title 'SystemVerilog'

    
    KEYWORDS = [
      'accept_on', 'alias', 'always', 'always_comb', 'always_ff', 'always_latch', 'and', 'assert', 'assign', 'assume', 'before', 'begin', 'bind', 'bins', 'binsof', 'break', 'buf', 'bufif0', 'bufif1', 'byte', 'case', 'casex', 'casez', 'cell', 'chandle', 'checker', 'class', 'clocking', 'cmos', 'config', 'const', 'constraint', 'context', 'continue', 'cover', 'covergroup', 'coverpoint', 'cross', 'deassign', 'default', 'defparam', 'design', 'disable', 'dist', 'do', 'edge', 'else', 'end', 'endcase', 'endchecker', 'endclass', 'endclocking', 'endconfig', 'endfunction', 'endgenerate', 'endgroup', 'endinterface', 'endmodule', 'endpackage', 'endprimitive', 'endprogram', 'endproperty', 'endsequence', 'endspecify', 'endtable', 'endtask', 'enum', 'event', 'eventually', 'expect', 'export', 'extends', 'extern', 'final', 'first_match', 'for', 'force', 'foreach', 'forever', 'fork', 'forkjoin', 'function', 'generate', 'genvar', 'global', 'highz0', 'highz1', 'if', 'iff', 'ifnone', 'ignore_bins', 'illegal_bins', 'implies', 'import', 'incdir', 'include', 'initial', 'inout', 'input', 'inside', 'instance', 'interface', 'intersect', 'join', 'join_any', 'join_none', 'large', 'let', 'liblist', 'library', 'local', 'localparam', 'macromodule', 'matches', 'medium', 'modport', 'module', 'nand', 'negedge', 'new', 'nexttime', 'nmos', 'nor', 'noshowcancelled', 'not', 'notif0', 'notif1', 'or', 'output', 'package', 'packed', 'parameter', 'pmos', 'posedge', 'primitive', 'priority', 'program', 'property', 'protected', 'pull0', 'pull1', 'pulldown', 'pullup', 'pulsestyle_ondetect', 'pulsestyle_onevent', 'pure', 'rand', 'randc', 'randcase', 'randsequence', 'rcmos', 'real', 'realtime', 'ref', 'reg', 'reject_on', 'release', 'repeat', 'restrict', 'return', 'rnmos', 'rpmos', 'rtran', 'rtranif0', 'rtranif1', 's_always', 's_eventually', 's_nexttime', 's_until', 's_until_with', 'scalared', 'sequence', 'shortint', 'shortreal', 'showcancelled', 'signed', 'small', 'solve', 'specify', 'specparam', 'static', 'strong', 'strong0', 'strong1', 'struct', 'super', 'supply0', 'supply1', 'sync_accept_on', 'sync_reject_on', 'table', 'tagged', 'task', 'throughout', 'time', 'timeprecision', 'timeunit', 'tran', 'tranif0', 'tranif1', 'tri', 'tri0', 'tri1', 'triand', 'trior', 'trireg', 'type', 'typedef', 'union', 'unique', 'unique0', 'unsigned', 'until', 'until_with', 'untyped', 'use', 'uwire', 'var', 'vectored', 'wait', 'wait_order', 'wand', 'weak', 'weak0', 'weak1', 'while', 'wildcard', 'with', 'within', 'wor', 'xnor', 'xor'
    ]  # :nodoc:
    
    PREDEFINED_TYPES = [
      'bit', 'int', 'integer', 'logic', 'longint', 'string', 'wire'
    ]  # :nodoc:
    PREDEFINED_CONSTANTS = [
      'null'
    ]  # :nodoc:
    PREDEFINED_VARIABLES = [
      'this',
    ]  # :nodoc:
    DIRECTIVES = [
      'automatic', 'virtual', 'void'
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

      state = :initial
      label_expected = true
      case_expected = false
      label_expected_before_preproc_line = nil
      in_preproc_line = false

      until eos?

        case state

        when :initial

          if match = scan(/ \s+ | \\\n /x)
            if in_preproc_line && match != "\\\n" && match.index(?\n)
              in_preproc_line = false
              label_expected = label_expected_before_preproc_line
            end
            encoder.text_token match, :space

          elsif match = scan(%r! // [^\n\\]* (?: \\. [^\n\\]* )* | /\* (?: .*? \*/ | .* ) !mx)
            encoder.text_token match, :comment

          elsif match = scan(/ \# \s* if \s* 0 /x)
            match << scan_until(/ ^\# (?:elif|else|endif) .*? $ | \z /xm) unless eos?
            encoder.text_token match, :comment

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

          elsif match = scan(/0[xX][0-9A-Fa-f]+/)
            label_expected = false
            encoder.text_token match, :hex

          elsif match = scan(/(?:0[0-7]+)(?![89.eEfF])/)
            label_expected = false
            encoder.text_token match, :octal

          elsif match = scan(/(?:\d+)(?![.eEfF])L?L?/)
            label_expected = false
            encoder.text_token match, :integer

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
            state = :initial
            label_expected = false
          elsif match = scan(/ \\ (?: #{ESCAPE} | #{UNICODE_ESCAPE} ) /mox)
            encoder.text_token match, :char
          elsif match = scan(/ \\ | $ /x)
            encoder.end_group :string
            encoder.text_token match, :error
            state = :initial
            label_expected = false
          else
            raise_inspect "else case \" reached; %p not handled." % peek(1), encoder
          end

        when :include_expected
          if match = scan(/<[^>\n]+>?|"[^"\n\\]*(?:\\.[^"\n\\]*)*"?/)
            encoder.text_token match, :include
            state = :initial

          elsif match = scan(/\s+/)
            encoder.text_token match, :space
            state = :initial if match.index ?\n

          else
            state = :initial

          end
        
        when :class_name_expected
          if match = scan(/ [A-Za-z_][A-Za-z_0-9]* /x)
            encoder.text_token match, :class
            state = :initial

          elsif match = scan(/\s+/)
            encoder.text_token match, :space

          else
            encoder.text_token getch, :error
            state = :initial

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
