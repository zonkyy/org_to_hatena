#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# org-mode の書式をはてな記法に変換するクラス
class OrgToHatena
  LANG_CONV_TABLE = {'emacs-lisp' => 'lisp'}
  CATEGORY_CAPTION_RE  = /^\*\s+\S+\s+:([^:]+:)+/
  LIST_RE = /^\s*(-|\+|\d+(\.|\)))/
  DEFLIST_RE = /^\s*-.+::.+/
  UNORDERED_LIST_RE = /^\s*(-|\+)/
  ORDERED_LIST_RE = /^\s*\d+(\.|\))/
  TABLE_RE = /^\s*\|([^|]*\|)+\s*$/
  BEGIN_COMMENT_STR = '^\s*#\+BEGIN_'
  END_COMMENT_STR = '^\s*#\+END_'
  LINE_EXAMPLE_RE = /^\s*:\s.+$/
  FOOTNOTE_RE = /\[fn:\w+\]/ # まだ使ってない
  NEXT_RE = /^#====[^=]?\s*$/ # まだ使ってない
  SUPER_NEXT_RE = /^#=====/ # まだ使ってない
  COMMENT_RE = /^#/
  INDENT_COMMENT_RE = /^\s*#\+/
  URL_RE_STR = '(https?|ftp)(:\/\/[-_.!~*\'()a-zA-Z0-9;\/?:\@&=+\$,%#]+)'

  # 入力したorgファイルをはてな記法で記述された文字列に変換する。
  # @param [String] src はてな記法に変換したいorgファイルのパス
  # @return [String] はてな記法で記述された文字列
  def to_hatena(src)
    buf = []

    lines = File.readlines(src).map { |line| line.chomp }

    # orgファイルからはてな記法に変換
    while lines.first
      case lines.first
      when CATEGORY_CAPTION_RE
        buf << parse_category_caption(lines.shift)
      when DEFLIST_RE
        buf.concat parse_deflist(take_block(lines, DEFLIST_RE))
      when LIST_RE
        buf.concat parse_list(take_block(lines, LIST_RE))
      when TABLE_RE
        buf.concat parse_table(take_block(lines, TABLE_RE))
      when begin_format_regexp('quote')
        buf.concat parse_quote(take_format(lines, end_format_regexp('quote')))
      when LINE_EXAMPLE_RE
        buf.concat parse_line_example(take_block(lines, LINE_EXAMPLE_RE))
      when begin_format_regexp('example')
        buf.concat parse_example(take_format(lines, end_format_regexp('example')))
      when begin_format_regexp('src')
        buf.concat parse_src(take_format(lines, end_format_regexp('src')))
      else
        if lines.first =~ COMMENT_RE or lines.first =~ INDENT_COMMENT_RE
          # コメント行は除去
          lines.shift
        else
          buf << lines.shift
        end
      end
    end

    # 文字列配列を接続したはてな記法を出力用に整形する
    "\n" + format_hatena_src(buf.join("\n"))
  end

  private

  # 入力したはてな記法の空行位置を整える。
  # キャプション下、ソースコード下、キャプション下の空行削除、
  # URLの変換 ([[http://~]] は [http://~:title], # [[http://~][name]] は [http://~:title=name])
  # @param [String] src はてな記法のソース
  # @return [String] 空行の数を調整したはてな記法ソース
  def format_hatena_src(src)
    # キャプション下、ソースコード下の空行除去
    src.gsub!(/((\*{1,3}[^\n]*)|\|\|<|<<)(\s*\n)*/) {"#$1\n"}
    # URLの変換
    src.gsub!(/\[\[#{URL_RE_STR}\](\[[^\[\]]+\])?\]/) {
      # タイトル付きなら$3にはタイトルが入る。それ以外なら$3はnil。
      ($3) ? "[#$1#$2:title=#{$3[/\[([^\[\]]+)\]/, 1]}]" : "[#$1#$2:title]"
    }
    src
  end

  # lines の先頭から正規表現 marker にマッチする行を全て取り出して配列で返す。
  # このとき、lines から marker にマッチした行は取り除かれる。markerは取り除かない。
  # @param [Array] lines はてな記法の文字列配列
  # @param [Regexp] marker 取り出したい行にマッチする正規表現
  # @return [Array] markerにマッチした文字列配列
  def take_block(lines, marker)
    buf = []
    until lines.empty?
      break unless marker =~ lines.first
      buf.push lines.shift
    end
    buf
  end

  # lines の先頭から正規表現 end_marker にマッチするまでの行を全て取り出して配列で返す。
  # このとき、lines から marker にマッチした行は取り除かれる。markerは取り除かない。
  # @param [Array] lines はてな記法の文字列配列
  # @param [Regexp] end_marker 取り出したいブロックの終了にマッチする正規表現
  # @return [Array] markerにマッチした文字列配列
  def take_format(lines, end_marker)
    buf = []
    finished = false
    until lines.empty? or finished
      finished = true if end_marker =~ lines.first
      buf.push lines.shift
    end
    buf
  end

  # 各書式の先頭と一致する正規表現。
  # @param [String] format 書式
  # @return [Regexp] 書式開始コメントと一致する正規表現
  def begin_format_regexp(format)
    /#{BEGIN_COMMENT_STR}#{format.upcase}/i
  end

  # 各書式の末尾と一致する正規表現。
  # @param [String] format 書式
  # @return [Regexp] 書式終了コメントと一致する正規表現
  def end_format_regexp(format)
    /#{END_COMMENT_STR}#{format.upcase}/i
  end

  # カテゴリ記法の処理。
  # @param [String] line カテゴリ記法に変換したいorg-modeの文字列
  # @return [String] 変換後の文字列
  # @todo キャプションにスペースが入れられるようにする
  def parse_category_caption(line)
    cap = line[/^\*\s+(\S+)\s+:/, 1]
    category = line.scan(/:(?=.+:)([^:]+)/).flatten
    "*[#{category.join("][")}] #{cap}"
  end

  # リスト記法の処理。
  # @param [Array] org_list リスト記法に変換したいorg-modeのリスト
  # @return [Array] 変換後の文字列配列
  def parse_list(org_list)
    indents = []
    hatena_list = []
    org_list.each do |l|
      line_indent = l.slice(/^\s*/).length
      indents.delete_if { |i| i >= line_indent }
      indents << line_indent
      case l
      when UNORDERED_LIST_RE
        hatena_list << ('-' * indents.length) + l.sub(LIST_RE, '')
      when ORDERED_LIST_RE
        hatena_list << ('+' * indents.length) + l.sub(LIST_RE, '')
      else
        raise 'must not happen.'
      end
    end

    hatena_list
  end

  # 定義リスト記法の処理。
  # @param [Array] org_deflist 定義リスト記法に変換したいorg-modeの定義リスト
  # @return [Array] 変換後の文字列配列
  def parse_deflist(org_deflist)
    org_deflist.map do |line|
      scanned = line.scan(/^\s*-(.+)::(.+)/).flatten
      ":#{scanned[0].strip}:#{scanned[1].strip}"
    end
  end

  # 表組み記法の処理。
  # @param [Array] org_table 表組み記法に変換したいorg-modeの文字列配列
  # @return [Array] 変換後の文字列配列
  def parse_table(org_table)
    # 区切りを除去後、最初の行に*を付ける
    org_table.delete_if { |line| line =~ /^\s*\|-/ }
    org_table[0].gsub!('|', '|*').sub!(/\|\*[^|]*$/, '|')
    org_table
  end

  # 引用記法の処理。
  # BEGIN_QUOTE から END_QUOTE までの変換。
  # @param [Array] org_example 引用記法に変換したいorg-modeの引用
  # @return [Array] 変換後の文字列配列
  def parse_quote(org_quote)
    org_quote.shift
    org_quote.unshift('>>')
    org_quote.pop
    org_quote.push('<<')
    org_quote
  end

  # 一行のpre記法の処理。
  # @param [Array] org_line_example pre記法に変換したいorg-modeの例示
  # @return [Array] 変換後の文字列配列
  def parse_line_example(org_line_example)
    scanned = org_line_example.map { |line| line[/^\s*:\s(.+)$/, 1] }
    scanned.unshift('>||')
    scanned.push('||<')
  end

  # 不要なインデントの除去。
  # @param [Array] text インデントを除去したい文字列配列
  # @return [Array] インデント除去後の文字列配列
  def remove_indent(org_text)
    min_indent = org_text.inject(Float::INFINITY) do |min, line|
      indent = line[/^\s*/].size
      indent < min ? indent : min
    end
    org_text.map { |line| line[/^\s{#{min_indent}}(.+)$/, 1]}
  end

  # 複数行のpre記法の処理。
  # @param [Array] org_example pre記法に変換したいorg-modeの例示
  # @return [Array] 変換後の文字列配列
  def parse_example(org_example)
    org_example.shift
    org_example.pop
    scanned = remove_indent(org_example)
    scanned.unshift('>||')
    scanned.push('||<')
    scanned
  end

  # シンタックスハイライト付きスーパーpre記法の処理
  # @param [Array] org_src スーパーpre記法に変換したいorg-modeのソースコード
  # @return [Array] 変換後の文字配列
  def parse_src(org_src)
    lang = org_src.shift[/#{BEGIN_COMMENT_STR}SRC\s+(\S+)/i, 1]
    lang = LANG_CONV_TABLE[lang] if LANG_CONV_TABLE[lang]
    org_src.pop
    scanned = remove_indent(org_src)
    scanned.unshift(">|#{lang}|")
    scanned.push('||<')
    scanned
  end

end


if __FILE__ == $0
  oth = OrgToHatena.new
  while argv = ARGV.shift
    s = oth.to_hatena(argv)
    output = argv.sub('.org', '.txt')
    open(output, "w") { |f|
      f.print s
    }
  end
end
