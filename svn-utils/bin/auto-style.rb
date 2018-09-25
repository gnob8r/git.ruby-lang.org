#!/usr/bin/env ruby

ENV["LC_ALL"] = "C"

class SVN
  def exec(*args)
    system("svn", *args)
  end

  def svnread(*args)
    IO.popen(["svn", *args], &:readlines).each(&:chomp!)
  end

  def svnwrite(*args, &block)
    IO.popen(["svn", *args], "w", &block)
  end

  def update(*args)
    log = svnread("update", "--accept=postpone", *args)
    log[1...-1].grep(/^[AMU]/) {|l| l[5..-1]}
  end

  def propget(prop, *args)
    svnread("propget", prop, *args)
  end

  def propset(prop, *args, &block)
    if block
      svnwrite(*%w"propset --file -", prop, *args, &block)
    else
      exec("propset", prop, *args)
    end
  end

  def commit(log, *args)
    exec("ci", "-m", log, *args)
  end

  def last_rev
    svnread('log', '-r', 'HEAD', '-q')[1].match(/\Ar(?<rev>\d+) /)[:rev]
  end

  module Debugging
    def commit(*args)
      p args
    end
  end
end

svn = SVN.new

if ARGV[0] == "--debug"
  ARGV.shift
  svn.extend(SVN::Debugging)
end

unless ARGV.empty?
  Dir.chdir(ARGV.shift)
end

EXPANDTAB_IGNORED_FILES = [
  %r{\Accan/},
  %r{\Aext/json/},
  %r{\Aext/psych/},
  %r{\Amissing/},
  %r{\Astrftime\.c\z},
  %r{\Avsnprintf\.c\z},
  %r{\Areg.+\.(c|h)\z},
]

log = svn.update
log.select! {|l|
  /^\d/ !~ l and /\.bat\z/ !~ l and
  (/\A(?:config|[Mm]akefile|GNUmakefile|README)/ =~ File.basename(l) or
   /\A\z|\.(?:[chsy]|\d+|e?rb|tmpl|bas[eh]|z?sh|in|ma?k|def|src|trans|rdoc|ja|en|el|sed|awk|p[ly]|scm|mspec|html|)\z/ =~ File.extname(l))
}
files = log.select {|n| File.file?(n)}
unless files.empty?
  translit = trailing = eofnewline = expandtab = false

  files.grep(/\/ChangeLog\z/) do |changelog|
    if IO.foreach(changelog, "rb").any? {|line| !line.ascii_only?}
      tmp = changelog+".ascii"
      if system("iconv", "-f", "utf-8", "-t", "us-ascii//translit", changelog, out: tmp) and
          (File.size(tmp) - File.size(changelog)).abs < 10
        File.rename(tmp, changelog)
        translit = true
      else
        File.unlink(tmp) rescue nil
      end
    end
  end

  last_rev = svn.last_rev
  edit = files.select do |f|
    src = File.binread(f) rescue next
    trailing = trailing0 = true if src.gsub!(/[ \t]+$/, '')
    eofnewline = eofnewline0 = true if src.sub!(/(?<!\n)\z/, "\n")

    expandtab0 = false
    if last_rev && (f.end_with?('.c') || f.end_with?('.h') || f == 'insns.def') && EXPANDTAB_IGNORED_FILES.all? { |re| !f.match(re) }
      line_i = 0
      blames = svn.svnread('blame', f)
      src.gsub!(/^.*$/) do |line|
        blame = blames[line_i]
        line_i += 1
        if blame.match(/\A\s*#{last_rev}\s/) && line.start_with?("\t") # last-committed line with hard tabs
          expandtab = expandtab0 = true
          line.sub(/\A\t+/) { |tabs| ' ' * (8 * tabs.length) }
        else
          line
        end
      end
    end

    if trailing0 or eofnewline0 or expandtab0
      File.binwrite(f, src)
      true
    end
  end
  unless edit.empty?
    msg = [("remove trailing spaces" if trailing),
           ("append newline at EOF" if eofnewline),
           ("translit ChangeLog" if translit),
           ("expand tabs" if expandtab),
          ].compact
    svn.commit("* #{msg.join(', ')}.", *edit)
  end
  svn.propset("svn:eol-style", "LF", *files)
  exts = []
  files.grep(/\/extconf\.rb$/) do
    dir = $`
    prop = svn.propget("svn:ignore", dir)
    if prop.size < (prop |= %w[Makefile extconf.h mkmf.log]).size
      svn.propset("svn:ignore", dir) {|f| f.puts *prop}
      exts << dir
    end
  end
  svn.commit("* properties.", *files)
end
